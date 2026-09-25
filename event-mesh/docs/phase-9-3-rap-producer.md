# Phase 9.3 — RAP business-event producer

Status: **IMPLEMENTED AND LOCALLY VERIFIED in A4H** on owner-supplied SAP compiler, debugger, and ABAP Unit evidence. External Event Binding, Event Mesh publication, AMQP delivery, queue redelivery/ACK/DLQ, and external rollback semantics are **not verified**. The currently inspected BTP Trial account has no assignable PIH Event Mesh entitlement; no PIH-owned broker exists. Do not reuse the shared SAP `/IWXBE/` channels or bindings.

## Active implementation and repository mirrors

`PurchaseOrderDeliveryRequested` describes a new durable delivery request, not approval: `approve` only moves the PurchaseOrder to APPROVED; `sendToSupplier` creates the DeliveryIntent and freezes its snapshot/hash. The producer is therefore on the **DeliveryIntent root**, whose CREATE is the new-operation signal. An existing FAILED/UNKNOWN intent is retried through UPDATE; PENDING/IN_FLIGHT re-entry does not create a second intent. The Phase 7 coordinator and existing SAP → Cloud Integration → CAP HTTP path remain unchanged.

The owner activated these A4H artifacts, now reflected in the repository:

| Artifact | Active result / mirror |
| --- | --- |
| `ZJP_A_PODeliveryRequested` | [`abap-rap/cds/zjp_a_podeliveryrequested.ddls`](../../abap-rap/cds/zjp_a_podeliveryrequested.ddls): `PurchaseOrderUUID : sysuuid_x16`, `OrderRevision : abap.int4`, `PayloadHash : abap.char(64)` only. |
| `ZJP_I_DeliveryIntent` BDEF | [`abap-rap/behavior/zjp_i_deliveryintent.bdef`](../../abap-rap/behavior/zjp_i_deliveryintent.bdef): `managed with additional save implementation in class ZBP_I_DELIVERYINTENT unique;` and `event PurchaseOrderDeliveryRequested parameter ZJP_A_PODeliveryRequested;`. Existing CRUD and mapping are preserved. |
| `ZBP_I_DELIVERYINTENT` local implementation | [`abap-rap/classes/zbp_i_deliveryintent.clas.locals_imp.abap`](../../abap-rap/classes/zbp_i_deliveryintent.clas.locals_imp.abap): a saver with `save_modified` raising the event from `create-deliveryintent` only. Existing authorization handler is preserved; there is no HTTP, coordinator, EML mutation, COMMIT, ROLLBACK, lease/retry/attempt or state change in the saver. |

The A4H compiler **rejected** a `DeliveryUUID` field in the abstract parameter because the DeliveryIntent event entity key already supplies it. The logical contract remains four business identifiers: `DeliveryUUID` from the RAP event key plus `%param` containing `PurchaseOrderUUID`, `OrderRevision`, and `PayloadHash`. Do not add the key to the abstract parameter. The parameter does not carry the full `PayloadSnapshot` or mutable commercial fields.

The saver method uses this active-equivalent logic: if `create-deliveryintent` is nonempty, raise `ZJP_I_DeliveryIntent~PurchaseOrderDeliveryRequested` once with `DeliveryUUID = delivery_intent-DeliveryUUID` and `%param` set from that CREATE image. UPDATE-only retry/re-entry cannot enter that loop. A deferred `ltc_delivery_event` declaration and saver `FRIENDS ltc_delivery_event` reflect the owner-described protected-method test access. The owner provided the method's active-equivalent source and test results, **not the complete ACTIVE local test-class source**; the repository has no established behavior-pool local-test mirror. Therefore this record does not claim byte-for-byte equivalence of the unseen test-class implementation. Its three assertions are described below, not reconstructed from memory.

## Evidence levels

### A. Compiler evidence — owner supplied

The abstract entity without duplicate `DeliveryUUID`, the managed additional-save BDEF/event declaration, and the saver activated on A4H (`SAP_BASIS 758 SP0001`, `S4CORE 108 SP0001`). The initial parameter variant with `DeliveryUUID` was rejected by that compiler; the active form excludes it. This target result supersedes the earlier generic candidate. Repository files remain source mirrors; no SAP activation was performed by Codex.

### B. Save-image evidence — owner supplied

An isolated A4H probe ran CREATE DeliveryIntent, obtained managed `DeliveryUUID`, UPDATEd the *same* intent with `PayloadSnapshot` and `PayloadHash`, then `COMMIT ENTITIES`. At `save_modified`, the debugger showed `create-deliveryintent` already had the **final consolidated state**, including DeliveryUUID, PurchaseOrderUUID, OrderRevision, PayloadSnapshot, PayloadHash, DispatchState, approval evidence, and managed timestamps. Thus this target needs no CREATE/UPDATE merge, late SELECT, `WITH FULL DATA`, or separate lookup for the final hash. This is **A4H runtime evidence**, not a universal RAP guarantee.

### C. ABAP Unit / RAP Event Test Double — owner supplied

The target provides `CL_RAP_EVENT_TEST_ENVIRONMENT`, `IF_RAP_EVENT_TEST_ENVIRONMENT`, `IF_RAP_EVENT_DOUBLE_SINGLE`, `IF_RAP_EVENT_DOUBLE_S_VERIFY`, and the verified `CREATE`, `CLEAR`, `DESTROY`, `GET_EVENT`, `VERIFY`, `IS_RAISED_TIMES`, and `GET_PAYLOAD` APIs. The behavior-pool test class used friend access to call protected `save_modified` directly. Final run: **3 methods, 0 failures, 0 errors**.

| Test | Observed result | Proven scope |
| --- | --- | --- |
| `new_intent_raises_event` | PASS | CREATE input raised exactly one event; captured DeliveryUUID key and PurchaseOrderUUID, OrderRevision, PayloadHash matched the input. |
| `no_create_no_event` | PASS | Empty CREATE input raised zero events. |
| `update_only_no_event` | PASS | UPDATE-only input raised zero events, preserving no-republication for normal existing-intent retries. |

These tests directly exercise the saver; they do **not** prove an end-to-end `sendToSupplier` COMMIT, an external publication, or rollback behavior of an Event Binding/broker. No such result should be inferred from the green unit run.

### D. Unproven / environment blocked

No Event Binding was created or changed. No shared `/IWXBE/` channel or binding was modified or reused. No PIH broker entitlement, topic, queue, CI consumer, or callback exists in this account. Accordingly there is no proof of Enterprise Event Enablement publication, Event Mesh routing, AMQP ACK/redelivery, DLQ, exactly-once effects, or externally visible rollback semantics. A future bound event must be tested against an explicitly PIH-owned environment, not the shared channels.

## Event-envelope boundary and future route

The RAP event carries **business identity**. SAP Enterprise Event Enablement/Event Binding is responsible for publication context such as CloudEvents `specversion`, `id`, `source`, `type`, and potentially `time`/`subject`; do not manually mint an event publication UUID in `sendToSupplier`. The actual external type/topic/envelope remains unverified until an Event Binding is inspected. The Phase 9.2 logical shape still identifies `purchaseOrderId`, `orderRevision`, `deliveryId`, and `payloadHash`, represented on this SAP target by the entity key plus the three-field `%param`. `id` is publication identity; DeliveryUUID is the durable delivery operation identity. No exactly-once claim is made.

Future flow, **not implemented here**: `sendToSupplier` → committed DeliveryIntent → `PurchaseOrderDeliveryRequested` → PIH-owned Event Binding/broker/queue → consumer → narrowly and idempotently trigger the **existing** coordinator for that DeliveryUUID → existing SAP HTTP → Cloud Integration → CAP transport. The event is a dispatch trigger/reference, not the authoritative order payload. It must not bypass the coordinator or create a second DeliveryIntent.

## Next gate

Phase 9.3 is locally verified within the evidence above. Phase 9.4 external configuration is **not started**. Before any Event Binding or broker work, the owner must establish explicit PIH ownership and an assignable broker entitlement in the chosen environment. Then separately verify external event metadata, commit/rollback publication boundary, topic/queue ACLs, ACK/redelivery, DLQ, and the coordinator-trigger design. Do not touch existing shared `/IWXBE/` artifacts.
