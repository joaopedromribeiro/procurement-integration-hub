# Phase 9.6 — broker availability and Phase 9 closure

Status: **PHASE 9.6 — CLOSED WITH ENVIRONMENT LIMITATION. PHASE 9 — CLOSED WITH ENVIRONMENT LIMITATION.** This is a closure of the work possible in the inspected DEV environment, not acceptance of a running Event Mesh integration or production cutover.

## Owner-supplied availability evidence

In the inspected DEV subaccount, BTP **Entitlements / Add Service Plans** and **Service Marketplace** showed neither SAP Event Mesh nor SAP Integration Suite, advanced event mesh. The owner's `cf marketplace | grep -Ei "event|mesh"` returned only `alert-notification`, plan `standard`, described as a service exposing platform events and APIs for custom events. That is **SAP Alert Notification Service**, not SAP Event Mesh or Advanced Event Mesh. It is not a substitute for the planned PIH-owned broker, queue/subscription, AMQP consumer, and dead-letter architecture. The observation is specific to this inspected subaccount; it is not a claim about all SAP BTP environments.

## Verified scope

- The RAP DeliveryIntent event producer was implemented and locally verified in A4H. PIH Event Binding `ZJPEBPODLVREQ` is **ACTIVE** and exposes generated external type `zjp.PurchaseOrder.DeliveryRequested.v*` (version `0001 / 0 / 0`). Activation does not establish external publication.
- The network-free consumer-semantics simulator passed **11/11**. The SAP trigger adapter ABAP Unit passed **8/8** with a dispatcher double. The HTTP trigger boundary ABAP Unit passed **13/13** without outbound networking.
- In the inspected DEV runtime, dedicated `ZJP_ROLE=DISPATCH` authorization, HTTP method/request/identity guards, and real trigger-to-coordinator wiring were verified. The positive path used the authorized SAP HTTP boundary, **not** Event Mesh: SAP → existing Phase 7 coordinator → `PIH_OrderDelivery_v1` → CAP/HANA.
- The positive DeliveryIntent ended SAP `DELIVERED`, `ATTEMPT_COUNT=1`, with lease owner/expiry cleared. CPI MPL was `COMPLETED` with `IntermediateError=false`. CAP/HANA persisted the exact delivery as a portal order with `STATUS=RECEIVED`. The [Phase 9.5 evidence](phase-9-5-consumer-trigger.md) records the identity and runtime observations.

## Not proven and not claimed

There was no PIH-owned Event Mesh broker in this environment. Consequently there is **no** runtime proof of real SAP → Event Mesh publication, queue/subscription delivery, an AMQP consumer, broker ACK/redelivery, dead-letter handling, duplicate/redelivery behavior in a real broker, or the external event envelope. There is no production event-driven cutover and no exactly-once delivery claim. The read-only trigger adapter's two committed-state reads still do not lock the PurchaseOrder against a concurrent revision change; that remains a cutover question.

The existing SAP → CPI → CAP and CAP → CPI → SAP HTTP business flows and the Phase 7 delivery intent, retry, lease, UNKNOWN, attempt-history, correlation, and recovery authority remain unchanged. If a suitable PIH-owned broker becomes available later, publication and broker-consumer acceptance require a separate, explicitly authorized runtime exercise; this closure must not be read as that evidence.
