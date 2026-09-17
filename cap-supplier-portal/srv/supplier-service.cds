using {pih.portal as portal} from '../db/schema';

/**
 * Phase 4.4 — the supplier-facing service.
 *
 * Separate from `IntegrationService` because the two have different callers and
 * will have different authentication and permissions (ADR-005): one is a machine
 * delivering snapshots, the other is a person deciding about them.
 *
 * The read model is a `@readonly` projection with a row filter, which is what
 * ARCHITECTURE.md prescribes — "generated READ support is appropriate with
 * authorization filters; ingestion and decisions require custom handlers, not
 * unrestricted generic CRUD". So reads are generated and scoped; every decision
 * is an explicit action with its own handler. There is no writable path to a
 * status field anywhere in this service.
 */
// `SupplierPortalUser` is a real application role, not CAP's `authenticated-user`
// pseudo-role. The distinction matters for exactly the reason ADR-005 separates
// the two services: a client-credentials token minted for SAP's inbound
// integration is also an authenticated user, so `authenticated-user` would have
// let the integration client read supplier orders. A named role cannot be reused
// that way, and only a named role reaches `xs-security.json` — CAP's
// `cds compile --to xsuaa` skips the pseudo-roles when generating scopes.
// Plain comments, not `/** */`: a doc comment here overrides the service's own.
@protocol: 'rest'
@path    : '/rest/supplier/v1'
@requires: 'SupplierPortalUser'
service SupplierService {

  /** The result of any supplier decision, per API_CONTRACTS.md. */
  type SupplierDecision : {
    portalOrderId          : UUID;
    externalOrderNumber    : String(20);
    status                 : String(10);
    responseVersion        : Integer;
    estimatedDeliveryDate  : Date;
    rejectionReason        : String(255);
    respondedAt            : Timestamp;

    /** Transport state, never a claim that SAP has been updated. */
    responseDeliveryStatus : String(10);
  };

  /**
   * One line of a received order, as the supplier sees it.
   *
   * `sourceItemId` is omitted: it is SAP's item identity, needed by the Phase 5
   * correlation and by nothing the supplier does.
   */
  @readonly
  entity OrderItems as projection on portal.OrderItems {
    ID,

    /**
     * The parent key, exposed under the same public name the order carries, so
     * the composition resolves without publishing the `order_ID` foreign key.
     * It repeats the id the supplier already used to address the order.
     */
    order.ID as portalOrderId,

    lineNumber,
    productCode,
    description,
    quantity,
    uom,
    unitPrice,
    currency,
    lineAmount
  }

  /**
   * The supplier's own orders. The element list is explicit and deliberately
   * short: `sourceSystem`, `sourceOrderId`, `sourceRevision`, `deliveryId` and
   * the supplier foreign key are all omitted, because they are SAP correlation
   * and portal bookkeeping rather than anything a supplier acts on.
   */
  @readonly
  entity Orders as projection on portal.Orders {
    ID                  as portalOrderId,

    /**
     * The caller's own code. Exposed because the row filter is applied to this
     * projection and must be expressible over its own elements; it tells the
     * supplier nothing it did not already authenticate as.
     */
    supplier.supplierCode as supplierCode,

    externalOrderNumber,
    status,
    currency,
    totalAmount,
    estimatedDeliveryDate,
    rejectionReason,
    responseVersion,
    receivedAt,
    items               : redirected to OrderItems on items.portalOrderId = $self.portalOrderId
  }
  actions {
    // Action parameters are declared without `not null` deliberately. CAP's own
    // ASSERT_MANDATORY check runs before any handler and answers in the
    // framework's envelope, which would make the contract's error codes and
    // correlation id unreachable for the commonest mistakes. Requiredness is
    // enforced in the handler instead, so every supplier-facing 400 looks alike.
    /**
     * `POST /rest/supplier/v1/Orders/{portalOrderId}/accept`
     *
     * `responseId` is the caller's stable idempotency key; `expectedResponseVersion`
     * is the precondition that stops a stale client overwriting a newer decision.
     * `estimatedDeliveryDate` is optional on acceptance — an omitted date means
     * unknown, not today.
     */
    action accept(
                  responseId : UUID,
                  expectedResponseVersion : Integer,
                  estimatedDeliveryDate : Date
                ) returns SupplierDecision;

    /**
     * `POST /rest/supplier/v1/Orders/{portalOrderId}/reject`
     *
     * A reason is mandatory and a delivery date is forbidden, so `reject` takes
     * no date parameter at all rather than validating one away.
     */
    action reject(
                  responseId : UUID,
                  expectedResponseVersion : Integer,
                  reason : String(255)
                ) returns SupplierDecision;

    /**
     * `POST /rest/supplier/v1/Orders/{portalOrderId}/updateEstimatedDeliveryDate`
     *
     * Only on an already accepted order. Keeps the decision ACCEPTED and takes a
     * new `responseId` and a new version.
     */
    action updateEstimatedDeliveryDate(
                                       responseId : UUID,
                                       expectedResponseVersion : Integer,
                                       estimatedDeliveryDate : Date
                                     ) returns SupplierDecision;
  }
}
