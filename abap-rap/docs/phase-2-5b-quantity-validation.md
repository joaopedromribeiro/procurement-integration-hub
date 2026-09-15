# Phase 2.5B — Quantity greater than zero on save

Phase 2.5A validateSupplier and Phase 2.5B validateQuantity are SAP runtime-verified complete. The learner supplied console evidence on 2026-09-14. The existing Supplier validation and all runtime-verified determination behavior are preserved.

## Rule and implementation

PurchaseOrderItem Quantity must be greater than 0. The rule applies when an item is created and whenever Quantity changes. It does not add price validation, item-count validation, technical draft behavior or any Phase 2.5C rule.

The item BDEF declares:

```abap
validation validateQuantity on save { create; field Quantity; }
```

`lhc_PurchaseOrderItem` implements `FOR VALIDATE ON SAVE`, reads Quantity through local-mode EML and appends every invalid item key to FAILED. REPORTED contains the error `Quantity must be greater than 0.` marked against `%element-Quantity`. The FAILED entry vetoes the save; the validation performs no writes and no commit.

## ADT objects

1. Update Behavior Definition **ZJP_I_PURCHASEORDER** from [the BDEF](../behavior/zjp_i_purchaseorder.bdef).
2. Update **ZBP_I_PURCHASEORDER**, Local Types, from [the local source](../classes/zbp_i_purchaseorder.clas.locals_imp.abap). Preserve all existing root validation and root/item determination methods.
3. Update normal ABAP Class **ZJP_CL_PO_EML_TEST** from [the test source](../classes/zjp_cl_po_eml_test.clas.abap).
4. Syntax-check and activate the BDEF and behavior pool together if ADT requires it, then activate the test class and run it with F9. The target compiler and generated handler signatures/components are authoritative.

## Test expectations

| Scenario | MODIFY | COMMIT | Database after rollback/check |
| --- | --- | --- | --- |
| Create a valid-Supplier root with an item whose Quantity is 0 | Succeeds in the RAP buffer | Fails with nonzero sy-subrc, item FAILED and the Quantity message | Neither invalid root nor item persists |
| Change the committed item Quantity from 2 to -1 | Succeeds in the RAP buffer | Fails with the same validation | Quantity remains 2; item total remains 1500; header total remains 1900 |
| Existing valid create/update/totals/deletion flow | Succeeds | Successful commits keep sy-subrc 0 | Existing Phase 2.4/2.5A checkpoints and cleanup still pass |

The negative helper checks the failed item key, exact message and Quantity field marker, then rolls back and reads persistence directly. Zero on create covers the boundary; -1 on update covers a negative value. The normal flow still changes Quantity to 3 successfully and continues through price changes and committed-item deletion.

Read-only, UUID-filtered table snapshots compare every persisted header and item field before and after the rejected update, including sibling items and audit fields. Both snapshots use primary-key ordering. The rejected create checks that no header or associated item exists. These SELECTs are test assertions only; all mutations use EML. Existing determinations may calculate temporary invalid totals in the buffer, but the save validation must prevent those totals from persisting. Rollback discards that rejected buffer state.

Expected final line:

```text
PASS: Quantity validation rejects zero create/negative update; valid flow and cleanup pass.
```

## SAP runtime evidence — 2026-09-14

The supplied attachment contains two runs. The first ends with STOP: its zero-Quantity create committed with sy-subrc 0, empty save failures and persisted header/item rows. The reason for the difference between runs was not supplied; no cause or code fix is inferred.

The subsequent full run verifies:

- Zero-Quantity create: save sy-subrc 4, failed item key, exact message `Quantity must be greater than 0.`, and no persisted header/item after rollback.
- Negative-Quantity update: save sy-subrc 4 with the same message; complete persistence comparison passes, preserving Quantity 2, item total 1500 and header total 1900.
- Supplier create/update validation still passes.
- Positive commits return 0; header totals are 1900/2650/2800/2400/0 and the successful run's cleanup passes.
- Final line: `PASS: Quantity validation rejects zero create/negative update; valid flow and cleanup pass.`

Evidence provenance: learner attachment `588b0889-c1e9-4b06-a25a-99cb55eb70e9/pasted-text.txt`, first run lines 1–55, successful run lines 58–422. No independent SAP execution by the assistant is claimed. RAP sources are unchanged in this evidence update.

Earlier failed-run order `37FC3FA8EB2D1FE1AC8C579A02445D72` and item `37FC3FA8EB2D1FE1AC8C579A02447D72` were persisted. Their later cleanup is not evidenced. Inspect by UUID and use EML for cleanup if still present; rollback after commit cannot remove them. The successful run uses order `37FC3FA8EB2D1FE1AC8CB039CA3F3E2E`, so its cleanup does not prove removal of the earlier order.

Phase 2.5B is complete. The learner subsequently authorized [Phase 2.5C](phase-2-5c-net-price-validation.md), which is now SAP runtime-verified complete. The persisted-parent lookup still does not support uncommitted-item deletion.
