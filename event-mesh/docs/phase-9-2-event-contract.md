# Phase 9.2 — Local event contract and consumer-decision proof

Status: **CLOSED for local contract/semantics only**. Phase 9.3 subsequently activated and locally verified the SAP RAP producer; see [its evidence record](phase-9-3-rap-producer.md). No PIH Event Binding, Event Mesh broker, Cloud Integration consumer, callback, queue acknowledgement, or external event delivery is implemented or verified.

## Frozen first logical event

`PurchaseOrderDeliveryRequested.v1` is a notification about an **already committed** DeliveryIntent, not an approval command. In the current RAP lifecycle, `approve` only moves the business order to `APPROVED`; `sendToSupplier` creates or reuses the durable intent and stores its immutable `PayloadSnapshot` and `PayloadHash`. An event that means merely `PurchaseOrderApproved` cannot safely start delivery.

The logical CloudEvents-compatible shape is in [`../payloads/purchase-order-delivery-requested-v1.schema.json`](../payloads/purchase-order-delivery-requested-v1.schema.json), with one synthetic example beside it. Required envelope: `specversion=1.0`, canonical publication UUID `id`, stable `source`, `type=com.pih.purchaseorder.deliveryrequested.v1`, UTC `time`, `subject=purchaseOrderId`, and `data` containing `purchaseOrderId`, positive integer `orderRevision`, canonical `deliveryId` and 64-hex-character `payloadHash`. No mutable live-order fields or full order payload are permitted. This is a **logical fixture**, not a claim about the eventual native SAP event wire format.

`id` identifies a publication; `deliveryId` identifies the durable business operation. The consumer checks the already-existing DeliveryIntent by `deliveryId`, compares purchase order, revision, and hash, then uses authoritative known revision/state. It never creates an intent, rebuilds a snapshot, or generates another CAP order identity. A republish with a new `id` cannot bypass this check. The actual outbound transport correlation remains the Phase 7 attempt correlation; the event ID is only causation metadata.

**Decision: identity-only event.** A full snapshot could avoid a subsequent read, but it would replicate sensitive business payload and the existing delivery contract into broker retention, increase size/schema coupling, and still not solve SAP claim/attempt/UNKNOWN authority. The identity-only event preserves the existing immutable snapshot as source of truth, at the cost of a commit-visible SAP lookup and a narrow, authenticated trigger for the same DeliveryUUID. Neither production endpoint exists yet. Missing or hash-mismatched intent is not repaired from the live PO; it is held for support/quarantine. No SAP → CAP HTTP payload changes are proposed.

## Isolated simulator

[`../src/consumer.mts`](../src/consumer.mts) runs only against `LocalDeliveryRegistry`, a deterministic in-memory census representing **pre-existing committed** DeliveryIntents. `consumeEvent` validates the logical envelope, resolves the record, checks immutable identity/hash and latest revision, then invokes an injected callback at most once while that record is `READY`. The registry marks it `IN_FLIGHT` before invocation; the callback may mark it `COMPLETED` to simulate observing a durable business result. No simulator status is a new SAP status. No SAP, HANA, Event Mesh, Cloud Integration, CAP runtime, network, or credentials are used. The model deliberately does not simulate real cross-process durability or a broker's settlement timer.

| Test | Expected local decision | Actual proof |
| --- | --- | --- |
| First valid event | `DISPATCH`; one callback; ACK eligible only after simulated completion | PASS |
| Exact duplicate | `DUPLICATE`; no second callback | PASS |
| Same operation, new event ID | `ALREADY_COMPLETED`; no second callback | PASS |
| Same delivery, conflicting revision/hash/order | `CONFLICT`; quarantine; no callback | PASS |
| Older revision with authoritative newer record | `STALE`; no callback | PASS |
| Redelivery before ACK while in flight | `DUPLICATE`; no second callback; no ACK | PASS |
| Success followed by lost ACK and redelivery | `DUPLICATE`; ACK eligible; one business callback total | PASS |
| Malformed/unsupported event | `INVALID_EVENT` / `UNSUPPORTED_VERSION`; quarantine | PASS |
| Unknown DeliveryUUID | `UNKNOWN_DELIVERY`; no callback or fabricated record | PASS |
| Revision 2 arrives before revision 1 | Revision 2 dispatches; revision 1 is `STALE` | PASS |

An eleventh test proves that a callback throwing after invocation yields `AMBIGUOUS`, no ACK, and no blind second dispatch. It must be reconciled against the existing SAP delivery state. Tests run with Node's built-in runner and TypeScript stripping, using the repository's Node 22 baseline; no package was installed for this simulator:

```text
node --experimental-strip-types --test event-mesh/test/consumer.test.mts
11 tests passed, 0 failed
cap-supplier-portal/node_modules/.bin/tsc.cmd -p event-mesh/tsconfig.json
PASS
```

## Intended acknowledgement and recovery boundary

- ACK a duplicate, completed operation, or stale event **only after** the authoritative SAP record proves the safe outcome; a stale event is an explicit no-op in this design.
- Permanently malformed, unsupported, conflicting, or unknown-identity events: no business dispatch; classify for observable quarantine/DLQ equivalent. The simulator marks `quarantine=true`, `ack=false`; a real adapter's settlement/reject mechanism remains product-specific and unverified.
- While the same operation is `IN_FLIGHT`, or a dispatch result is ambiguous: no ACK and no second blind callback. Resolve the existing claim, attempt history, lease, and if necessary the Phase 7 `UNKNOWN` path. A transient downstream outage should not be converted into a new independent retry machine.
- On ordinary successful dispatch, ACK only when a durable safe SAP outcome is observable. Broker publication/consumption ACK is not portal delivery. A broker redelivery must re-resolve the same DeliveryUUID; CAP's existing idempotency remains the residual protection if a prior send reached CAP but its response was lost.
- Real lock duration, settlement, retry/redelivery, retention, and DLQ behavior cannot be frozen as fact until an entitled offering, configured adapter, and runtime tests exist. The current Trial account cannot perform those proofs.

Cutover remains trigger-only: committed DeliveryIntent → event → queue → isolated consumer → narrowly trigger the **existing coordinator for that DeliveryUUID** → existing SAP HTTP → Cloud Integration → CAP path. The synchronous trigger remains default/rollback, and the event trigger stays disabled until a per-order/revision mutual exclusion and durable acknowledgement design are proven. The event is never a second DeliveryIntent or second independent transport state machine.
