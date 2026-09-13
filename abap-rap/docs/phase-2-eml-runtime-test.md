# Phase 2 — managed RAP runtime test with EML

The learner reports Phase 2.4C runtime-verified complete: header totals 1900 → 2650 → 2800 → 2400 → 0, successful relevant COMMIT ENTITIES calls (sy-subrc 0), and `PASS: header totals 1900/2650/2800/2400/0; cleanup complete.` The persisted-parent lookup still does not support uncommitted-item deletion. No independent SAP execution by the assistant is claimed. The current test adds Phase 2.5A Supplier validation and awaits a new SAP run.

## ADT object

Use normal ABAP Class `ZJP_CL_PO_EML_TEST`, implementing `IF_OO_ADT_CLASSRUN`. Its complete current source is [zjp_cl_po_eml_test.clas.abap](../classes/zjp_cl_po_eml_test.clas.abap).

The class is an external BO consumer: it deliberately does not use `IN LOCAL MODE`. It creates and changes data only through EML, respects field control/authorization and calls `COMMIT ENTITIES` at explicit transaction boundaries. UUID-filtered SQL `SELECT` statements are read-only persistence checks; there is no direct database write.

## Current sequence

1. Deep-create one header and two composed items using `%cid`, `%cid_ref` and `%target`.
2. Read the uncommitted BO buffer and verify Status DRAFT, item totals 1500/400 and header total 1900.
3. Prove the database still has no matching rows, then commit and verify persistence.
4. Change item 00010 Quantity from 2 to 3 and verify item/header totals 2250/2650 before and after commit.
5. Change its NetPrice from 750 to 800 and verify totals 2400/2800 before and after commit.
6. Delete item 00020 and verify the buffered and persisted header becomes 2400.
7. Delete the last item and verify the still-existing header becomes zero before and after commit.
8. Delete the empty root through EML and verify final database cleanup.

## What RAP manages

RAP assigns UUIDs, links composition children, owns the transaction buffer, executes determinations and persists managed create/update/delete requests. The test supplies business inputs, correlates creates through `MAPPED`, reuses `%tky` for later mutations, checks `FAILED` and `REPORTED`, and chooses when to commit.

`READ ENTITIES` can see current unsaved values. `COMMIT ENTITIES` is required only after a modifying stage must become durable. A failed later stage cannot roll back earlier successful commits, so the class prints the generated UUID for diagnosis and stops on failure.

## Activation and expected result

The first Phase 2.4C run passed persisted totals 1900/2650/2800 but failed deletion. Debugger evidence later proved the precheck and determination had different ME objects, invalidating the instance-state bridge. The stateless correction derives parent identity from the still-persisted committed item and aggregates through EML. The test now prints and checks that physical identity before each delete commit, alongside buffered surviving-item/header values. Follow the [deletion correction guide](phase-2-4c-header-total-determination.md) for the new determination-only breakpoints. All test items are committed before deletion; uncommitted-item deletion is outside this implementation's scope.

Activate the updated BDEF, behavior pool Local Types and this console class, then run the class with F9. Every modify/save `FAILED` structure should be initial. The important final output is:

```text
PASS: header totals 1900/2650/2800/2400/0; cleanup complete.
```

If the run stops, send the exact compiler diagnostic or STOP line, the relevant FAILED/REPORTED content and the printed UUID. The test covers the intended sequential requests; it does not yet cover same-request create-then-delete, concurrency, negative authorization, validations, draft or actions.

## Phase 2.5A extension

See [Supplier validation](phase-2-5a-supplier-validation.md). The test first attempts a blank-Supplier create, then tries clearing Supplier on the committed SUP001 order. Both MODIFY requests should succeed and both saves must fail with a matching root FAILED key and field-specific `Supplier is required.` message. These intentional negative commits are expected to have nonzero sy-subrc. The helper rolls back before checking persistence and proceeding. Positive saves still require sy-subrc 0.

The final line is now `PASS: Supplier validation rejects blank create/update; valid flow and cleanup pass.` The historical header-total PASS line is still printed immediately before it.
