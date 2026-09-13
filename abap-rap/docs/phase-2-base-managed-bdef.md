# Phase 2 — base managed BDEF checkpoint

Phase 2.1 is complete. The original compiler corrections below remain part of the baseline, now exercised by the [successful SAP EML test](phase-2-3-eml-runtime-evidence.md). Phase 1 remains complete. The current checkpoint is the [status-initialization plan](phase-2-4a-status-initialization-plan.md).

## Design

One Behavior Definition repository object, ZJP_I_PURCHASEORDER, contains both entity sections. PurchaseOrder is the root and maps to ZJP_PO_H. PurchaseOrderItem is the child and maps to ZJP_PO_I. The [complete BDEF source](../behavior/zjp_i_purchaseorder.bdef) is manual ADT source, not an exported repository package.

| Concern | Declaration and meaning |
| --- | --- |
| Managed persistence | `managed implementation in class ZBP_I_PURCHASEORDER unique;` retains framework standard persistence and names the required behavior pool |
| Explicit contract | `strict ( 2 );` requests strict modeling checks; target release must accept it |
| Root operations | create, update and delete |
| Child creation | `association _Items { create; }` on the root creates items in a known parent context |
| Child operations | update and delete; no independent child create declaration |
| Locking | Root is lock master; child is lock dependent through `_PurchaseOrder`, so changing an item uses its header's lock |
| ETags | Each entity uses its own LocalLastChangedAt; lock dependency and ETag ownership are separate choices |
| UUIDs | Managed numbering for each entity's own UUID key, marked readonly to consumers |
| Parent identity | The child PurchaseOrderUUID is readonly and supplied through create-by-association; do not independently generate it |
| Authorization | Root `authorization master ( instance )`; child `authorization dependent by _PurchaseOrder`. The root requires an instance-authorization handler; declaration alone implements no permission policy |
| Mapping | Every exposed scalar CDS field maps explicitly to its persistence column; CLIENT is handled by the framework and is not an exposed CDS field |

The earlier claim that this BDEF needs no custom class is withdrawn for the target system and current contract. Declaring instance authorization requires its implementation method in a behavior pool; this does not require manually implementing managed CRUD. See [SAP authorization definition](https://help.sap.com/docs/ABAP_PLATFORM_NEW/fc4c71aa50014fd1b43721701471913d/2a26db5640364b46b843dca786c495d1.html).

## Compiler feedback and correction

| Attempt | Reported SAP diagnostic | Current correction |
| --- | --- | --- |
| Rejected: `authorization master ( none )` | "global \| instance was expected, not none." | Root uses `authorization master ( instance )` |
| Authorization clauses removed with strict(2) retained | "The behavior definition is strict, which means that every entity must be flagged as authorization master or as authorization dependent." | Both entities explicitly participate; child depends on `_PurchaseOrder` |
| Instance authorization declared without an implementation class | "Operations need to be implemented for the entity 'ZJP_I_PURCHASEORDER', which means an implementation class needs to be specified." | Managed header now names ZBP_I_PURCHASEORDER; class and handler implementation are the next required artifact |

These are learner-reported findings from the SAP S/4HANA study system. Exact release remains unrecorded. The real compiler is authoritative over generic examples; the updated source is not yet evidence of successful activation.

## Field behavior

The root exposes Supplier, CompanyCode, PurchasingOrganization, PurchasingGroup and Currency for ordinary writes. SupplierName and PurchaseOrderNumber are reserved for later derivation/numbering. Administrative, computed, business-status and integration-result fields are readonly. Items expose ItemNumber, material fields, Quantity, UnitOfMeasure, NetPrice and Currency for ordinary writes; their own UUID, parent UUID, total and administrative timestamp are readonly.

Readonly does not calculate a field. Status and display number therefore remain initial, totals remain zero, and integration fields remain initial for newly created records until their later logic is added. No validation rejects an empty supplier, zero quantity, negative price or mismatched item currency in this checkpoint. No state-dependent edit/delete restrictions exist yet. These are deliberate learning boundaries, not completed business logic.

The existing CDS administrative annotations and mapped readonly fields allow the managed runtime to maintain audit data. Each LocalLastChangedAt is the instance ETag; LastChangedAt is not declared as a draft total ETag here. No draft is added. ETag declaration/activation prepares optimistic concurrency, but does not demonstrate stale-request handling; that needs an appropriate consumer test later. An ordinary EML update is not automatically an HTTP If-Match test.

## ADT objects and activation dependency

1. Open the active data definition ZJP_I_PurchaseOrder.
2. Choose New → Behavior Definition. Exact ADT repository object type: **Behavior Definition (BDEF)**. Name: **ZJP_I_PURCHASEORDER**. Select implementation type Managed and your existing package/transport.
3. Replace the entire generated template with the linked source. Keep both entity sections in this one BDEF. Do not create ZJP_I_PURCHASEORDERITEM as a separate BDEF.
4. Retain `managed implementation in class ZBP_I_PURCHASEORDER unique;` and `strict ( 2 );`. Keep root instance authorization and child authorization dependency.
5. The learner has confirmed the [behavior implementation architecture](phase-2-behavior-implementation-architecture.md). The BDEF cannot be treated as independently activatable while its required implementation is missing in SAP.
6. Follow the [minimal behavior-pool lesson](phase-2-minimal-behavior-pool.md) to create the **ABAP Class (behavior pool)** ZBP_I_PURCHASEORDER and the required root authorization method. Keep the target system's generated signatures and use the supplied source in the correct editor areas. Syntax-check and activate BDEF plus class together as needed; the subsequent EML run confirms this BO is usable in SAP.

Open Declaration on persistent tables, mapped fields and associations should resolve to existing Phase 1 objects. Record any further exact diagnostic rather than removing strict mode, authorization or concurrency to bypass it. Keep the two confirmed Phase 1 compatibility fixes intact.

## Test this checkpoint

| Test | Expected result | Actual |
| --- | --- | --- |
| Syntax-check and activate BDEF plus required behavior pool | Active BDEF containing both entity sections and active ZBP_I_PURCHASEORDER | Complete: learner-supplied successful SAP EML execution after the documented fixes |
| Inspect persistence mapping | Root points to ZJP_PO_H; child points to ZJP_PO_I; all mapped aliases resolve | Locally checked; SAP check pending |
| Inspect operations | Root create/update/delete; `_Items` supports create-by-association; child update/delete | Locally checked; SAP check pending |
| Inspect concurrency fields | Both ETag references resolve to the entity's mapped LocalLastChangedAt | Locally checked; SAP check pending |
| Inspect persistence during EML | The new test UUID has no persisted rows before commit; committed rows appear and are later removed | Verified in the learner-supplied EML console snapshots; see the runtime evidence record |

Activation verifies the behavior contract, not actual CRUD execution. Data Preview remains a read tool. The [EML checkpoint](phase-2-eml-runtime-test.md) now supplies the create/read/update/delete exercise; its runtime results are now verified from learner-supplied SAP output. No projection behavior or OData service is provided by the base BDEF step.

Current stop point: the [status-initialization plan](phase-2-4a-status-initialization-plan.md). The successful EML baseline and base BDEF source are unchanged in this planning update.
