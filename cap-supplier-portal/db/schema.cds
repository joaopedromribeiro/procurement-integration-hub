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

    supplier              : Association to one Suppliers;

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
