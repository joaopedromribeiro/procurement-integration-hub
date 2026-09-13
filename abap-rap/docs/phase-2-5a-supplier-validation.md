# Phase 2.5A — Supplier required on save

Phase 2.4C is runtime-verified complete for its documented committed-item deletion scope. Uncommitted-item deletion remains unsupported. Phase 2.5A validateSupplier is now runtime-verified complete in the learner's SAP system. The existing determination methods remain preserved.

## Rule and implementation

Supplier must not be initial when saving a new order or changing Supplier. This applies even when business Status is DRAFT; technical RAP draft is not implemented. No supplier-master lookup, item-count check, quantity/price validation or other rule is added.

The root BDEF declares:

```abap
validation validateSupplier on save { create; field Supplier; }
```

`lhc_PurchaseOrder` implements `FOR VALIDATE ON SAVE`, reads Supplier through local-mode EML and appends an invalid root key to FAILED. REPORTED contains an error message, `Supplier is required.`, marked against `%element-Supplier`. The validation performs no writes and no commit. This follows the [SAP validation pattern](https://github.com/SAP-samples/abap-platform-rap-opensap/blob/main/week3/unit6.md). We use a simple transition message for this active-only checkpoint; translated messages can follow later.

## ADT objects

1. Update Behavior Definition **ZJP_I_PURCHASEORDER** from [the BDEF](../behavior/zjp_i_purchaseorder.bdef).
2. Update **ZBP_I_PURCHASEORDER**, Local Types, from [the local source](../classes/zbp_i_purchaseorder.clas.locals_imp.abap). Add validateSupplier to the root handler; preserve working item determination methods.
3. Update normal ABAP Class **ZJP_CL_PO_EML_TEST** from [the test source](../classes/zjp_cl_po_eml_test.clas.abap).
4. Syntax-check and activate the changed BDEF/pool together if needed, then activate the test and run with F9. ADT's generated signatures/components remain authoritative.

## Test expectations

| Scenario | MODIFY | COMMIT | Database after rollback/check |
| --- | --- | --- | --- |
| Create root with blank Supplier | Succeeds in buffer | Fails, nonzero sy-subrc; root FAILED plus Supplier message | Invalid root absent |
| Clear Supplier on committed SUP001 root | Succeeds in buffer | Fails with the same validation | Supplier still SUP001 |
| Existing valid create/SUP002 update and totals flow | Succeeds | sy-subrc 0 | Expected totals and final cleanup |

The negative helper checks the failure key and exact message with its Supplier field marker, then explicitly rolls back. Nonzero COMMIT results are expected only in the two negative cases. ROLLBACK does not undo earlier successful commits. If a test unexpectedly saves invalid data, the printed UUID identifies it for diagnosis; stop and correct the validation before rerunning.

Runtime-verified evidence:

- blank Supplier create was rejected at save;
- blank Supplier update was rejected at save;
- both negative commits returned nonzero sy-subrc;
- both produced `Supplier is required.`;
- persistence remained unchanged;
- the valid regression flow still passed.

Final output:

```text
PASS: header totals 1900/2650/2800/2400/0; cleanup complete.
PASS: Supplier validation rejects blank create/update; valid flow and cleanup pass.
```

This is learner-supplied SAP runtime evidence; the assistant did not independently connect to SAP. Phase 2.5A is complete. Phase 2.5B has not started.
