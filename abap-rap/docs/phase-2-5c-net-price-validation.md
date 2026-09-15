# Phase 2.5C — NetPrice must not be negative

SAP runtime-verified complete on learner-supplied console evidence, 2026-09-14. Phase 2.5A Supplier and Phase 2.5B Quantity validations remain runtime-verified. This step adds only validateNetPrice and its EML tests.

## Rule and implementation

PurchaseOrderItem.NetPrice must be greater than or equal to 0. Zero is valid; an initial numeric NetPrice is also zero. This is not a mandatory-positive-price rule.

The item section of Behavior Definition ZJP_I_PURCHASEORDER adds:

```abap
validation validateNetPrice on save { create; field NetPrice; }
```

The method in lhc_PurchaseOrderItem follows the verified validateQuantity pattern: read NetPrice from the transactional buffer using EML in local mode, append invalid item keys to FAILED, and report exactly `Net Price cannot be negative.` with error severity and the NetPrice field marker. It performs no modification or commit. Managed RAP retains persistence responsibility; the validation supplies the save rejection.

Existing determinations may calculate temporary negative totals during modify processing. The save validation must prevent those values from persisting. The consumer rolls back the rejected transaction; rollback cannot undo a save that unexpectedly succeeded.

## ADT objects and execution

1. Update Behavior Definition **ZJP_I_PURCHASEORDER** from [the BDEF](../behavior/zjp_i_purchaseorder.bdef).
2. Update behavior pool **ZBP_I_PURCHASEORDER**, Local Types, from [the local handler source](../classes/zbp_i_purchaseorder.clas.locals_imp.abap). Add validateNetPrice; preserve the existing handlers. ADT-generated method signatures and components are authoritative.
3. Update normal ABAP Class **ZJP_CL_PO_EML_TEST** from [the console test](../classes/zjp_cl_po_eml_test.clas.abap).
4. Syntax-check and activate BDEF and behavior pool together as needed, then activate the console class and run with **F9**. If compilation fails, supply the exact diagnostic before changing generated signatures.

## Test sequence and expected results

Compiler correction: ADT rejected `prices = VALUE #( ( 750 ) ( 0 ) ).` with `"750" and the row type of "PRICES" are incompatible.` Keep the existing table declaration and use explicitly typed values:

```abap
prices = VALUE #( ( CONV zjp_po_i-net_price( 750 ) )
                  ( CONV zjp_po_i-net_price( 0 ) ) ).
```

Only the console fixture initialization changed. The subsequent successful SAP run verifies the explicit-conversion correction.

| Scenario | Expected save | Expected persistence |
| --- | --- | --- |
| New root with valid Supplier, Quantity 2, NetPrice -1 | Nonzero commit sy-subrc, failed item key and exact NetPrice message | No root or associated item after rollback |
| Separate root/item with Quantity 2, NetPrice 0 | Commit sy-subrc 0 | NetPrice 0; item and header totals 0 |
| Change that committed item's price 0 → 750 → 0, committing each update | Both commits return 0 | Item/header totals 1500, then 0; zero update is a real change |
| Delete the separate committed fixture through EML | Commit sy-subrc 0 | No remaining root/items for its UUID |
| Change main regression item price 750 → -1 | Nonzero commit sy-subrc with the exact message | Complete header/item snapshots unchanged, including sibling/audit fields; price 750, item total 1500, header total 1900 |
| Existing Supplier/Quantity negative tests and positive regression | Original expected save outcomes | Header totals 1900/2650/2800/2400/0 and cleanup still pass |

The new negative helper checks both FAILED and REPORTED, including the item identity and NetPrice field marker. Read-only SELECT snapshots are limited to the test UUID and ordered by primary key to compare complete persistence before/after rejected updates. The existing Quantity helper remains unchanged.

The zero-price helper reads item/header values through EML before every commit and checks persistence afterward. It first commits a zero-price create, establishes a positive price of 750, then commits an update back to zero. A separate fixture keeps the original regression amounts and flow intact. All mutations and cleanup use EML; there are no direct SQL writes.

Runtime-verified final line:

```text
PASS: NetPrice rejects negative create/update; zero create/update, regression and cleanup pass.
```

## SAP runtime evidence — 2026-09-14

Provenance: learner attachment `1d71d5da-a4ac-4914-babe-3adb34b1923e/pasted-text.txt`, lines 1–580. This is learner-supplied SAP execution evidence, not independent execution by the assistant.

- Negative NetPrice create: commit sy-subrc 4, failed item and exact message `Net Price cannot be negative.`; no persisted root/item after rollback (lines 57–86).
- Zero-price create: commit 0, Quantity 2 and item/header totals 0. Committed updates 0 → 750 → 0 return 0 and produce totals 1500 → 0. Buffer, database and fixture cleanup checks pass (lines 87–235).
- Negative NetPrice update: commit 4 with the exact message; full persistence comparison passes, retaining price 750, item total 1500 and header total 1900 (lines 350–384).
- Supplier and Quantity negative cases still pass. Positive regression reaches header totals 1900/2650/2800/2400/0; cleanup and final NetPrice PASS line pass (through line 580).
- No STOP result appears in the supplied run. Phase 2.5C is complete. RAP sources are unchanged in this evidence update; no later phase is started.

Cleanup evidence covers this run's fixtures only, not the earlier failed Phase 2.5B order.

## Scope retained

No Phase 2.6, draft, actions, OData, Fiori, CAP or integration changes. Existing readonly totals and calculation logic are preserved. The current header deletion lookup still does not support uncommitted-item deletion; the new positive fixture is committed before cleanup. Earlier failed-run data recorded in the Phase 2.5B guide is outside this run's UUID scope.
