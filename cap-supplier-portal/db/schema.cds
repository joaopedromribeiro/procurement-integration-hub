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
 * That table marks it phase 5, and Phase 4.4 pulls forward only what a supplier
 * decision needs: the identity, the version, the payload and the state. Attempt
 * count, last error and the sender itself stay in Phase 5, because nothing in
 * Phase 4 ever attempts a delivery — every row written here is PENDING and stays
 * PENDING.
 *
 * It is written in the same transaction as the decision it records, so an order
 * can never be ACCEPTED with no pending response, nor carry a pending response
 * while still RECEIVED.
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
     * (ADR-010). Phase 4.4 only ever writes PENDING; DELIVERED, FAILED and
     * UNKNOWN become reachable when a sender exists in Phase 5.
     */
    state                 : String(10) default 'PENDING';

    @cds.on.insert: $now
    createdAt             : Timestamp;
}
