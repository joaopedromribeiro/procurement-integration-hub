# Phase 9.5 — SAP event-trigger adapter and HTTP boundary

Status: **9.5A SAP TRIGGER ADAPTER LOCALLY VERIFIED; 9.5B HTTP TRIGGER BOUNDARY VERIFIED END-TO-END IN THE INSPECTED DEV ENVIRONMENT**, on owner-supplied A4H, CPI, and CAP/HANA evidence. An HTTP Service exists; no Event Mesh consumer, PIH-owned broker, or real event publication is verified. Phase 7 coordinator behavior and its callers remain unchanged. The owner subsequently supplied the full ACTIVE ADT [HTTP handler](../../abap-rap/classes/zcl_jp_po_event_dispatch.clas.abap) and [Test Classes include](../../abap-rap/classes/zcl_jp_po_event_dispatch.clas.testclasses.abap) for repository mirroring.

## Discovery and responsibility

`ZJP_CL_DISPATCH_COORDINATOR->run_once( delivery_uuid )` is the authoritative single-delivery dispatch operation. It owns the committed claim/lease, immutable snapshot POST, attempt/correlation/retry/UNKNOWN classification, and result commit. `sendToSupplier` creates or reuses the intent but performs no HTTP. `retryDelivery` prepares only the current UNKNOWN intent for explicit recovery; it rejects a first-delivery PENDING intent. Neither action is the event-consumer trigger. No current service projection exposes a dispatch operation. The active binding's generated external type is `zjp.PurchaseOrder.DeliveryRequested.v*` (version `0001 / 0 / 0`); its actual published envelope is still unverified.

The new ordinary application service `ZJP_CL_EVENT_TRIGGER` accepts `DeliveryUUID`, `PurchaseOrderUUID`, `OrderRevision`, and `PayloadHash`. It reads committed `ZJP_PO_DLV` identity and `ZJP_PO_H-ORDER_REVISION` through `ZJP_IF_EVENT_INTENT_READER`, then invokes `ZJP_IF_EVENT_DISPATCHER->run_once` **only with the supplied DeliveryUUID**. The production dispatcher delegates directly to the unchanged coordinator. The external event/publication ID is neither input nor a deduplication key.

| Validation | Adapter decision / delegation |
| --- | --- |
| DeliveryUUID absent from committed DeliveryIntent table | `UNKNOWN_DELIVERY` |
| UUID, PurchaseOrderUUID, OrderRevision, or PayloadHash differs from the persisted intent | `IDENTITY_CONFLICT` |
| Owning PurchaseOrder is absent | `ORDER_NOT_FOUND` |
| Persisted current PurchaseOrder revision is greater than the intent/event revision | `STALE_REVISION` |
| Persisted current revision is lower than the matching intent/event revision | `IDENTITY_CONFLICT` (inconsistent state) |
| All identity and current-revision checks pass | `DELEGATED`; return the coordinator's own `ty_outcome` |

The committed current revision is available in `ZJP_PO_H-ORDER_REVISION` and exposed by `ZJP_I_PurchaseOrder`. The lookup is read-only; it does not reconstruct a snapshot or inspect claimability. Two SELECTs are not an atomic lock on concurrent PurchaseOrder changes. The existing coordinator and `recordDeliveryResult` guards remain authoritative; the race and eventual broker-settlement implications require target runtime proof before cutover.

`DELEGATED` means the adapter invoked its dispatcher interface, **not** that an HTTP request was sent or a portal delivery succeeded. In production that interface delegates to the coordinator, whose `ty_outcome` reports claim/skip, dispatch, answer, final state, recording, and correlation. Duplicate invocation may delegate twice for the *same* DeliveryUUID; the coordinator's persisted claim/lease/state policy decides whether the second call sends or skips. The adapter has no publication registry or second delivery state machine.

## Test seam and transaction boundary

`ZJP_IF_EVENT_INTENT_READER` isolates the two committed reads; `ZJP_CL_EVENT_INTENT_READER` supplies production SELECTs. `ZJP_IF_EVENT_DISPATCHER` isolates a single coordinator invocation; `ZJP_CL_EVENT_DISPATCHER` constructs the unchanged coordinator with an injected transport and lease duration. ABAP Unit substitutes both interfaces, so no real HANA read, HTTP call, EML mutation, or coordinator commit occurs in the tests.

The owner compiled and activated `ZJP_IF_EVENT_INTENT_READER`, `ZJP_IF_EVENT_DISPATCHER`, `ZJP_CL_EVENT_INTENT_READER`, `ZJP_CL_EVENT_DISPATCHER`, `ZJP_CL_EVENT_TRIGGER`, and the trigger's Test Classes include in A4H. The ABAP Unit run finished **8 methods, 0 failures, 0 errors**:

| Green test | Proven adapter behavior |
| --- | --- |
| `valid_identity` | Delegates exactly once with the matching DeliveryUUID through the dispatcher double. |
| `duplicate_identity` | Repeated invocation delegates the same DeliveryUUID/business operation; the adapter creates no second intent. |
| `unknown_delivery` | Unknown DeliveryUUID does not delegate. |
| `missing_order` | Missing owning PurchaseOrder does not delegate. |
| `stale_revision` | Older revision does not delegate. |
| `wrong_order` | PurchaseOrderUUID mismatch does not delegate. |
| `wrong_revision` | OrderRevision mismatch does not delegate. |
| `wrong_hash` | PayloadHash mismatch does not delegate. |

These network-free tests prove validation and dispatcher-interface invocation only. Because the dispatcher is a test double, they do **not** prove an actual `ZJP_CL_DISPATCH_COORDINATOR->run_once` invocation, HTTP delivery, or end-to-end outcome.

The trigger is deliberately **not a RAP behavior action**. `run_once` commits its own claim and result transactions; invoking it inside a RAP interaction would cross that boundary. At the 9.5A checkpoint no external endpoint existed. The separate 9.5B HTTP Service now authenticates and authorizes the narrow trigger; the existing `WORKER` check on `recordDeliveryResult` is not reused as endpoint authority.

## 9.5B — authenticated HTTP Service

The owner created and locally published HTTP Service `ZJP_PO_EVENT_DISPATCH`, generated handler `ZCL_JP_PO_EVENT_DISPATCH`, at `/sap/bc/http/sap/ZJP_PO_EVENT_DISPATCH?sap-client=100` in A4H. Platform authentication precedes an explicit `AUTHORITY-CHECK` of `ZJP_PIH` / `ZJP_ROLE = DISPATCH`; authorization is checked before business execution. `DISPATCH` is a dedicated character-like authorization value (the target rejected `STRING` for `FIELD`), not `INTEGRATOR`, `OPERATOR`, or `WORKER`. The owner added `DISPATCH` / “Event Dispatch” to domain `ZJP_ROLE_DM`, configured PFCG role `ZJP_PIH_DISPATCH`, assigned it to `ZHUB.USER`, completed user comparison, and saw `DISPATCH` in SU56. These are tenant-side facts, not repository-managed credentials or role assignments.

The HTTP contract is POST with `application/json` and exactly the four business identity members `deliveryUUID`, `purchaseOrderUUID`, positive `orderRevision`, and `payloadHash` (64 hexadecimal characters). The handler checks method, authorization, content type, nonempty/parseable JSON, required fields, canonical UUIDs with safe round-trip conversion, revision, and hash before invoking `ZJP_CL_EVENT_TRIGGER`. It does **not** call the coordinator directly. Production construction uses `ZJP_CL_EVENT_INTENT_READER`, `ZJP_CL_OUTBOUND_TRANSPORT` with destination name `ZJP_CI_ORDER_DELIVERY`, `ZJP_CL_EVENT_DISPATCHER`, and `ZJP_CL_EVENT_TRIGGER`; the configured lease duration was **300 seconds for this DEV/runtime test**, not a universal default. Trigger decisions are `DELEGATED`, `UNKNOWN_DELIVERY`, `ORDER_NOT_FOUND`, `IDENTITY_CONFLICT`, and `STALE_REVISION`. `DELEGATED` says the validated request reached the dispatcher; the nested coordinator outcome, not that word, reports claim/transport/result facts. No publication ID enters this SAP contract.

**Target-specific XCO parsing finding.** With `xco_cp_json=>transformation->camel_case_to_underscore`, `deliveryUUID` becomes `delivery_u_u_i_d` and `purchaseOrderUUID` becomes `purchase_order_u_u_i_d`. The handler's XCO wire structure had to use those generated names, then map to the semantic trigger fields `delivery_uuid` and `purchase_order_uuid`. The initial parsing failure was resolved in ACTIVE ADT; ordinary camel-case intuition would have produced incorrect field names here.

The handler's private `process_request( ... )` has a network-free test seam. Its Test Classes use `CLASS ltc_po_event_dispatch DEFINITION DEFERRED` and `LOCAL FRIENDS ltc_po_event_dispatch` on the global class definition, with `ltd_http_intent_reader` and `ltd_http_dispatcher` doubles. `LOCAL FRIENDS` was not added to the global class header. A4H ABAP Unit passed **13/13, zero failures/errors**: `empty_body`, `identity_conflict`, `invalid_content_type`, `invalid_hash`, `invalid_json`, `invalid_uuid`, `order_not_found`, `stale_revision`, `trigger_unavailable`, `unauthorized`, `unknown_delivery`, `valid_delegated`, and `wrong_method`. The valid case parsed the exact external JSON, checked all semantic fields and the same DeliveryUUID, returned HTTP 200/`DELEGATED`, and called the dispatcher once; its configured coordinator outcome was `DELIVERED`. The unauthorized unit case supplied `authorized = false` to `process_request`; by itself it does **not** exercise the real `AUTHORITY-CHECK` in `handle_request`.

## 9.5B — real boundary and delivery evidence

| A4H/runtime observation | What it proves, and its limit |
| --- | --- |
| GET returned `METHOD_NOT_ALLOWED` / “Only POST is allowed.” | Service and `HANDLE_REQUEST` were reached; no dispatch. |
| Malformed POST `{broken-json` returned `INVALID_REQUEST` / “The request body is not valid JSON.” | POST passed the actual `DISPATCH` authorization check in that runtime user context and reached parsing; no dispatch. |
| Valid POST for nonexistent `00000000-0000-0000-0000-000000000000` returned `UNKNOWN_DELIVERY`. | Real parser, reader, and trigger; no dispatch for an unknown intent. |
| Existing intent with deliberately wrong PurchaseOrderUUID returned `IDENTITY_CONFLICT`. | Identity guard prevented dispatch. |
| Correct identity of an already `DELIVERED` intent returned `DELEGATED`, with `claimed=false`, `dispatched=false`, `recorded=false`, `skipReason=STATE_NOT_CLAIMABLE`. | Real dispatcher/coordinator wiring, but no transport on that probe. |

Three failed transport fixtures remain evidence, **not snapshots to edit or retry**. First, a Fiori-created item with no item number produced an empty `<item>`; CPI's `/xsd/pih-order-delivery-source-v1.xsd` rejected it against `[0-9]+` (`XmlValidationException`, `CallActivity_238`, MPL `OverallStatus=COMPLETED` with `IntermediateError=true`). SAP recorded `HTTP_502` / `INTEGRATION_TECHNICAL_ERROR`, one attempt, cleared the lease, and returned the intent to retryable `PENDING`. Second, after item number `10` was corrected, the immutable snapshot still had blank `material`, description, and unit. CAP returned “Line 10: product.code is required.” That answered deterministic rejection was non-retryable and SAP persisted `FAILED`. Third, after material was populated, CAP rejected `SUP033` as not an active portal supplier; SAP again persisted non-retryable `FAILED`. These runs separate CPI structure validation, CAP product-code validation, and CAP live supplier validation without rewriting historical evidence. The [source XSD](../../integration-suite/mappings/pih-order-delivery-source-v1.xsd), [CAP ingestion rules](../../cap-supplier-portal/srv/lib/ingestion.ts), and [local contract fixture](../../integration-suite/payloads/order-delivery-source-valid-v1.json) explain the boundaries. Local `SUP001`/`SUP002` seed data do not prove deployed supplier activity; no CAP product-master lookup exists on ingestion.

The controlled successful PO was created through Fiori as `ZHUB.USER` after the owner assigned existing `ZJP_PIH_BUYER` and completed user comparison. The ACTIVE `ZJP_C_PurchaseOrder` projection now exposes `use action sendToSupplier;`, and its metadata extension presents `Submit`, `Approve`, and `Send to Supplier`, supporting Create → Submit → Approve → Send to Supplier. The final fixture used active `RTTEST001`, company code `1000`, `EUR`, item `10`, `MAT001` / “Test Material”, quantity `2 EA`, net price `750`, and total `1500.00`; CPI mapped `EA` to `PCE`. This is evidence for this fixture, **not** a claim that all supplier codes are active.

The final immutable intent was `DeliveryUUID 37FC3FA8-EB2D-1FD1-AEAB-78ABE1985261`, `PurchaseOrderUUID 37FC3FA8-EB2D-1FD1-AEAB-6B918C2CD221`, revision `1`, and `PayloadHash EBE6F80513173455C5D8320F8C462FE3CD47474A15B7440C66E2B54B5DEC8329`. POST to the HTTP Service returned HTTP **200**, `DELEGATED`, and coordinator `claimed=true`, `dispatched=true`, `recorded=true`, `finalState=DELIVERED`. SAP then showed `DISPATCH_STATE=DELIVERED`, `ATTEMPT_COUNT=1`, and empty lease owner/expiry. The `PIH_OrderDelivery_v1` MPL ran **2026-09-26 03:40:19.360–03:40:19.640 UTC**, `OverallStatus=COMPLETED`, `IntermediateError=false`, MessageGuid `AGq3PqOv18u69kNSvDFOw67qCx-z`. A succeeding read-only CAP task `pih95b-cap-proof2` found portal order `82745532-fbd1-4c6f-8024-1c1385bbfda4` in `pih.portal.Orders`, tied to that exact delivery and source order, `PO00000281`, `RTTEST001` supplier ID `a1187936-465d-4f12-8ff4-427b44261f71`, `EUR 1500.00`, `STATUS=RECEIVED`, `RESPONSEVERSION=0`. The first read-only task failed because Windows CMD mangled JavaScript arrow-function characters; it did not mutate data.

Thus the **Phase 9.5B positive runtime path was verified end-to-end in the inspected DEV environment**: SAP PO → immutable intent → authorized HTTP trigger → existing coordinator → outbound HTTP → CPI → CAP ingestion → HANA receipt/order → SAP `DELIVERED`. This is not exactly-once delivery, Event Mesh runtime, AMQP ACK/redelivery, production cutover, or readiness across environments. The reader's two committed-state reads still do not lock against a concurrent PO revision change. The temporary read-only `ZJP_CL_PAYLOAD_CHECK` diagnostic is not a production Phase 9.5 object or repository mirror.

## Remaining repository and environment gates

The full ACTIVE ADT source supplied for `ZCL_JP_PO_EVENT_DISPATCH` and its Test Classes include is mirrored without redesign. The owner also supplied the ACTIVE [projection BDEF](../../abap-rap/behavior/zjp_c_purchaseorder.bdef) and [metadata extension](../../abap-rap/cds/zjp_c_purchaseorder.ddlx), which are mirrored with the `sendToSupplier` projection and three Fiori actions; the projection CDS is unchanged. The HTTP Service is a published SAP repository object, but this repository has no established file format/mirror for its service definition; record its name and path here without inventing one. Real Event Mesh publication, queue consumption, ACK/redelivery, broker availability, and the external CloudEvents envelope remain environment-blocked/unobserved. The SAP read-boundary concurrency question remains open before any event-driven cutover. One reviewed commit is intended for all of Phase 9.5, not separate 9.5A and 9.5B commits.
