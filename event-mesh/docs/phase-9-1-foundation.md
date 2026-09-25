# Phase 9.1 — Event Mesh offering discovery and event architecture

Status: **CLOSED WITH ENVIRONMENT LIMITATION** on owner-supplied, read-only checks in the current Trial account. This is the 9.1 architecture record. Phase 9.3 later activated and locally verified the RAP producer, but no PIH broker, Event Binding, or deployed external event flow exists. Phase 6–8 HTTP integrations remain the runtime-proven reference and rollback path.

## Owner discovery result (this account only)

- Subaccount **PIH Integration**: Event Mesh was absent from visible Integration Suite capabilities. BTP entitlement/service-plan searches for Event Mesh and `message-client` found no assignable plan. The Integration Suite Event Mesh capability and standalone/default service are therefore **not available through this account's current Trial entitlement**. This is not a claim about all Trial accounts. Advanced Event Mesh was not selected for a small-volume baseline.
- Target A4H SAP system: `/IWXBE/CONFIG` opened; Channel Configuration and AMQP were visible; existing active AMQP channels and outbound bindings were present, including a `sap/s4/beh/product/v1/Product/*` example topic. These are shared-system objects, not PIH-owned, and must not be modified or reused without ownership verification. ADT **New → Event Binding** opened successfully.
- Integration Suite's adapter picker showed **AMQP**. This establishes product capability to select an adapter, not a configured AMQP sender or successful queue consumption.
- Thus SAP event tooling and visible AMQP infrastructure are available, while the **real Event Mesh runtime path is environment blocked** by the current broker entitlement. RAP event syntax and saver emission were subsequently proven locally in 9.3; binding publication, real broker acknowledgement/redelivery, and DLQ remain unproven. Phase 9.2 proved local semantics only; see [the local contract proof](phase-9-2-event-contract.md) and [9.3 SAP evidence](phase-9-3-rap-producer.md).

## Evidence and corrections to the earlier sketch

- `ARCHITECTURE.md` proposes an approval event, queue, Cloud Integration consumer, and CAP ingestion. `docs/environments.md` explicitly defers the actual product, plan, channel, adapter, and quarantine policy. At the 9.1 checkpoint, `event-mesh/` contained no broker configuration, producer, or contract implementation; 9.2 and 9.3 subsequently added a local contract simulator and an A4H RAP producer, respectively, without external broker configuration.
- Current `ZBP_I_PURCHASEORDER` `approve` changes `SUBMITTED` to `APPROVED` only. A separate `sendToSupplier` action creates/reuses the unique DeliveryIntent for `(PurchaseOrderUUID, OrderRevision)` and persists its immutable `PayloadSnapshot` and `PayloadHash` in the same LUW, without sending HTTP or committing. The coordinator later claims and dispatches that intent. Thus `PurchaseOrderApproved` truthfully means *approved*, but is **not** a safe delivery command in the current lifecycle: an approved order may not yet have a durable delivery operation. The diagram in `ARCHITECTURE.md` is a proposal, not a verified implementable route.
- The first delivery-trigger event should therefore be logically `PurchaseOrderDeliveryRequested.v1`, emitted only after the **new** DeliveryIntent and snapshot commit. A separate `PurchaseOrderApproved` notification may be added later, but must not trigger CAP delivery. A `PurchaseOrderSent` event means acknowledged portal receipt, not publication to a broker. No status event may loop back into a send trigger.
- The broker's acknowledgement of publication is not CAP's acknowledgement of the business operation. Introducing a queue does not replace the SAP DeliveryIntent, its claim/attempt/history/retry-window/UNKNOWN policy, or the CAP order/response idempotency contracts. No technical cutover is authorized until the event consumer can invoke the **existing coordinator for the same DeliveryUUID** and its result remains recorded by the existing SAP state machine. A narrow authenticated dispatch trigger may be necessary; its feasibility and commit/ack boundary need a separate design and runtime proof. Direct queue → CI mapping → CAP would bypass the coordinator and is **not** a drop-in replacement.

## Product candidates (current-account entitlement now inspected)

| Candidate | Broker and prerequisites | SAP outbound / Cloud Integration | Fit |
| --- | --- | --- | --- |
| **SAP Integration Suite, Event Mesh capability** | Broker initiated in subscribed Integration Suite; CF offering **SAP Integration Suite, Event Mesh**, plan `message-client`, plus entitlement and OAuth-bound client. Supports AMQP 1.0 over WebSocket, MQTT 3.1.1 over WebSocket, and HTTP. | SAP S/4HANA Event Mesh integration documentation lists this offering. Cloud Integration's **AMQP Sender for SAP Event Mesh** consumes a queue/topic subscription over AMQP WebSocket; verify adapter in this tenant. | Preferred conditional small-volume candidate because Integration Suite already exists; capability, broker, entitlement and target channel must be verified. |
| **SAP Event Mesh default plan** (standalone) | Separate CF SAP Event Mesh service instance, `default` plan; independent entitlement and message client. Do not assume the retired `lite` plan. | SAP S/4HANA documentation lists Default Plan as another route. Cloud Integration AMQP sender is documented for SAP Event Mesh, subject to actual endpoints/adapter support. | Valid fallback only if available and the Integration Suite capability is not; separate service lifecycle. |
| **SAP Integration Suite, advanced event mesh** | Separate subscription/entitlement, validation/default plan setup and broker instance; not the same capability or service plan. Provides AMQP broker endpoint and its own operational model. | SAP documents an **Advanced** `/IWXBE/CONFIG` channel and an Advanced Event Mesh sender adapter (and AMQP integration options) in Cloud Integration. | Not the default for this low-volume learning baseline; consider only if the simpler offerings are unavailable or a concrete requirement warrants it. |

Sources: [Integration Suite capability broker](https://help.sap.com/docs/integration-suite/sap-integration-suite/initiating-event-mesh), [message-client plan/prerequisites](https://help.sap.com/docs/integration-suite/sap-integration-suite/configure-message-client), [capability protocols](https://help.sap.com/docs/integration-suite/sap-integration-suite/publish-and-consume-events), [standalone default plan](https://help.sap.com/docs/event-mesh/event-mesh/event-mesh-default-plan-concepts), [SAP outbound default/capability integration](https://help.sap.com/docs/abap-cloud/abap-integration-connectivity/integrating-with-sap-event-mesh?version=s4_hana), [Advanced SAP channel](https://help.sap.com/docs/abap-cloud/abap-integration-connectivity/integrating-with-sap-event-mesh-advanced-plan), [Cloud Integration AMQP sender](https://help.sap.com/docs/integration-suite/sap-integration-suite/amqp-sender-for-sap-event-mesh), [Advanced sender](https://help.sap.com/docs/integration-suite/sap-integration-suite/configure-advanced-event-mesh-sender-adapter).

SAP documents RAP business events and ADT event bindings for S/4HANA 2022 FPS00 onward, which is evidence of release-family support, **not proof** that this SAP_BASIS 758 SP0001 / S4CORE 108 SP0001 client has the required authorization, component support, outbound channel or communication setup. Later verify BDEF event syntax/activation and binding in ADT; `/IWXBE/CONFIG` channel types, outbound bindings, SM59/OAuth/certificates as applicable; and commit-coupled publication using a safe disposable order. Advanced uses a different channel. Do not invent ABAP syntax or configure a channel in 9.1. Sources: [RAP events](https://help.sap.com/docs/abap-cloud/abap-rap/develop-business-events), [ADT bindings](https://help.sap.com/docs/abap-cloud/abap-development-tools-user-guide/creating-event-bindings), [S/4HANA Event Mesh integration](https://help.sap.com/docs/abap-cloud/abap-integration-connectivity/integrating-with-sap-event-mesh?version=s4_hana), [Advanced channel](https://help.sap.com/docs/abap-cloud/abap-integration-connectivity/integrating-with-sap-event-mesh-advanced-plan).

Cloud Integration should remain the routing/mapping boundary. A **separate** queue-consumer iFlow is favored over changing either verified HTTP iFlow in place. It would validate the event, preserve correlation, and invoke an as-yet-unbuilt narrow SAP trigger for the existing DeliveryUUID; the SAP coordinator would continue to use the existing OrderDelivery HTTP iFlow and persist the outcome. Queue → CI → existing mapping → CAP **unchanged** is false: the event envelope is not the existing immutable delivery snapshot, and direct CAP delivery would bypass SAP attempt/result authority. Queue → CAP directly offers less architectural value and the same authority problem. The proposed trigger must be idempotent and authorize only its single delivery; do not expose generic coordinator execution. The CI acknowledgement boundary, whether the trigger waits for committed SAP result, and broker redelivery/quarantine settings remain design gates for 9.2–9.5.

## First logical event contract (proposal, not SAP wire format)

```json
{
  "specversion": "1.0",
  "id": "<publication UUID>",
  "source": "<stable SAP system/client and PurchaseOrder source>",
  "type": "com.pih.purchaseorder.deliveryrequested.v1",
  "time": "<UTC commit-visible event time>",
  "subject": "<PurchaseOrderUUID>",
  "data": {
    "purchaseOrderId": "<PurchaseOrderUUID>",
    "orderRevision": 1,
    "deliveryId": "<DeliveryUUID>",
    "payloadHash": "<persisted PayloadHash>"
  }
}
```

`id` identifies a publication, not the business operation. `(purchaseOrderId, orderRevision)` and `deliveryId` identify the **one** durable operation; the hash binds the event to the persisted immutable snapshot. The correlation ID for each actual dispatch attempt remains the Phase 7 attempt correlation and flows SAP → CI → CAP; event ID is retained only as a causation/diagnostic link. No editable live-order representation is included. This identity-only event is small and replayable, but requires a commit-visible lookup of the **existing DeliveryIntent** by `deliveryId` and a safe dispatch trigger; neither endpoint is currently present. Publishing the complete snapshot could remove that read dependency but would duplicate sensitive payload into broker retention, raise size/schema limits, and still not solve SAP attempt/result authority. Do not choose full snapshot or claim a native RAP envelope matches this JSON until target and broker probes confirm it. A missing/mismatched snapshot is a poison condition, never an invitation to rebuild from the current PO.

## Delivery/acknowledgement policy to prove, not assume

| Case | Consumer action and durable identity | Ack / retry / evidence |
| --- | --- | --- |
| 1. Same event duplicated | Resolve `deliveryId`; existing claim/state wins. | Ack only after confirming committed no-op or completed result; event ID in broker/CI trace. |
| 2. Same operation, new event ID | Deduplicate on `deliveryId` plus PO/revision, not event ID. | Same as above; record both publication IDs as causation if supported. |
| 3. Out-of-order revision | Do not use current mutable PO; verify event revision against persisted intent. | Obsolete/invalid event is quarantined or acknowledged as an explicitly classified no-op; never dispatch a different revision. |
| 4. Crash before ack | Broker redelivers after lock/visibility expiry. | Existing SAP claim/lease bounds duplicate dispatch; broker + SAP traces identify it. |
| 5. Crash after CAP accepted, before ack | Redelivery resolves same DeliveryUUID. | CAP idempotency and SAP persisted receipt/UNKNOWN semantics govern; never mint a new intent or infer success from broker ack. |
| 6. Broker redelivery | Re-run the same validation and claim path. | Ack only after a durable classification; delivery history remains SAP authority. |
| 7. CAP unavailable | Coordinator classifies bounded retry/UNKNOWN per Phase 7. | CI/broker must not add an unbounded competing retry loop; ack strategy depends on committed coordinator result. |
| 8. CI unavailable | Queue retains pending message within broker limits. | No ack; monitor depth/age and retention; old HTTP path remains rollback. |
| 9. Poison payload | Reject schema, identity, hash mismatch or missing intent without dispatch. | Bounded redelivery followed by broker DLQ/equivalent quarantine with safe diagnostics; support must not edit snapshots. |
| 10. Backlog | Throttle consumer to SAP/CAP capacity; avoid ordering assumptions across orders. | Monitor oldest age, depth, redelivery, DLQ, and SAP PENDING/IN_FLIGHT; alert before retention expiry. |

The actual adapter settlement behavior, lock/visibility duration, retries, DLQ support, and their limits **must be demonstrated for the selected product and plan**. CI MPL, broker queue/DLQ telemetry and SAP DeliveryIntent/attempt history need a shared `deliveryId` plus traceable event/attempt correlation. No exactly-once delivery is claimed. The Cloud Integration AMQP sender consumes **queues** (including topic-subscribed queues), not an unretained topic directly. [SAP adapter documentation](https://help.sap.com/docs/integration-suite/sap-integration-suite/amqp-sender-for-sap-event-mesh).

## Safe migration boundary

1. Keep the current synchronous `sendToSupplier` → committed DeliveryIntent → coordinator → CI HTTP → CAP path unchanged, available, and default. The event route starts disabled; local event fixtures and then shadow publication have no dispatch authority.
2. Before enabling a real event route, prove publication only for a committed intent, a narrow idempotent trigger for that same DeliveryUUID, precise broker acknowledgement after durable SAP classification, and broker quarantine. The trigger must not create a second DeliveryIntent or call CAP directly.
3. Select **one dispatch trigger per order/revision**. Switching a cohort to the event trigger disables its legacy automatic trigger, but retains manual recovery through Phase 7. A single shared SAP claim protects against races; monitor both paths and rollback by disabling new event dispatch and draining/quarantining queued messages safely before restoring the old trigger. Never replay both blindly.
4. This is a **trigger migration**, not replacement of the SAP → CI HTTP leg or CAP → CI → SAP supplier response leg. If the target cannot support commit-coupled event publication and coordinator reuse with a sound ack boundary, stop at advisory events; do not cut over Phase 7 delivery.

## Subphases and acceptance gates

| Phase | Scope and independently testable exit |
| --- | --- |
| 9.1 | Confirm offering, entitlement, target channel and CI adapter by read-only checks; freeze logical semantics and identify trigger/ack design gap. No resources. |
| 9.2 | Versioned event fixture and local duplicate/new-ID/out-of-order/poison tests; define exact coordinator trigger contract, commit boundary and broker-specific ack/quarantine policy. No runtime cutover. |
| 9.3 | RAP producer definition, target compiler/save-image proof and local saver Event TDF tests. **Completed locally**; no Event Binding or external rollback/publication proof is claimed. Keep dispatch off. |
| 9.4 | Owner configures least-privilege broker client, topic, subscribed queue and quarantine using selected supported plan; prove publish/subscribe and authorization with disposable messages. |
| 9.5 | Add isolated CI consumer and narrow authorized SAP trigger; prove exact existing DeliveryIntent/coordinator path and correlated durable outcome, without altering the proven HTTP iFlows. |
| 9.6 | One disposable SAP → broker → CI trigger → SAP coordinator → existing CI HTTP → CAP delivery; verify single CAP order and same DeliveryUUID. |
| 9.7 | Controlled duplicates, crash/redelivery, CAP/CI outage, poison, backlog, retention and manual recovery; verify bounded policy and no second business effect. |
| 9.8 | Cohort-based trigger cutover/rollback, monitoring/runbook, exports and source sync; close only with owner-supplied runtime evidence. Supplier-response events remain optional and separate. |

## Owner read-only discovery checks (completed)

1. In the **trial subaccount** BTP cockpit, inspect **Services → Instances and Subscriptions** for the Integration Suite subscription; in Integration Suite inspect **Settings/Capabilities** for Event Mesh availability/activation and whether a broker has already been initiated. Record names/status only, no keys.
2. In BTP cockpit **Entitlements → Entity Assignments** and **Services → Service Marketplace**, inspect the exact visible offerings/plans: `SAP Integration Suite, Event Mesh` / `message-client`, standalone `SAP Event Mesh` / `default`, and `SAP Integration Suite, advanced event mesh` if shown. Record region, assigned entitlement and available plan, not credentials. Visibility does not prove working channel connectivity.
3. In target SAP client, inspect ADT **New → Other → ABAP → Event Binding** availability and package tooling (do not create); inspect `/IWXBE/CONFIG` existing channels/channel types and outbound topic-binding options read-only if authorized. Record whether a standard/default or Advanced channel is offered, plus release/client; do not create destinations or paste service keys.
4. In Integration Suite's iFlow editor, inspect available sender adapters for **AMQP Sender for SAP Event Mesh** and, only if considering AEM, **Advanced Event Mesh Sender**. Do not modify or deploy an iFlow. These observations, together with the SAP channel, settle the candidate; they do not yet prove end-to-end operation.

The checks above were completed by the owner without creating resources. Resolved: no assignable Event Mesh offering in this account; SAP Event Binding and `/IWXBE/CONFIG` tooling visible; generic CI AMQP adapter visible. Still open: entitlement on a future suitable account; which SAP channel is appropriate and PIH-owned; **external** commit/rollback publication behavior; a safe narrow coordinator trigger; exact adapter compatibility with the selected broker; broker ACK/redelivery/DLQ/retention guarantees; and topic/queue ACLs. RAP compiler/save-image and local event-emission questions were subsequently resolved in [9.3](phase-9-3-rap-producer.md); none of the external guarantees is silently assumed.
