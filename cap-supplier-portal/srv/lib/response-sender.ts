/**
 * Phase 6.5e — the supplier-response sender.
 *
 * ARCHITECTURE.md fixes the shape: *"A CAP development command can similarly
 * flush a committed response. Automatic scheduling is a later enhancement."*
 * So this drains the durable outbox when it is explicitly run, and nothing here
 * is a timer, a queue worker or an HTTP endpoint.
 *
 * The rule the whole file exists to keep: a transport outcome must never touch
 * the supplier's committed business decision. The supplier action already wrote
 * the order and its response row in one transaction; this code writes the
 * transport columns of `SupplierResponseDeliveries` and reads everything else.
 * `Orders` is never updated here — not on success, not on a refusal, not on a
 * conflict. A failed delivery means SAP has not heard about a decision, not
 * that the decision is any less made.
 */

import cds from '@sap/cds'
import { randomUUID } from 'node:crypto'
import { Orders as PortalOrders, SupplierResponseDeliveries, Suppliers } from '#cds-models/pih/portal'
import type { ResponseTransport } from './ci-transport'
import {
  buildSupplierResponsePayload,
  classify,
  describe,
  PayloadError,
  type DeliveryState,
  type ResponseOrder,
  type ResponseRow,
  type SupplierResponsePayload
} from './supplier-response'

/** What one row's attempt did, for the command's report and for the tests. */
export interface AttemptOutcome {
  responseId: string
  portalOrderId: string
  version: number
  decision: string
  /** Fresh for every attempt. Absent when the row was skipped or not sent. */
  correlationId?: string
  state: DeliveryState | 'SKIPPED'
  status?: number
  error?: string | null
  /** Present on a dry run, so an operator can read the exact bytes first. */
  payload?: SupplierResponsePayload
  /** The guarded write matched nothing: someone else moved the row mid-attempt. */
  conflicted?: boolean
}

export interface FlushSummary {
  scanned: number
  delivered: number
  failed: number
  pending: number
  unknown: number
  skipped: number
  outcomes: AttemptOutcome[]
}

export interface FlushOptions {
  transport: ResponseTransport
  /** Maximum rows to attempt in one run. */
  limit?: number
  /** Builds the payload and reports it without sending anything. */
  dryRun?: boolean
  /** Injected so tests can assert a fresh correlation ID per attempt. */
  newCorrelationId?: () => string
  log?: (line: string) => void
}

export const DEFAULT_LIMIT = 50

/**
 * Drains PENDING supplier responses.
 *
 * PENDING means both "never attempted" and "attempted and retryable", which is
 * the same vocabulary the ABAP coordinator uses on the outbound leg. DELIVERED,
 * FAILED and UNKNOWN rows are never picked up: a delivered row must not be
 * resent, and a failed or ambiguous one needs reconciliation rather than a
 * blind replay. Returning either to PENDING is a deliberate operator act and
 * this command does not do it by itself.
 */
export async function flushSupplierResponses(options: FlushOptions): Promise<FlushSummary> {
  const {
    transport,
    limit = DEFAULT_LIMIT,
    dryRun = false,
    newCorrelationId = randomUUID,
    log = () => {}
  } = options

  const summary: FlushSummary = {
    scanned: 0, delivered: 0, failed: 0, pending: 0, unknown: 0, skipped: 0, outcomes: []
  }

  // Oldest first, and within one order by version ascending. An acceptance must
  // reach SAP before the date update that supersedes it, and `createdAt` alone
  // would rely on two rows never sharing a timestamp.
  const rows = (await SELECT
    .from(SupplierResponseDeliveries)
    .where({ state: 'PENDING' })
    .orderBy('createdAt', 'version')
    .limit(limit)) as unknown as ResponseRow[]

  summary.scanned = rows.length
  if (!rows.length) {
    log('No PENDING supplier responses.')
    return summary
  }

  const orders = await readOrders(rows)

  // Once a response for an order does not reach SAP, every later response for
  // that same order is held back. Sending version 2 while version 1 is still
  // PENDING would make SAP refuse version 1 on the next run as stale, leaving a
  // row permanently FAILED for a decision that was in fact superseded rather
  // than rejected — a bookkeeping lie the outbox would never recover from.
  //
  // THIS GUARD IS WITHIN ONE RUN ONLY, and the scope is worth being exact
  // about. If version 1 ends FAILED or UNKNOWN it leaves the PENDING set
  // entirely, so a later run sees version 2 with nothing in front of it and
  // sends it. That is deliberate and contract-permitted — API_CONTRACTS.md
  // states that a newer response "contains the complete current supplier
  // response, so version gaps can be applied after validating the allowed
  // state" — and blocking it would instead strand the order behind a failure
  // that the newer response already supersedes. What it is NOT is a guarantee
  // that SAP sees every version in order; reconciling a FAILED or UNKNOWN row
  // against what SAP actually holds is a Phase 6.5f obligation.
  const blocked = new Set<string>()

  for (const row of rows) {
    if (blocked.has(row.order_ID)) {
      summary.skipped++
      summary.outcomes.push({
        responseId: row.responseId,
        portalOrderId: row.order_ID,
        version: row.version,
        decision: row.decision,
        state: 'SKIPPED',
        error: 'An earlier response for this order has not reached SAP yet.'
      })
      log(`SKIP  ${row.responseId} v${row.version} — an earlier response for this order is still pending.`)
      continue
    }

    const outcome = await attempt(row, orders.get(row.order_ID), {
      transport, dryRun, newCorrelationId, log,
      // Rows were selected as PENDING, so that is what the guarded write expects.
      expectedState: 'PENDING'
    })

    summary.outcomes.push(outcome)

    if (outcome.state === 'DELIVERED') summary.delivered++
    else if (outcome.state === 'FAILED') { summary.failed++; blocked.add(row.order_ID) }
    else if (outcome.state === 'PENDING') { summary.pending++; blocked.add(row.order_ID) }
    else if (outcome.state === 'UNKNOWN') { summary.unknown++; blocked.add(row.order_ID) }
    else summary.skipped++
  }

  return summary
}

/** Resolves each row's order and the order's supplier code, in two queries. */
async function readOrders(rows: ResponseRow[]): Promise<Map<string, ResponseOrder>> {
  const orderIds = [...new Set(rows.map(row => row.order_ID))]

  const orders = await SELECT
    .from(PortalOrders)
    .columns('ID', 'sourceSystem', 'sourceOrderId', 'sourceRevision', 'deliveryId', 'supplier_ID')
    .where({ ID: { in: orderIds } })

  const supplierIds = [...new Set(orders.map((order: any) => order.supplier_ID).filter(Boolean))]
  const suppliers = supplierIds.length
    ? await SELECT.from(Suppliers).columns('ID', 'supplierCode').where({ ID: { in: supplierIds } })
    : []

  const codeById = new Map(suppliers.map((supplier: any) => [supplier.ID, supplier.supplierCode]))

  return new Map(orders.map((order: any) => [order.ID, {
    ID: order.ID,
    sourceSystem: order.sourceSystem,
    sourceOrderId: order.sourceOrderId,
    sourceRevision: order.sourceRevision,
    deliveryId: order.deliveryId,
    supplierCode: codeById.get(order.supplier_ID)
  } as ResponseOrder]))
}

/**
 * One row: build, send, classify, record.
 *
 * Shared by the normal flush and by operator reconciliation, which differ only
 * in which state they expect the row to be in. Everything that decides what a
 * transport outcome means lives here and is never duplicated: the payload, the
 * fresh correlation ID, `classify`, `describe` and the guarded write.
 */
async function attempt(
  row: ResponseRow,
  order: ResponseOrder | undefined,
  context: Required<Pick<FlushOptions, 'transport' | 'dryRun' | 'newCorrelationId' | 'log'>>
    & { expectedState: DeliveryState }
): Promise<AttemptOutcome> {
  const base = {
    responseId: row.responseId,
    portalOrderId: row.order_ID,
    version: row.version,
    decision: row.decision
  }

  // A row that cannot be turned into a payload is a deterministic failure. It
  // is recorded as FAILED with the reason and never as PENDING, because no
  // amount of retrying makes a missing supplier code appear, and never as
  // DELIVERED, because nothing was sent.
  let payload: SupplierResponsePayload
  try {
    payload = buildSupplierResponsePayload(row, order as ResponseOrder)
  } catch (error: any) {
    const reason = error instanceof PayloadError ? `${error.code}: ${error.message}` : String(error?.message ?? error)
    // Nothing was sent, so a lost race here costs nothing but the bookkeeping.
    await record(row, 'FAILED', reason.slice(0, 255), null, context.expectedState)
    context.log(`FAIL  ${row.responseId} v${row.version} — ${reason}`)
    return { ...base, state: 'FAILED', error: reason }
  }

  if (context.dryRun) {
    context.log(`DRY   ${row.responseId} v${row.version} ${row.decision} — not sent.`)
    return { ...base, state: 'SKIPPED', payload, error: 'dry run' }
  }

  // One attempt, one fresh correlation ID. It identifies this attempt in the
  // Cloud Integration message log and nothing else; `responseId` is unchanged
  // and is what makes the replay idempotent at the RAP end.
  const correlationId = context.newCorrelationId()

  const result = await context.transport.send(payload, correlationId)
  const state = classify(result)
  const error = describe(result)

  const written = await record(row, state, error, correlationId, context.expectedState)

  if (!written) {
    // The request went out and somebody else owns the row now. Do NOT force the
    // write: whatever moved it did so with knowledge this call no longer has.
    // The row keeps its `responseId`, so nothing is lost that a later replay
    // cannot recover, and RAP answers a duplicate with ALREADY_APPLIED.
    const note =
      `the row left ${context.expectedState} while this attempt was in flight; ` +
      `its result (${state}, correlation ${correlationId}) was NOT written`
    context.log(`RACE  ${row.responseId} v${row.version} — ${note}`)
    return { ...base, correlationId, state, status: result.status, error, conflicted: true }
  }

  context.log(
    `${state.padEnd(5)} ${row.responseId} v${row.version} ${row.decision}` +
    ` — ${result.answered ? `HTTP ${result.status}` : 'no answer'} (correlation ${correlationId})`
  )

  return { ...base, correlationId, state, status: result.status, error }
}

// ------------------------------------------------------- operator reconciliation

/** Why a reconciliation was refused before anything was sent. */
export type ReconcileRefusal =
  | 'MISSING_RESPONSE_ID'
  | 'NOT_FOUND'
  | 'NOT_UNKNOWN'
  | 'ORDER_UNREADABLE'
  | 'STATE_CHANGED'

export interface ReconcileOptions {
  /** The durable response to replay. Never generated, always supplied. */
  responseId: string
  transport: ResponseTransport
  newCorrelationId?: () => string
  log?: (line: string) => void
}

export interface ReconcileResult {
  refused?: ReconcileRefusal
  message?: string
  outcome?: AttemptOutcome
}

/**
 * Resolves ONE `UNKNOWN` delivery, by replaying it.
 *
 * `UNKNOWN` means the receiver may or may not have committed, and the sender
 * refuses to guess — so nothing drains it automatically and this is the only
 * way it moves. It is an operator action by design.
 *
 * **It does not ask SAP anything.** CAP has no direct dependency on SAP and
 * gains none here; Cloud Integration stays the only mediation layer. The
 * question "did SAP already get this?" is answered by SENDING IT AGAIN rather
 * than by reading SAP, which is sound because RAP's idempotency is
 * runtime-proven: the same `responseId` with the same content returned HTTP 204
 * with `LastChangedAt` unmoved. So if the original landed, the replay is a
 * no-op; if it never landed, the replay applies it; and if the answer is
 * ambiguous again, the row simply stays `UNKNOWN` and nothing has been lost.
 *
 * Nothing about the supplier's decision is re-made. The payload is rebuilt from
 * the same durable row, under the same `responseId`, at the same version, and
 * `Orders` is never touched. Only the transport columns move.
 */
export async function reconcileSupplierResponse(options: ReconcileOptions): Promise<ReconcileResult> {
  const { responseId, transport, newCorrelationId = randomUUID, log = () => {} } = options

  if (!responseId || !responseId.trim()) {
    return { refused: 'MISSING_RESPONSE_ID', message: 'A responseId must be supplied explicitly.' }
  }

  const row = (await SELECT.one
    .from(SupplierResponseDeliveries)
    .where({ responseId: responseId.trim() })) as unknown as ResponseRow | null

  if (!row) {
    return { refused: 'NOT_FOUND', message: `No supplier response exists with responseId ${responseId}.` }
  }

  // Only UNKNOWN is reconcilable, and each refusal says why in its own terms.
  if (row.state !== 'UNKNOWN') {
    const because: Record<string, string> = {
      DELIVERED: 'it already reached SAP; replaying it would be a pointless duplicate',
      FAILED: 'SAP refused it deterministically, so a replay would be refused identically — ' +
              'the payload or the order state has to change first, which is a business decision, not a transport one',
      PENDING: 'it is still queued and the normal flush will send it'
    }
    return {
      refused: 'NOT_UNKNOWN',
      message:
        `Response ${responseId} is ${row.state}, not UNKNOWN: ` +
        `${because[String(row.state)] ?? 'only an UNKNOWN delivery can be reconciled'}.`
    }
  }

  const order = (await readOrders([row])).get(row.order_ID)
  if (!order) {
    return { refused: 'ORDER_UNREADABLE', message: `Response ${responseId} points at no readable order.` }
  }

  log(`Replaying ${responseId} v${row.version} ${row.decision} (attempt ${(row.attempts ?? 0) + 1}).`)

  const outcome = await attempt(row, order, {
    transport,
    dryRun: false,
    newCorrelationId,
    log,
    // The compare-and-set guard: this write lands only if the row is still the
    // UNKNOWN one that was read a moment ago.
    expectedState: 'UNKNOWN'
  })

  if (outcome.conflicted) {
    return { refused: 'STATE_CHANGED', message: outcome.error ?? 'the row changed during the attempt', outcome }
  }

  return { outcome }
}

/**
 * Persists the transport outcome for one row, and only the transport outcome.
 *
 * Each row commits in its own transaction, so a crash part-way through a flush
 * keeps every result already recorded. The window this cannot close is the one
 * between SAP applying a response and this update committing — and that is
 * precisely why the row keeps its `responseId`: the next run replays the same
 * identity and RAP answers ALREADY_APPLIED, which is runtime-proven.
 *
 * `responseId`, `version`, `decision`, `estimatedDeliveryDate`, `reason` and
 * `respondedAt` are absent from this statement on purpose. They are the
 * supplier's committed answer and transport has no business editing them.
 */
/**
 * Persists the transport outcome for one row, and only the transport outcome.
 *
 * Each row commits in its own transaction, so a crash part-way through a flush
 * keeps every result already recorded. The window this cannot close is the one
 * between SAP applying a response and this update committing — and that is
 * precisely why the row keeps its `responseId`: the next run replays the same
 * identity and RAP answers ALREADY_APPLIED, which is runtime-proven.
 *
 * `responseId`, `version`, `decision`, `estimatedDeliveryDate`, `reason` and
 * `respondedAt` are absent from this statement on purpose. They are the
 * supplier's committed answer and transport has no business editing them.
 *
 * THE UPDATE IS GUARDED ON THE STATE WE READ. `expectedState` is part of the
 * WHERE clause, so this is a compare-and-set: if anything moved the row since
 * it was read — a concurrent flush, or an operator reconciling by hand — the
 * statement matches nothing, returns 0 and writes nothing. That is the whole
 * concurrency safeguard, and it needs no lock table and no lease, because the
 * database already resolves the race for us.
 *
 * Returns true when the row was ours to write.
 */
async function record(
  row: ResponseRow,
  state: DeliveryState,
  error: string | null,
  correlationId: string | null,
  expectedState: DeliveryState
): Promise<boolean> {
  return await cds.tx(async () => {
    const affected = await UPDATE(SupplierResponseDeliveries)
      .set({
        state,
        attempts: (row.attempts ?? 0) + 1,
        lastAttemptAt: new Date().toISOString(),
        lastError: error,
        lastCorrelationId: correlationId
      } as any)
      .where({ ID: row.ID, state: expectedState })

    return Number(affected) === 1
  })
}
