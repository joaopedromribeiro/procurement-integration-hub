/**
 * Phase 4.2 — CAP Supplier Portal persistence.
 *
 * This is the portal's own domain, not a copy of the SAP purchase-order tables.
 * SAP RAP owns the commercial lifecycle; the portal stores the snapshots it was
 * sent, keeps its own identities, and will later record what a supplier decided
 * about them (ADR-004).
 *
 * The field set, names, sizes and scales come from the CAP persistence table in
 * docs/architecture/domain-model.md and the mapped CAP order in API_CONTRACTS.md.
 * Where the two layers name the same fact differently — SAP's `Material` against
 * the portal's `productCode`, `EA` against `PCE` — the portal name is used,
 * because the boundary mapping is the point of the contract.
 *
 * Phase 4.2 defines persistence only. No service, no handler and no rule lives
 * here; ingestion is Phase 4.3 and supplier decisions are Phase 4.4.
 */
namespace pih.portal;

using {cuid} from '@sap/cds/common';

/** ISO 4217 alphabetic code. Only EUR is supported initially. */
type CurrencyCode : String(3);

/** Portal-side unit code. The boundary maps SAP's `EA` to `PCE` on ingestion. */
type UnitCode : String(3);

/** External supplier identity; the portal's own key stays a UUID. */
type SupplierCode : String(10);

/**
 * Server-owned. A caller may never supply it: ingestion always produces
 * RECEIVED, and only a supplier decision in Phase 4.4 moves it on.
 */
type PortalOrderStatus : String(10) enum {
    RECEIVED;
    ACCEPTED;
    REJECTED;
}

/**
 * The durable delivery state one committed attempt produced. Deliberately the
 * same four values as `SupplierResponseDeliveries.state`, because an attempt's
 * outcome is exactly the state it moved the row to. A dry run produces no
 * attempt row at all, so there is no SKIPPED here and no fifth state.
 */
type SupplierResponseAttemptOutcome : String(10) enum {
    PENDING;
    DELIVERED;
    FAILED;
    UNKNOWN;
}

/**
 * Why an attempt ended as it did, as a closed vocabulary. It answers a
 * different question from `outcome`: the outcome is the durable state, this is
 * the reason. `NO_ANSWER` deliberately does not claim whether the request was
 * sent — separating pre-send from ambiguous is Phase 7.4 work.
 */
type SupplierResponseAttemptErrorCategory : String(12) enum {
    NONE;
    REFUSED;
    TRANSIENT;
    AMBIGUOUS;
    NO_ANSWER;
    PAYLOAD;
}

/**
 * Supplier master data held by the portal. Deliberately thin: a controlled
 * synthetic reference used to resolve `supplierCode` on ingestion and to scope
 * supplier access in Phase 4.4, not a master-data replication.
 */
@assert.unique.supplierCode: [supplierCode]
entity Suppliers : cuid {
    supplierCode : SupplierCode not null;
    name         : String(100);
    active       : Boolean default true;

    /**
     * Association, not composition: an order does not belong to the supplier's
     * lifecycle. Deleting a supplier must never delete the orders it received.
     */
    orders       : Association to many Orders
                       on orders.supplier = $self;
}

/**
 * One purchase-order snapshot as received by the portal.
 *
 * `ID` is the portal's own identity, independent of SAP. The source identity is
 * kept separately and in full — system, order UUID and revision — because the
 * two systems correlate through that triple and never through a shared key.
 */
@assert.unique.sourceOrder: [
    sourceSystem,
    sourceOrderId,
    sourceRevision
]
entity Orders : cuid {
    sourceSystem          : String(30) not null;
    sourceOrderId         : UUID not null;
    sourceRevision        : Integer not null;

    /** Human-readable number allocated by SAP on submit. Display only here. */
    externalOrderNumber   : String(20);

    supplier              : Association to one Suppliers not null;

    currency              : CurrencyCode;

    @Measures.ISOCurrency: currency
    totalAmount           : Decimal(19, 2);

    status                : PortalOrderStatus default #RECEIVED;

    // Supplier-decision columns. Phase 4.2 persists them and writes none of
    // them; the accept/reject/date commands that fill them are Phase 4.4.
    estimatedDeliveryDate : Date;
    rejectionReason       : String(255);
    responseVersion       : Integer default 0;

    /** Identity of the delivery that carried this snapshot. */
    deliveryId            : UUID not null;

    @cds.on.insert       : $now
    receivedAt            : Timestamp;

    @cds.on.insert       : $now
    @cds.on.update       : $now
    modifiedAt            : Timestamp;

    /**
     * Composition: the lines exist only as part of this order, are created with
     * it by the Phase 4.3 deep insert, and are deleted with it.
     */
    items                 : Composition of many OrderItems
                                on items.order = $self;
}

/**
 * One line of a received order. `sourceItemId` preserves the SAP item identity
 * so a later supplier response can be correlated line by line.
 */
@assert.unique.line      : [
    order,
    lineNumber
]
@assert.unique.sourceItem: [
    order,
    sourceItemId
]
entity OrderItems : cuid {
    order        : Association to one Orders not null;
    sourceItemId : UUID not null;
    lineNumber   : Integer not null;
    productCode  : String(40);
    description  : String(100);

    @Measures.Unit       : uom
    quantity     : Decimal(13, 3);
    uom          : UnitCode;

    @Measures.ISOCurrency: currency
    unitPrice    : Decimal(19, 4);
    currency     : CurrencyCode;

    @Measures.ISOCurrency: currency
    lineAmount   : Decimal(19, 2);
}

/**
 * Deduplication record for one delivery attempt, written in the same
 * transaction as the order it produced.
 *
 * Specified in the CAP persistence table of docs/architecture/domain-model.md
 * as "source system + deliveryId unique; normalized request hash; source order
 * identity; portal order ID; original receipt; createdAt". That table marks it
 * phase 5, and Phase 4.3 pulls it forward deliberately: the ingestion contract
 * requires an exact replay to return the *original* receipt and a conflicting
 * reuse of the same deliveryId to return 409, and neither is answerable without
 * a stored hash and a stored receipt. The rest of the Phase 5 delivery
 * machinery — DeliveryIntent, SupplierResponseDelivery, attempt history — is
 * not pulled forward with it.
 *
 * The unique constraint is the point of the entity. The contract requires
 * parallel duplicates to be "resolved through database uniqueness and rereading
 * the committed receipt", not by a read-before-insert check that two concurrent
 * requests can both pass.
 */
@assert.unique.delivery: [
    sourceSystem,
    deliveryId
]
entity DeliveryReceipts : cuid {
    sourceSystem   : String(30) not null;
    deliveryId     : UUID not null;

    /** sha256 over the normalized delivery content; see srv/lib/ingestion.ts. */
    requestHash    : String(64) not null;

    sourceOrderId  : UUID not null;
    sourceRevision : Integer not null;

    /** The order this delivery produced: `portalOrderId` in the receipt. */
    order          : Association to one Orders not null;

    // The receipt exactly as it was first returned, so a replay re-reads it
    // rather than recomputing it from the order's current state.
    status         : PortalOrderStatus default #RECEIVED;
    receivedAt     : Timestamp;

    @cds.on.insert: $now
    createdAt      : Timestamp;
}

/**
 * The supplier's decision, captured as an immutable outbound response that has
 * not yet been sent to SAP.
 *
 * Specified in the CAP persistence table of docs/architecture/domain-model.md as
 * "responseId: UUID; order association; version; immutable response payload;
 * state PENDING/DELIVERED/FAILED/UNKNOWN; attempt count; last error; timestamps".
 * That table marks it phase 5, and Phase 4.4 pulled forward only what a supplier
 * decision needs: the identity, the version, the payload and the state — because
 * nothing in Phase 4 ever attempted a delivery, so every row written there was
 * PENDING and stayed PENDING.
 *
 * Phase 6.5e completes the documented field set. The sender now exists, so
 * "attempt count, last error, timestamps" stop being a future note and become
 * `attempts`, `lastError` and `lastAttemptAt`. `lastCorrelationId` is the one
 * addition beyond that line: it is the only way to find the Cloud Integration
 * message processing log for an attempt after the fact, which is what Phase 6.5f
 * reconciliation has to do when a row ends UNKNOWN. It is transport metadata and
 * never business identity — the correlation ID changes on every attempt while
 * `responseId` never does.
 *
 * Everything above `state` is immutable once written. The sender writes only the
 * transport columns, and never the decision, the version or the payload: a
 * transport outcome must not be able to edit the supplier's committed answer.
 *
 * The row is written in the same transaction as the decision it records, so an
 * order can never be ACCEPTED with no pending response, nor carry a pending
 * response while still RECEIVED.
 */
@assert.unique.responseId  : [responseId]
@assert.unique.orderVersion: [
    order,
    version
]
entity SupplierResponseDeliveries : cuid {
    /** Client-generated and stable: the caller's idempotency key. */
    responseId            : UUID not null;

    order                 : Association to one Orders not null;

    /** The `responseVersion` this response assigned. Starts at 1. */
    version               : Integer not null;

    // The immutable payload, exactly the facts the Phase 5 sender will submit.
    decision              : PortalOrderStatus not null;
    estimatedDeliveryDate : Date;
    reason                : String(255);
    respondedAt           : Timestamp;

    /**
     * Transport state, deliberately separate from the order's business status
     * (ADR-010). Phase 4.4 only ever wrote PENDING; Phase 6.5e's sender is what
     * makes DELIVERED, FAILED and UNKNOWN reachable.
     *
     * PENDING is both "never attempted" and "attempted, retryable", exactly as
     * the ABAP coordinator returns a retryable intent to PENDING rather than
     * inventing a fifth value. `attempts` is what tells the two apart.
     */
    state                 : String(10) default 'PENDING';

    /** Attempts made, including the one that succeeded. Never reset. */
    attempts              : Integer default 0;

    /** When the most recent attempt ran, whatever its outcome. */
    lastAttemptAt         : Timestamp;

    /**
     * Transport diagnosis for the most recent attempt: a status code and a
     * short safe reason, never a response body, a header or a credential.
     */
    lastError             : String(255);

    /** Transport metadata for the most recent attempt. Not business identity. */
    lastCorrelationId     : UUID;

    @cds.on.insert: $now
    createdAt             : Timestamp;

    /**
     * Phase 7.3 diagnostics. The four fields above stay the business fast path
     * and are never replaced by a join against this collection; history exists
     * to explain how the row reached its state, not to define it.
     *
     * A composition, because an attempt has no meaning without the response it
     * was an attempt at, and must be deleted with it.
     */
    attemptHistory        : Composition of many SupplierResponseDeliveryAttempts
                                on attemptHistory.delivery = $self;
}

/**
 * One transport attempt against one committed supplier response.
 *
 * Diagnostics and audit only. Deleting every row here must leave business
 * behaviour identical: nothing reads this collection to decide anything, and
 * the parent's `attempts`, `lastAttemptAt`, `lastError` and `lastCorrelationId`
 * remain the durable fast path.
 *
 * A row is inserted only inside the transaction whose guarded compare-and-set
 * won, and only when it won. A losing runner writes nothing, because history
 * that records a discarded outcome is worse than no history.
 *
 * History begins at the Phase 7.3 deployment. Parent rows written earlier may
 * legitimately show `attempts` above zero with no rows here; that is historical
 * truth and no backfill is implied or permitted.
 */
@assert.unique.attempt: [
    delivery,
    attemptNumber
]
entity SupplierResponseDeliveryAttempts : cuid {
    delivery      : Association to one SupplierResponseDeliveries not null;

    /**
     * The parent's `attempts` value this attempt committed, so the two can
     * never disagree. The unique constraint above is a data-integrity backstop
     * that keeps duplicate audit history out of the table; it is not the
     * concurrency mechanism, which remains the parent's compare-and-set.
     */
    attemptNumber : Integer not null;

    /**
     * Transport-attempt identity, fresh for every attempt and never business
     * identity. Nullable because an attempt can end before any transport
     * attempt exists — a payload that cannot be built is never sent.
     */
    correlationId : UUID;

    startedAt     : Timestamp not null;
    durationMs    : Integer not null;
    outcome       : SupplierResponseAttemptOutcome not null;

    /** Null when the transport observed no HTTP answer. */
    httpStatus    : Integer;

    errorCategory : SupplierResponseAttemptErrorCategory not null;

    /** The same short, sanitised diagnosis as the parent's `lastError`. */
    errorSummary  : String(255);
}
