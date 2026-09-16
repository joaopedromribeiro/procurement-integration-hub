# Phase 3.2 — UI annotations through metadata extensions

Status: **SAP runtime-verified complete.** Two `#CUSTOMER` metadata extensions drive a working Fiori Elements List Report and Object Page over the Phase 3.1 OData V4 service. `@Metadata.layer`, `@UI.headerInfo`, `@UI.lineItem`, `@UI.selectionField`, `@UI.identification` and `@UI.facet` with `#IDENTIFICATION_REFERENCE`, `#LINEITEM_REFERENCE` and `targetElement: '_Items'` are all activated and confirmed in Fiori Elements Preview. No Phase 2 source, RAP behavior, CDS projection, behavior definition, service definition or test was touched.

## Target baseline

SAP_BASIS 758 SP01 (SAPK-75801INSAPBASIS), S4CORE 108 SP01 (SAPK-10801INS4CORE), ADT Core 3.60.3 / Business Object Tools 1.209.0, Eclipse 4.40.0. Fiori Elements Preview launched from service binding `ZJP_UI_PURCHASEORDER_O4`, entity set `PurchaseOrders`. Every statement below was observed on this target and must not be generalized.

## Verification status

| Construct | Status |
| --- | --- |
| `@Metadata.layer: #CUSTOMER` | **Runtime-verified** |
| `@UI.headerInfo` at top level | **Runtime-verified** |
| `@UI.lineItem` — root and item | **Runtime-verified** |
| `@UI.selectionField` | **Runtime-verified** |
| `@UI.identification` | **Runtime-verified** |
| `@UI.facet` inside `annotate entity … with { }` | **Runtime-verified** |
| `#IDENTIFICATION_REFERENCE` | **Runtime-verified** |
| `#LINEITEM_REFERENCE` with `targetElement: '_Items'` | **Runtime-verified** |
| `@UI.facet` at top level, beside `@UI.headerInfo` | **Compiler-verified INVALID — do not use** |

## The placement lesson

**`@UI.facet` at the top of a metadata extension is invalid on this target.** The first attempt placed it beside `@UI.headerInfo`, above `annotate entity`. ADT rejected it with 11 errors of the form:

```text
Annotation 'UI.facet.id' used at wrong position (wrong scope)
Annotation 'UI.facet.purpose' used at wrong position (wrong scope)
Annotation 'UI.facet.type' used at wrong position (wrong scope)
Annotation 'UI.facet.label' used at wrong position (wrong scope)
Annotation 'UI.facet.position' used at wrong position (wrong scope)
Annotation 'UI.facet.targetElement' used at wrong position (wrong scope)
```

The valid placement is **inside the `annotate entity … with { }` body, before the annotated elements**. Moving the block there and changing nothing else produced a clean syntax check, a successful activation and a rendered Object Page.

The instructive part is the asymmetry. `@UI.headerInfo` and `@UI.facet` both describe the entity rather than a single element, yet they do **not** share a placement rule here: `headerInfo` works at top level, `facet` is refused there. Assuming symmetry was the natural inference and it was wrong, and only the compiler could have said so. This is target evidence, not a general CDS rule.

## Activated root extension

Held in the repository at [zjp_c_purchaseorder.ddlx](../cds/zjp_c_purchaseorder.ddlx), matching the ADT active source exactly.

```
@Metadata.layer: #CUSTOMER

@UI.headerInfo: {
    typeName: 'Purchase Order',
    typeNamePlural: 'Purchase Orders',
    title: {
        type: #STANDARD,
        value: 'PurchaseOrderNumber'
    },
    description: {
        value: 'Supplier'
    }
}

annotate entity ZJP_C_PurchaseOrder
    with
{
    @UI.facet: [
        {
            id: 'GeneralInfo',
            purpose: #STANDARD,
            type: #IDENTIFICATION_REFERENCE,
            label: 'General Information',
            position: 10
        },
        {
            id: 'Items',
            purpose: #STANDARD,
            type: #LINEITEM_REFERENCE,
            label: 'Items',
            targetElement: '_Items',
            position: 20
        }
    ]

    @UI.lineItem: [{ position: 10, label: 'Purchase Order' }]
    @UI.selectionField: [{ position: 10 }]
    @UI.identification: [{ position: 10, label: 'Purchase Order' }]
    PurchaseOrderNumber;

    @UI.lineItem: [{ position: 20, label: 'Supplier' }]
    @UI.selectionField: [{ position: 20 }]
    @UI.identification: [{ position: 20, label: 'Supplier' }]
    Supplier;

    @UI.identification: [{ position: 30, label: 'Company Code' }]
    CompanyCode;

    @UI.identification: [{ position: 40, label: 'Purchasing Organization' }]
    PurchasingOrganization;

    @UI.identification: [{ position: 50, label: 'Purchasing Group' }]
    PurchasingGroup;

    @UI.identification: [{ position: 60, label: 'Currency' }]
    Currency;

    @UI.lineItem: [{ position: 40, label: 'Total Amount' }]
    @UI.identification: [{ position: 70, label: 'Total Amount' }]
    TotalAmount;

    @UI.lineItem: [{ position: 30, label: 'Status' }]
    @UI.selectionField: [{ position: 30 }]
    @UI.identification: [{ position: 80, label: 'Status' }]
    Status;

    @UI.identification: [{ position: 90, label: 'Rejection Origin' }]
    RejectionOrigin;

    @UI.identification: [{ position: 100, label: 'Rejection Reason' }]
    RejectionReason;
}
```

## Activated item extension

Held in the repository at [zjp_c_purchaseorderitem.ddlx](../cds/zjp_c_purchaseorderitem.ddlx), matching the ADT active source exactly.

```
@Metadata.layer: #CUSTOMER

annotate entity ZJP_C_PurchaseOrderItem
    with
{
    @UI.lineItem: [{ position: 10, label: 'Item' }]
    ItemNumber;

    @UI.lineItem: [{ position: 20, label: 'Material' }]
    Material;

    @UI.lineItem: [{ position: 30, label: 'Description' }]
    MaterialDescription;

    @UI.lineItem: [{ position: 40, label: 'Quantity' }]
    Quantity;

    @UI.lineItem: [{ position: 50, label: 'Net Price' }]
    NetPrice;

    @UI.lineItem: [{ position: 60, label: 'Item Total' }]
    TotalAmount;
}
```

## Runtime evidence

The learner activated both extensions and exercised Fiori Elements Preview. No independent SAP execution is claimed here.

### List Report

| Element | Rendered |
| --- | --- |
| `PurchaseOrderNumber` | Purchase Order |
| `Supplier` | Supplier |
| `Status` | Status |
| `TotalAmount` | Total Amount, with EUR |

Title *Purchase Orders (n)*. Filter Bar: **Editing Status, PurchaseOrderNumber, Supplier, Status** — *Editing Status* is framework-provided by draft handling and was never annotated. **Go** loaded real data, `PO00000002` through `PO00000010`, with blank numbers on pre-2.7E and draft-cancelled rows, exactly as the Phase 2.7E allocation rule predicts.

Before `@UI.headerInfo` existed, Fiori titled the Object Page with `PurchaseOrderUUID`. That is the Phase 2.7E identity split made visible: the UUID is the technical key an OData client addresses, `PurchaseOrderNumber` is what a person recognises, and the annotation is what tells the presentation layer which of the two a human should see.

### Object Page

Header: **Purchase Order `PO00000004`**, description **`SUP010`**.

General Information facet rendered all ten fields: Purchase Order, Supplier, Company Code, Purchasing Organization, Purchasing Group, Currency, Total Amount, Status, Rejection Origin, Rejection Reason.

Items facet rendered, with the item table showing Item, Material, Description, Quantity, Net Price, Item Total. Runtime values included Item `10`, Material `MAT001`, Quantity `2 EA`, Net Price `750.00 EUR`, Item Total `1,500.00 EUR`.

### Semantics carried the units, as designed

`Quantity` rendered as `2 EA` and both amounts with `EUR`, **with no unit or currency annotation anywhere in either metadata extension**. The `@Semantics.quantity.unitOfMeasure`, `@Semantics.unitOfMeasure`, `@Semantics.amount.currencyCode` and `@Semantics.currencyCode` markers placed on the base views in Phase 1 propagate through the projections into OData, and Fiori reads them.

**This settles the open question: do not add `UnitOfMeasure` or `Currency` as separate item columns.** They would duplicate information the framework already renders. The restraint was provisional when the columns were first chosen; it is now evidenced.

### Mechanism

Activating a metadata extension refreshed `$metadata` automatically — **the service binding did not need republishing**. That matters on this target, where publishing required `/IWFND/V4_ADMIN` because client 100 is a Customizing client; a per-change republish would have made annotation work expensive enough to discourage iteration.

## Design decisions recorded

**Restraint over completeness.** The root projection exposes 24 elements; ten are annotated. Excluded on purpose: `PurchaseOrderUUID`, `IsActiveEntity`, `HasActiveEntity`, `HasDraftEntity` and the draft administrative properties, which are framework-managed and must not be annotated; and `SupplierName`, `SupplierResponse`, `EstimatedDeliveryDate`, `IntegrationStatus`, `OrderRevision` and the four `LastError*` fields, which no Phase 2 code writes and would render as permanently empty boxes implying capabilities the system does not have. They become meaningful in Phase 5 and get annotated then.

**Rejection fields sit at the end of `@UI.identification` rather than in a field group.** A `#FIELDGROUP_REFERENCE` facet with `@UI.fieldGroup` and a qualifier would give `RejectionOrigin` and `RejectionReason` their own titled section, at the cost of three further unverified constructs in a round that already carried several. Positions 90 and 100 read acceptably. Now that `@UI.identification` and `@UI.facet` are proven, promoting them to a field group is a small optional refinement rather than a risk.

Both rejection fields are blank on any order that was never rejected. That is correct and needs no conditional display.

## Known limits, unchanged by this subphase

- **`__OperationControl` advertises bound actions even where the lifecycle would reject them.** A UX gap, not a rule defect: the Phase 2 handlers still return HTTP 400 with their exact message texts. Dynamic feature control is the known remedy and **remains out of scope**; Phase 2.7B established that feature control is advisory and bypassed by `IN LOCAL MODE`, so it can improve what a UI offers but can never enforce.
- **`OptimisticConcurrency` appears in `$metadata`, but stale-ETag and multi-user behavior remain unproven.** Open as OI-13.
- **No authorization is enforced.** The permissive study stub is unchanged, so the Object Page's action buttons are available to any user.
- **`sendToSupplier` and the integration surface remain Phase 5.**

## Optional refinements, none required

Nothing below is needed for Phase 3.2 to be complete, and none should be started without being scoped.

- A `#FIELDGROUP_REFERENCE` facet for the rejection fields.
- `@UI.textArrangement` or a value help on `Supplier`, once supplier master data exists.
- Criticality decoration on `Status`, so `REJECTED` and `CANCELLED` read differently from `APPROVED`.
- Annotating the integration and error fields in Phase 5, when they start carrying values.
