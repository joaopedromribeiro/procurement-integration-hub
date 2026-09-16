import cds from '@sap/cds'
import { randomUUID } from 'node:crypto'
import { DeliveryReceipts, Orders, Suppliers } from '#cds-models/pih/portal'
import { deliveryHash, isFailure, normalizeDelivery, type NormalizedDelivery } from './lib/ingestion'

/**
 * Phase 4.3 — the CI → CAP ingestion handler.
 *
 * One custom CREATE handler on a service-local contract entity. The caller
 * never reaches persistence directly: the wire shape is the nested *Mapped CAP
 * order* and the stored shape is the flat `pih.portal` model, and this handler
 * is the only thing that converts one into the other.
 *
 * Everything runs inside the request's transaction, so a rejection at any point
 * leaves nothing behind.
 */
export default class IntegrationService extends cds.ApplicationService {

  init(): Promise<void> {
    this.on('CREATE', 'Orders', req => this.ingest(req as any))
    return super.init()
  }

  private async ingest(req: any) {
    const correlationId = req.headers?.['x-correlation-id'] ?? randomUUID()
    req.http?.res?.setHeader?.('X-Correlation-ID', correlationId)

    const normalized = normalizeDelivery(req.data)
    if (isFailure(normalized)) {
      return this.refuse(req, 400, normalized.code, normalized.message, correlationId, false)
    }

    // A delivery this endpoint has already accepted is answered from the stored
    // receipt, never by re-running the ingestion.
    const existing = await this.findReceipt(normalized)
    if (existing) {
      return this.answerReplay(req, existing, normalized, correlationId)
    }

    const supplier = await SELECT.one
      .from(Suppliers)
      .columns('ID', 'active')
      .where({ supplierCode: normalized.supplierCode })

    if (!supplier || supplier.active === false) {
      return this.refuse(
        req, 400, 'UNKNOWN_SUPPLIER',
        `supplierCode "${normalized.supplierCode}" is not an active supplier in this portal.`,
        correlationId, false
      )
    }

    const portalOrderId = cds.utils.uuid()
    const receivedAt = new Date().toISOString()

    try {
      await this.persist(normalized, supplier.ID!, portalOrderId, receivedAt)
    } catch (error: any) {
      return this.translateWriteFailure(req, error, normalized, correlationId)
    }

    this.pinStatus(req, 201)
    return this.receipt(normalized, portalOrderId, 'RECEIVED', receivedAt)
  }

  /**
   * Order and its lines in one deep insert, then the deduplication record — one
   * transactional unit. CAP runs each request in a single transaction, so a
   * failure in either statement rolls back both and no partial order survives.
   *
   * Every server-owned value is set here and none of them is read from the
   * payload: the portal's UUID, the RECEIVED status, responseVersion 0 and both
   * timestamps. The caller cannot set them because they are not in the contract.
   */
  private async persist(
    delivery: NormalizedDelivery,
    supplierId: string,
    portalOrderId: string,
    receivedAt: string
  ) {
    await INSERT.into(Orders).entries({
      ID: portalOrderId,
      sourceSystem: delivery.sourceSystem,
      sourceOrderId: delivery.sourceOrderId,
      sourceRevision: delivery.sourceRevision,
      externalOrderNumber: delivery.externalOrderNumber,
      supplier_ID: supplierId,
      currency: delivery.currency,
      totalAmount: delivery.totalAmount,
      status: 'RECEIVED',
      responseVersion: 0,
      deliveryId: delivery.deliveryId,
      receivedAt,
      modifiedAt: receivedAt,
      items: delivery.lines.map(line => ({
        ID: cds.utils.uuid(),
        sourceItemId: line.sourceItemId,
        lineNumber: line.lineNumber,
        productCode: line.productCode,
        description: line.description,
        quantity: line.quantity,
        uom: line.uom,
        unitPrice: line.unitPrice,
        currency: line.currency,
        lineAmount: line.lineAmount
      }))
    } as any)

    await INSERT.into(DeliveryReceipts).entries({
      ID: cds.utils.uuid(),
      sourceSystem: delivery.sourceSystem,
      deliveryId: delivery.deliveryId,
      requestHash: deliveryHash(delivery),
      sourceOrderId: delivery.sourceOrderId,
      sourceRevision: delivery.sourceRevision,
      order_ID: portalOrderId,
      status: 'RECEIVED',
      receivedAt
    } as any)
  }

  private findReceipt(delivery: NormalizedDelivery) {
    return SELECT.one
      .from(DeliveryReceipts)
      .where({ sourceSystem: delivery.sourceSystem, deliveryId: delivery.deliveryId })
  }

  /**
   * Same delivery key, already committed. Identical content returns the original
   * receipt with 200; different content is a conflict and must not overwrite the
   * order that is already stored.
   */
  private answerReplay(req: any, stored: any, delivery: NormalizedDelivery, correlationId: string) {
    if (stored.requestHash !== deliveryHash(delivery)) {
      return this.refuse(
        req, 409, 'DELIVERY_PAYLOAD_CONFLICT',
        `deliveryId ${delivery.deliveryId} was already accepted with different content. The stored order is unchanged; use a new deliveryId for a corrected snapshot.`,
        correlationId, false
      )
    }

    this.pinStatus(req, 200)
    return this.receipt(delivery, stored.order_ID, stored.status, stored.receivedAt)
  }

  /**
   * A write that failed on a uniqueness rule is a conflict, not a server error.
   *
   * Two distinct rules can fire here and they mean different things. A delivery
   * collision means a concurrent request won the race with the same deliveryId,
   * so the committed receipt is re-read and answered exactly as a sequential
   * replay would be. A source-order collision means this source order and
   * revision were already ingested under a *different* delivery, which the
   * contract answers with 409 rather than a second copy of the same order.
   */
  private async translateWriteFailure(
    req: any, error: any, delivery: NormalizedDelivery, correlationId: string
  ) {
    const text = `${error?.message ?? ''} ${error?.code ?? ''}`

    if (/delivery/i.test(text)) {
      const committed = await this.findReceipt(delivery)
      if (committed) return this.answerReplay(req, committed, delivery, correlationId)
    }

    if (/sourceOrder/i.test(text)) {
      const conflicting = await SELECT.one
        .from(Orders)
        .columns('ID', 'deliveryId')
        .where({
          sourceSystem: delivery.sourceSystem,
          sourceOrderId: delivery.sourceOrderId,
          sourceRevision: delivery.sourceRevision
        })

      return this.refuse(
        req, 409, 'SOURCE_ORDER_ALREADY_INGESTED',
        `Source order ${delivery.sourceOrderId} revision ${delivery.sourceRevision} was already ingested as portal order ${conflicting?.ID} under deliveryId ${conflicting?.deliveryId}. Reconcile against that delivery instead of resending.`,
        correlationId, false
      )
    }

    throw error
  }

  /**
   * Pins the HTTP status of this response.
   *
   * The REST adapter's create middleware ends with `return { result, status: 201 }`
   * and the adapter applies it as `if (status && res.statusCode === 200) res.status(status)`
   * — "only set status if not yet modified". A handler can therefore choose any
   * status except 200, which is exactly the one the ingestion contract requires
   * for an exact replay. Freezing `res.status` after choosing it is the narrowest
   * way to hold 200; nothing later in the success path needs to change it.
   */
  private pinStatus(req: any, status: number) {
    const res = req.http?.res
    if (!res) return
    res.status(status)
    res.status = () => res
  }

  /** The receipt defined in API_CONTRACTS.md. Nothing else leaves this service. */
  private receipt(
    delivery: NormalizedDelivery, portalOrderId: string, status: string, receivedAt: string
  ) {
    return {
      deliveryId: delivery.deliveryId,
      sourceOrderId: delivery.sourceOrderId,
      portalOrderId,
      status,
      receivedAt
    }
  }

  /** The error envelope defined in API_CONTRACTS.md. */
  private refuse(
    req: any, status: number, code: string, message: string,
    correlationId: string, retryable: boolean
  ): never {
    req.reject({ status, code, message, correlationId, retryable })
    throw new Error('unreachable')
  }
}
