/**
 * Phase 4.3 — integration-facing ingestion boundary.
 *
 * This service is the CI → CAP edge from API_CONTRACTS.md. It is separate from
 * the supplier-facing service of Phase 4.4 so the two can carry different
 * permissions (ADR-005), and it exposes no persistence entity: `Orders` here is
 * a service-local contract shape, not a projection on `pih.portal.Orders`.
 *
 * The element structure is the *Mapped CAP order* from API_CONTRACTS.md and is
 * deliberately not the persistence shape — nested `source`, `amount`, `product`,
 * `orderedQuantity` and `unitPrice` objects, with monetary and quantity values
 * as decimal strings per the common rules. A custom CREATE handler maps it into
 * persistence; there is no deep insert from the wire.
 */
@protocol: 'rest'
@path    : '/rest/integration/v1'
service IntegrationService {

  /** Decimal transported as a string: "no scientific notation" (common rules). */
  type DecimalString : String(30);

  type InboundSource : {
    system      : String(30);
    orderId     : UUID;
    orderNumber : String(20);
    revision    : Integer;
  };

  type InboundMoney : {
    currency : String(3);
    value    : DecimalString;
  };

  type InboundProduct : {
    code        : String(40);
    description : String(100);
  };

  type InboundQuantity : {
    value : DecimalString;
    unit  : String(3);
  };

  type InboundLine : {
    sourceItemId    : UUID;
    lineNumber      : Integer;
    product         : InboundProduct;
    orderedQuantity : InboundQuantity;
    unitPrice       : InboundMoney;
    lineAmount      : DecimalString;
  };

  /** The receipt defined in API_CONTRACTS.md, returned on 201 and on replay. */
  type DeliveryReceipt : {
    deliveryId    : UUID;
    sourceOrderId : UUID;
    portalOrderId : UUID;
    status        : String(10);
    receivedAt    : Timestamp;
  };

  /**
   * `POST /rest/integration/v1/Orders`. Insert-only: the integration client may
   * deliver a snapshot and may not read, change or delete anything through this
   * service. `deliveryId` is the caller's key because the delivery, not the
   * order, is what the caller controls and replays.
   */
  @insertonly
  entity Orders {
        /**
         * Declared as String(36), not UUID, on purpose. CAP generates a value for
         * a UUID-typed key when the caller omits it, which would turn the
         * contract's mandatory delivery identity into an optional one and accept
         * a message with no `Idempotency-Key` equivalent at all. The canonical
         * UUID form is enforced in the handler instead.
         */
    key deliveryId    : String(36);
        schemaVersion : String(10);
        source        : InboundSource;
        supplierCode  : String(10);
        amount        : InboundMoney;
        lines         : many InboundLine;
  }
}
