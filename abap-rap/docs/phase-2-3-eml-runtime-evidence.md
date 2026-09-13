# Phase 2.3 — verified SAP EML runtime evidence

Evidence source: learner-supplied execution report and ADT console output for ZJP_CL_PO_EML_TEST in the SAP S/4HANA study environment. The assistant reviewed the supplied output; it did not independently connect to SAP. Exact S/4HANA/ABAP release remains unrecorded. This is actual SAP runtime evidence, superseding the earlier source-only and activation-assumed status for this baseline.

The output ends with:

```text
PASS: managed create/read/update/delete and composition cleanup.
```

## Observed execution

| Stage | Observed result |
| --- | --- |
| Create MAPPED | PO_1 mapped to root UUID 37FC3FA8EB2D1FD1ABE1DE7A4629379D; ITEM_1 mapped to item UUID 37FC3FA8EB2D1FD1ABE1DE7A4629579D |
| Buffered EML read | One header and one item returned before commit; item referenced the root UUID |
| Database before first commit | No matching rows in ZJP_PO_H or ZJP_PO_I |
| Create commit | sy-subrc = 0; one header with Supplier SUP001 and one item persisted |
| Item values | ItemNumber 00010; Material MAT001; Quantity 2; NetPrice 750; Currency EUR |
| Update and second commit | sy-subrc = 0; EML read and database output showed Supplier SUP002 |
| Root delete and third commit | sy-subrc = 0; neither header nor item remained for the test UUID |
| Request/save responses | Displayed FAILED and REPORTED tables were empty throughout the successful run |

Managed root audit maintenance is also visible: before commit the displayed audit values were initial; after create, CreatedAt and LocalLastChangedAt were 20260913010338.803371. After update, CreatedAt remained unchanged and LocalLastChangedAt advanced to 20260913010338.914723. The evidence summary omits the study user's account name. This observation does not establish stale-ETag rejection or concurrent lock behavior.

## What can now be claimed

Managed create/read/update/delete, create-by-association through _Items, header/item composition, managed UUID assignment, persistence mapping, transaction-buffer visibility, explicit COMMIT ENTITIES saving and composition cleanup on root deletion were executed successfully in SAP.

The run exercised %cid, %cid_ref, %target, MAPPED and %tky, and inspected FAILED/REPORTED at request and save boundaries. Their successful-path usage is verified. Error and warning population, duplicate/missing-key handling, negative authorization and every possible association-authorization path were not tested by this run.

The corrected BDEF and behavior pool were usable by the executing consumer. Phase 2.1 (BDEF), Phase 2.2 (behavior pool and permissive authorization stub) and Phase 2.3 (EML CRUD verification) are complete for this scoped baseline. Completion of the stub does not mean production authorization exists.

## Expected initial values

PurchaseOrderNumber, SupplierName, Status and later integration/business fields remained initial. Header and item TotalAmount remained zero despite Quantity 2 and NetPrice 750. Those observations match the absence of derivation/defaulting/calculation logic in the tested baseline; they are not test failures.

No draft, determination, validation, business action, OData/Fiori, CAP, Integration Suite, Event Mesh or API Management implementation is demonstrated by this output.

## Next checkpoint

The [status-initialization plan](phase-2-4a-status-initialization-plan.md) starts Phase 2.4. This evidence describes the pre-determination baseline. A later status test must produce DRAFT; do not retroactively change this run's observed blank Status to DRAFT.
