# Phase 2.4A — initializeStatus implementation and ADT check

Phase 2.1–2.3 retain their [verified SAP evidence](phase-2-3-eml-runtime-evidence.md). The learner reports initializeStatus and its extended EML test passed in SAP. Phase 2.4A is complete; Phase 2.4B also passed and [Phase 2.4C header TotalAmount](phase-2-4c-header-total-determination.md) is now active.

## What a determination does

A RAP determination automatically derives or defaults BO data when a declared trigger occurs. The framework invokes the method; the consumer does not call a status setter explicitly. The BDEF defines the trigger and the local handler in the behavior pool contains its ABAP implementation.

An on-modify determination runs during processing of the relevant modification, allowing a subsequent EML read to see derived values before commit. An on-save determination runs during save processing. For a default that should already be visible immediately after creating an order, recommend on modify with create as its trigger. See [SAP determination definition](https://help.sap.com/docs/latest/fc4c71aa50014fd1b43721701471913d/1c9cbfcecef74d588e68a2552812a278.html).

A determination changes values: for example, it supplies DRAFT when Status is initial. A validation checks whether data is acceptable and can reject saving with messages; it should not silently repair values. Defaults and totals are derivation concerns. Required supplier, positive quantity and permitted state transitions are separate later checks.

Determinations must be idempotent: repeated execution for the same state should not keep changing the result. Do not depend on the order in which different determinations execute. See [SAP determinations](https://help.sap.com/docs/abap-cloud/abap-rap/determinations).

## Implemented: Status only

| Decision | Plan |
| --- | --- |
| BO entity | Root PurchaseOrder in ZJP_I_PURCHASEORDER BDEF |
| Determination name | initializeStatus |
| Timing and trigger | on modify, triggered by create |
| Local handler | Existing lhc_PurchaseOrder inside behavior pool ZBP_I_PURCHASEORDER |
| Desired value | Status = DRAFT only when currently initial |
| Consumer field control | Keep Status readonly in the BDEF |
| Method declaration | Use ADT's generated FOR DETERMINE ON MODIFY signature bound to PurchaseOrder~initializeStatus, importing instance keys |
| Persistence | Managed RAP buffer and save sequence; no direct SQL writes and no commit in the handler |

```text
Consumer creates root through EML
  -> RAP establishes the new instance and identity in its buffer
  -> create-triggered initializeStatus determination
  -> read requested roots internally through EML
  -> select roots with initial Status
  -> update only Status to DRAFT through internal EML
  -> return to the consumer
  -> consumer can read DRAFT before commit
  -> consumer COMMIT ENTITIES persists it
```

The planned internal READ ENTITIES uses IN LOCAL MODE to access this BO's transactional state, using the imported keys. No SELECT from the persistence table is suitable for this step: the new order is not yet saved. The internal MODIFY ENTITIES updates only Status for the selected transactional keys. Local mode allows the BO's own implementation to fill its readonly field; the ordinary external EML consumer continues to respect readonly controls. Inspect the target-generated response parameters and handle/forward relevant messages without inventing unsupported components. See [SAP EML](https://help.sap.com/docs/abap-cloud/abap-rap/entity-manipulation-language-eml).

Checking for initial Status makes the operation repeatable and prevents resetting a status already set internally. A create-only trigger avoids resetting status whenever Supplier or another field changes. This does not backfill previously saved blank statuses. The existing permissive authorization stub remains unchanged.

DRAFT here is the business status meaning unsubmitted/preparatory. The order is still an active, non-draft RAP instance after save. No technical draft tables, %is_draft handling or draft actions are introduced.

## Proposed IntegrationStatus default, deferred

Recommend NOT_REQUESTED, already defined in the Phase 0 domain model. A newly created order has no delivery intent, so PENDING would incorrectly imply integration work has been queued. NOT_REQUESTED is distinct from a delivery failure or a supplier rejection.

For this first exercise, implement Status only. IntegrationStatus remains initial until a separate, explicitly explained defaulting extension is authorized. The proposal adds no dispatch or integration behavior.

## Later item and header totals: proposed approach only

For each item, derive TotalAmount from Quantity multiplied by NetPrice on item creation and relevant quantity/price changes. Define rounding explicitly for the stored two-decimal total; later header aggregation must use the same rounded per-item amounts. Currency changes and mixed currencies must be addressed when that step is designed; the current study baseline uses EUR and contains no currency-consistency validation.

The header total must equal the sum of the current surviving items' derived totals in RAP's transactional state. Recomputing that sum is safer than applying incremental plus/minus deltas, which can accumulate errors when requests repeat.

| Item change | Required header-recalculation design |
| --- | --- |
| Create | Identify the parent; include the new buffered item |
| Quantity change | Identify the parent; use the updated quantity and the same item rounding rule |
| NetPrice change | Identify the parent; use the updated price and the same item rounding rule |
| Delete | Retain/resolve the affected parent even if the item is no longer readable; sum only remaining items |
| Last item deleted | Explicitly set the still-existing header total to zero |
| Whole root deleted | Do not attempt to update a removed root |

A root create/update trigger alone is insufficient to establish that every child change causes recalculation. Nor can we assume the item-total determination executes before a header-total determination. Plan a common calculation routine or a calculation step that derives the rounded item totals from current Quantity/NetPrice and sums those same values, so the result is independent of determination scheduling.

Deletion needs a target-system check before finalizing its trigger design. A deleted item's parent association may no longer be readable at an on-modify callback; a create-then-delete item may never have had a database row at all. A SQL sum misses unsaved updates, and looking up only persisted deleted items does not cover that case. Investigate the release-supported delete-trigger/save-time behavior and how affected parent keys remain available. If needed, design an explicit framework-supported way to retain those identities and a save-time reconciliation, without relying on an undocumented callback order or process-global static cache. We will not claim deletion coverage until EML tests prove it.

Required later tests include multiple items, quantity and price changes, deletion of one/last item, create-then-delete before commit, updates followed by deletion, multiple affected parents, and root deletion. These are future calculation tests; none is implemented in this checkpoint.

## Apply the source and test in ADT

Compatibility fix, 2026-09-13: direct appending of read_reported-purchaseorder and update_reported-purchaseorder failed target syntax checks because the generated tables are not directly compatible with this determination's reported-purchaseorder. The [updated Local Types source](../classes/zbp_i_purchaseorder.clas.locals_imp.abap) converts each through CORRESPONDING #( DEEP ... ) into a temporary table typed LIKE the destination, then appends it. This retains root messages from both calls. SAP's [determination example](https://github.com/SAP-samples/abap-platform-rap-opensap/blob/main/week3/unit6.md) also maps EML reports into the handler response using CORRESPONDING. Apply this correction and rerun syntax/activation checks; success is not yet confirmed.

1. Copy the updated [BDEF](../behavior/zjp_i_purchaseorder.bdef) into Behavior Definition ZJP_I_PURCHASEORDER. It adds only initializeStatus on modify { create; } and keeps Status readonly.
2. In ZBP_I_PURCHASEORDER, use ADT Quick Fix if necessary to generate the missing determination method. Apply the updated [Local Types source](../classes/zbp_i_purchaseorder.clas.locals_imp.abap) without duplicating the existing local class or methods. Keep the target-generated signature if the release requires a difference.
3. The implementation uses a local-mode EML read, filters already populated statuses, updates only Status through local-mode EML and forwards root messages. Its DELETE filters an internal table; it does not delete database rows. No commit is added to the handler.
4. Syntax-check and activate the BDEF and behavior pool together as required. Record any compiler diagnostic before changing the agreed design.
5. Apply the updated [ZJP_CL_PO_EML_TEST source](../classes/zjp_cl_po_eml_test.clas.abap), then activate and run it as ABAP Application (Console), normally F9. CREATE deliberately does not supply Status. The test now checks buffered/persisted DRAFT and preserves CRUD cleanup checks.

| Planned assertion | Expected result |
| --- | --- |
| Root read immediately after CREATE | Status DRAFT in RAP's buffer |
| Database before commit | No row for the new UUID |
| Root after create commit | Persisted Status DRAFT |
| Supplier update and commit | Supplier SUP002; Status still DRAFT |
| IntegrationStatus, totals, display number | Still initial/zero at this narrow step |
| Cleanup | Root and item removed through the existing EML deletion flow |

Actual status: runtime-verified complete as reported by the learner. Status DRAFT was verified before and after commit. Item TotalAmount has since passed its runtime test; header TotalAmount is the current checkpoint. IntegrationStatus, validations, technical draft and actions remain pending.
