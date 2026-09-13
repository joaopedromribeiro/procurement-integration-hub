# Phase 2.4B — item TotalAmount determination

Phase 2.4A initializeStatus and this item calculation are runtime-verified complete as reported by the learner.

## Implemented behavior

The child BDEF section declares:

```abap
determination calculateTotalAmount on modify {
  create;
  field Quantity, NetPrice;
}
```

`TotalAmount` remains in the existing readonly field list. Consumers supply Quantity and NetPrice; RAP triggers the determination on item creation or when either input changes.

The new local class `lhc_PurchaseOrderItem` belongs in Local Types of the existing behavior pool `ZBP_I_PURCHASEORDER`. Its generated method signature is:

```abap
METHODS calculateTotalAmount FOR DETERMINE ON MODIFY
  IMPORTING keys FOR PurchaseOrderItem~calculateTotalAmount.
```

The implementation reads Quantity and NetPrice from the RAP transactional buffer with `READ ENTITIES ... IN LOCAL MODE`, then updates only TotalAmount using `MODIFY ENTITIES ... IN LOCAL MODE`. It does not write directly to ZJP_PO_I and does not commit. The external EML consumer owns the commit boundary.

The assignment is `TotalAmount = Quantity * NetPrice`. Conversion into the modeled TotalAmount field applies its target numeric type. Currency conversion, taxes and header aggregation are outside this step. ADT-generated signatures and compiler-derived response types remain authoritative for the target release.

## ADT changes

1. Update Behavior Definition `ZJP_I_PURCHASEORDER` with the [BDEF source](../behavior/zjp_i_purchaseorder.bdef).
2. In the Local Types area of behavior pool `ZBP_I_PURCHASEORDER`, apply the updated [handler source](../classes/zbp_i_purchaseorder.clas.locals_imp.abap). If ADT generates the method first, preserve its target-compatible signature and avoid duplicating the item handler.
3. Update normal console class `ZJP_CL_PO_EML_TEST` with the [test source](../classes/zjp_cl_po_eml_test.clas.abap).
4. Syntax-check and activate the BDEF, behavior pool and test class. Run the console class with F9.

## Runtime assertions

| Stage | Quantity | NetPrice | Expected item TotalAmount |
| --- | ---: | ---: | ---: |
| Create, before first commit | 2 | 750 | 1500 |
| After create commit | 2 | 750 | 1500 persisted |
| Quantity update, before commit | 3 | 750 | 2250 |
| After quantity commit | 3 | 750 | 2250 persisted |
| NetPrice update, before commit | 3 | 800 | 2400 |
| After price commit | 3 | 800 | 2400 persisted |

The test retains Status DRAFT checks, Supplier update and composition cleanup. It now has four successful commit boundaries: create, combined Supplier/Quantity update, NetPrice update and root deletion.

Verified final output:

```text
PASS: item totals 1500/2250/2400; status, CRUD and cleanup.
```

The learner reported successful buffered and persisted results for 2 × 750 = 1500, 3 × 750 = 2250 and 3 × 800 = 2400. The SAP console ended with the exact PASS line above. Phase 2.4B is complete on this [learner-supplied runtime evidence](phase-2-4b-runtime-evidence.md); the assistant did not independently connect to SAP.

The test has now advanced to [Phase 2.4C header aggregation](phase-2-4c-header-total-determination.md). IntegrationStatus, validations, technical draft, actions, OData/Fiori, CAP and Integration Suite remain unimplemented.
