# Phase 2.4C — Purchase Order header TotalAmount

The learner reports Phase 2.4C runtime-verified complete: header totals 1900 → 2650 → 2800 → 2400 → 0, successful relevant COMMIT ENTITIES calls (sy-subrc 0), and `PASS: header totals 1900/2650/2800/2400/0; cleanup complete.` The persisted-parent lookup still does not support uncommitted-item deletion. No independent SAP execution by the assistant is claimed.

## Design

The child behavior now has two on-modify determinations:

```abap
determination calculateTotalAmount on modify { create; field Quantity, NetPrice; }
determination recalculateHeaderAfterDelete on modify { delete; }
```

`calculateTotalAmount` reads changed items, their affected parents and all current sibling items from the RAP transactional buffer. It derives each line value from `Quantity × NetPrice`, converts it to the item TotalAmount type, sums those derived line values per parent and updates changed item totals and root totals in one local-mode EML statement.

This intentionally does not sum possibly stale buffered `TotalAmount` fields. RAP does not guarantee the order of separate determinations, so the header calculation derives the same rounded item values directly from their source fields. After the method finishes, the observable rule is still header TotalAmount = sum of item TotalAmount.

The debugger confirmed that `precheck_delete` and `recalculateHeaderAfterDelete` run on different handler objects (different ME). The precheck had one delete_context row; the determination had none and READ TABLE returned sy-subrc 4. The previous assumption that handler-instance attributes bridge callbacks is withdrawn. Neither instance attributes nor CLASS-DATA are used in the correction.

The child returns to plain `delete;`; the precheck and delete_context are removed. At entry to the delete determination, a UUID-filtered, read-only SELECT from our own ZJP_PO_I retrieves only the immutable child-to-parent identity. The current non-draft test deletes previously committed items: their physical rows still exist until RAP's save sequence. No amount, quantity or price is read from persistence for aggregation. Empty input keys are checked before FOR ALL ENTRIES.

The method deduplicates parent keys, reads the live roots and their surviving children through local-mode EML, derives rounded line values from buffered inputs, and writes the root total through local-mode EML. A surviving root with no items gets zero. The working create/Quantity/NetPrice method is unchanged. The method holds only local variables, so different callback instances are irrelevant.

This is a scoped solution for previously committed active items with immutable parent assignment. It does not cover newly created/uncommitted item deletion or technical draft. A missing persisted identity produces an error message; that message alone is not a save-blocking validation. Consumers must roll back an unsupported request. Do not treat this checkpoint as a general production deletion API. Before supporting uncommitted deletes, redesign the child key to carry its parent (with coordinated model/persistence changes), or verify a target-supported RAP before-image/change-read facility. No unverified newer syntax or shared-state cache is introduced here.

SAP documents that managed persistence is performed in the [save sequence](https://help.sap.com/docs/abap-cloud/abap-rap/9a411f08c3db48e5af542e2d560a564c.html). Using the still-persisted immutable relationship for this committed-item case is our design inference from that transaction boundary. The learner's subsequent run confirmed the lookup and results for the committed-item test.

Both methods use `READ ENTITIES` and `MODIFY ENTITIES ... IN LOCAL MODE`. They do not issue SQL updates and do not commit. `TotalAmount` remains readonly to BO consumers, while the behavior implementation may set it internally.

ADT-generated method signatures, accepted delete-trigger syntax and target runtime behavior are authoritative. SAP notes that on-modify determinations execute immediately after buffer changes, that their order is not fixed, and that an item created or updated and then deleted within one request can have special read behavior. This test deletes previously committed items in separate requests and verifies each result.

## ADT changes

1. Update Behavior Definition `ZJP_I_PURCHASEORDER` from [the BDEF source](../behavior/zjp_i_purchaseorder.bdef).
2. Update Local Types of behavior pool `ZBP_I_PURCHASEORDER` from [the handler source](../classes/zbp_i_purchaseorder.clas.locals_imp.abap).
3. Update normal console class `ZJP_CL_PO_EML_TEST` from [the EML test source](../classes/zjp_cl_po_eml_test.clas.abap).
4. Syntax-check and activate those three objects in that order, then run `ZJP_CL_PO_EML_TEST` with F9.

Set breakpoints inside `recalculateHeaderAfterDelete` immediately after SELECT, after the root-to-items EML read, and before MODIFY ENTITIES. Verify persisted_parents has the deleted item UUID and its parent; parent_keys/affected_orders have one root; remaining_items has only 00010 after deleting 00020 and is empty after the last deletion; orders_to_update-TotalAmount is 2400 then 0. There is no precheck breakpoint anymore. The console additionally proves the deleted identity still exists physically before each delete commit while the item is absent from the RAP buffer. After commit, the existing persistence checks verify actual removal and the header amount.

## Runtime proof

| Stage | Item 00010 | Item 00020 | Expected header |
| --- | ---: | ---: | ---: |
| Deep create, before/after commit | 2 × 750 = 1500 | 4 × 100 = 400 | 1900 |
| Quantity becomes 3 | 2250 | 400 | 2650 |
| NetPrice becomes 800 | 2400 | 400 | 2800 |
| Delete item 00020 | 2400 | deleted | 2400 |
| Delete last item | deleted | deleted | 0 |

The console checks every value in the RAP buffer before its commit and verifies persisted header/item sums afterward. It then deletes the empty root through EML and verifies final cleanup.

Runtime-verified final line:

```text
PASS: header totals 1900/2650/2800/2400/0; cleanup complete.
```

If activation or runtime fails, capture the exact ADT diagnostic or STOP line plus the printed UUID. Do not replace EML with direct persistence updates. Validations, IntegrationStatus, technical draft, actions, OData/Fiori, CAP and Integration Suite remain outside this checkpoint.

The next checkpoint is [Phase 2.5A Supplier validation](phase-2-5a-supplier-validation.md). The working determination methods are unchanged by that addition.
