# Phase 2 — managed RAP runtime test with EML

The learner reports Phase 2.4C and Phase 2.5A runtime-verified complete. Header totals reached 1900 → 2650 → 2800 → 2400 → 0 with successful positive commits. Blank Supplier create/update were rejected during save with nonzero sy-subrc and `Supplier is required.`, persistence remained unchanged, and the valid regression flow passed. That historical persisted-parent lookup did not support uncommitted-item deletion. Phase 2.6 replaces it with the SAP runtime-verified root-known technical action for active and draft instances. No independent SAP execution by the assistant is claimed.

## ADT object

Use normal ABAP Class `ZJP_CL_PO_EML_TEST`, implementing `IF_OO_ADT_CLASSRUN`. Its complete current source is [zjp_cl_po_eml_test.clas.abap](../classes/zjp_cl_po_eml_test.clas.abap).

The class is an external BO consumer: it deliberately does not use `IN LOCAL MODE`. It creates and changes data only through EML, respects field control/authorization and calls `COMMIT ENTITIES` at explicit transaction boundaries. UUID-filtered SQL `SELECT` statements are read-only persistence checks; there is no direct database write.

## Current sequence

1. Deep-create one header and two composed items using `%cid`, `%cid_ref` and `%target`.
2. Read the uncommitted BO buffer and verify Status DRAFT, item totals 1500/400 and header total 1900.
3. Prove the database still has no matching rows, then commit and verify persistence.
4. Change item 00010 Quantity from 2 to 3 and verify item/header totals 2250/2650 before and after commit.
5. Change its NetPrice from 750 to 800 and verify totals 2400/2800 before and after commit.
6. Verify removeItem rejects a foreign item without changing either root/composition. Then call root removeItem for item 00020 and verify the buffered and persisted header becomes 2400.
7. Call root removeItem for the last item and verify the still-existing header becomes zero before and after commit.
8. Delete the empty root through EML and verify final database cleanup.

## What RAP manages

RAP assigns UUIDs, links composition children, owns the transaction buffer, executes determinations and persists managed create/update/delete requests. The test supplies business inputs, correlates creates through `MAPPED`, reuses `%tky` for later mutations, checks `FAILED` and `REPORTED`, and chooses when to commit.

`READ ENTITIES` can see current unsaved values. `COMMIT ENTITIES` is required only after a modifying stage must become durable. A failed later stage cannot roll back earlier successful commits, so the class prints the generated UUID for diagnosis and stops on failure.

## Activation and expected result

The Phase 2.4C committed-parent lookup is historical and has been removed. Current sources use root removeItem and internal child DELETE; see the [Phase 2.6 guide](phase-2-6-technical-draft.md) for parameter creation, joint BDEF/pool activation and breakpoints. The active regression runtime-verifies foreign-item rejection and aggregate-safe removal; it no longer depends on physical deleted-item identity.

Activate in the linked Phase 2.6 order, then run with F9. Positive modify/save FAILED structures are initial; validation saves and the intentional foreign-item action fail as expected. The important final output is:

```text
PASS: header totals 1900/2650/2800/2400/0; cleanup complete.
```

If the run stops, send the exact compiler diagnostic or STOP line, the relevant FAILED/REPORTED content and the printed UUID. The active test covers the existing validations and new technical action; concurrency and negative role authorization are not covered. ZJP_CL_PO_DRAFT_PROBE separately checks saved and buffer-only draft removal. Those revised tests are SAP runtime-verified.

## Phase 2.5A extension

See [Supplier validation](phase-2-5a-supplier-validation.md). The test first attempts a blank-Supplier create, then tries clearing Supplier on the committed SUP001 order. Both MODIFY requests should succeed and both saves must fail with a matching root FAILED key and field-specific `Supplier is required.` message. These intentional negative commits are expected to have nonzero sy-subrc. The helper rolls back before checking persistence and proceeding. Positive saves still require sy-subrc 0.

The runtime-verified Phase 2.5A final line is `PASS: Supplier validation rejects blank create/update; valid flow and cleanup pass.` The header-total PASS line is printed immediately before it.

## Phase 2.5B extension — SAP runtime-verified

The [Quantity validation test](phase-2-5b-quantity-validation.md) adds zero-Quantity deep create and negative-Quantity update. It requires nonzero save results, the failed item key and exact field-marked message `Quantity must be greater than 0.` After rollback, no invalid create may persist and complete header/item snapshots must match the pre-update database state. Existing positive regression checks remain in place.

Learner-supplied successful final line: `PASS: Quantity validation rejects zero create/negative update; valid flow and cleanup pass.` The 2026-09-14 successful run also passes both negative-save persistence checks and the full regression. The attachment includes an earlier failed run; its residual test data and unknown cause are recorded in the Phase 2.5B guide.

## Phase 2.5C extension — SAP runtime-verified

The [NetPrice validation guide](phase-2-5c-net-price-validation.md) adds negative-price create/update rejection with unchanged persistence and zero-price create/update acceptance. A separate committed fixture exercises prices 0 → 750 → 0, checking buffer and database totals, then cleans up through EML. The existing regression remains intact. The learner's supplied SAP output verifies both negative NetPrice saves (sy-subrc 4), zero-price checkpoints, the existing regression and cleanup.

Runtime-verified final line: `PASS: NetPrice rejects negative create/update; zero create/update, regression and cleanup pass.`

## Phase 2.6 extension — SAP runtime-verified

The existing validation helpers and positive input-change flow are retained. Standard child deletion calls become root removeItem calls carrying root %tky and item UUID. A foreign-root item is rejected before mutation; rollback and read-only table checks verify persistence is unchanged. The active run reaches:

```text
PASS: removeItem active totals 2400/0; ownership, Phase 2.5 regression and cleanup pass.
```

The separate [draft test](../classes/zjp_cl_po_draft_probe.clas.abap) verifies saved-draft totals 1900/1500/0 and buffer-only totals 1500/0. Full instructions and expected lines are in the [Phase 2.6 guide](phase-2-6-technical-draft.md).
