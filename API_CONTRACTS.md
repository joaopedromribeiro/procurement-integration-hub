| **Implemented, Phase 4.4.** New response version on accepted order || **Implemented, Phase 4.4.** Explicit rejection command || **Implemented, Phase 4.4.** Explicit acceptance command || **Implemented, Phase 4.4.** Supplier-filtered list and detail || CI → CAP integration service | POST `/rest/integration/v1/Orders` | **Implemented, Phase 4.3.** Mapped portal ingestion contract |# API contracts

Phase 0 proposed version: v1 / design draft. Freeze machine-readable schemas and test actual protocol serialization when implementing the relevant phase.

**Status update:** the buyer-facing RAP OData V4 service is no longer a proposal — it is implemented, published and SAP runtime-verified; see [the buyer UI service](#buyer-ui-service-rap-odata-v4). The CAP integration ingestion endpoint and the CAP supplier-facing service are also implemented and **locally** runtime-verified, in [Phase 4.3](cap-supplier-portal/docs/phase-4-3-integration-ingestion.md) and [Phase 4.4](cap-supplier-portal/docs/phase-4-4-supplier-service.md), with a browser UI over them in [Phase 4.5](cap-supplier-portal/docs/phase-4-5-supplier-ui.md). [Phase 4.6](cap-supplier-portal/docs/phase-4-6-closure.md) reconciled this document against the running code and **found no mismatch** in the ingestion route, the nested DTO, receipt semantics, `deliveryId` idempotency, source-order uniqueness, the supplier routes and bound-action wire shape, supplier identity, scoped-404 isolation, `responseVersion`, `responseId` replay, the pending response, pagination or the error envelope. All of it is local Node.js execution on a developer machine, not a hosted deployment, with mocked supplier identity rather than real authentication, and with no traffic between SAP and CAP in either direction, which remains Phase 5. Every route that crosses the SAP/CAP boundary remains a design draft and does not exist yet.

Phase 1 compatibility note: `ZJP_` table/view names are internal ADT object names; they do not change these external DTOs. At that checkpoint they established no OData service path either; [Phase 3.1](abap-rap/docs/phase-3-1-odata-service-exposure.md) has since created one, recorded below. The persistence/CDS model preserves the planned field sizes and decimal scales. Optional values use ABAP initial values in the tables; the future boundary adapter must map blank response text, initial UUIDs and initial dates to the contract's null/absence convention. Do not serialize date `00000000` as a valid external calendar date. Phase 1 adds no API implementation.

## Boundaries

| Consumer → provider | Interface | Ownership |
| --- | --- | --- |
| Buyer UI → RAP UI service | **Implemented and runtime-verified.** OData V4 entity CRUD, draft operations and bound business actions on `ZJP_UI_PURCHASEORDER`; see [the buyer UI service](#buyer-ui-service-rap-odata-v4) below | Buyer edits permitted fields; RAP enforces rules |
| Authorized technical caller → SAP HTTP Service | POST `/sap/bc/http/sap/ZJP_PO_EVENT_DISPATCH?sap-client=100` | **Phase 9.5B DEV-verified trigger boundary.** Platform authentication plus `ZJP_PIH` / `ZJP_ROLE=DISPATCH`; accepts only `deliveryUUID`, `purchaseOrderUUID`, positive `orderRevision`, and 64-hex `payloadHash`, validates against the committed intent, and delegates the same DeliveryUUID to the existing coordinator. `DELEGATED` is not transport success. This is not an Event Mesh publication or cutover; see the [9.5 evidence](event-mesh/docs/phase-9-5-consumer-trigger.md). |
| Coordinator → CI | POST `/http/pih/v1/order-deliveries` | **This is the ACTIVE production outbound path since the Phase 6.4 cutover**, runtime-verified across Phases 6.1 to 6.4. SAP posts the persisted `PayloadSnapshot` **verbatim** here over destination `ZJP_CI_ORDER_DELIVERY`, and **sends no `Idempotency-Key`** — delivery identity is the body's `deliveryId`. It validates the source delivery contract, echoes `X-Correlation-ID`, **maps the source to the Mapped CAP order contract** below with semantic parity against the Phase 5 ABAP mapper, and **calls the protected CAP `IntegrationService` over OAuth 2.0 client credentials, returning CAP's receipt unchanged**. Downstream answers are passed through as themselves — `201` create, `200` idempotent replay, `409 DELIVERY_PAYLOAD_CONFLICT` — because `Throw Exception on Failure` is OFF; only *technical* failures (DNS, connectivity, TLS, timeout, OAuth, iFlow processing) produce the Exception Subprocess's controlled `502 INTEGRATION_TECHNICAL_ERROR`. **CI does not send `Idempotency-Key`**; delivery identity is the body's `deliveryId`. Real runtime evidence: a `201` create, a `200` replay of the exact persisted snapshot returning the same `portalOrderId`, and a `409 DELIVERY_PAYLOAD_CONFLICT` for the same `deliveryId` with changed content |
| CI → CAP integration service | POST `/rest/integration/v1/Orders` | **Implemented, Phase 4.3.** Mapped portal ingestion contract |
| Supplier UI → CAP supplier service | GET `/rest/supplier/v1/Orders`, GET `/rest/supplier/v1/Orders/{ID}` | **Implemented, Phase 4.4.** Supplier-filtered list and detail |
| Supplier UI → CAP supplier service | POST `/rest/supplier/v1/Orders/{ID}/accept` | **Implemented, Phase 4.4.** Explicit acceptance command |
| Supplier UI → CAP supplier service | POST `/rest/supplier/v1/Orders/{ID}/reject` | **Implemented, Phase 4.4.** Explicit rejection command |
| Supplier UI → CAP supplier service | POST `/rest/supplier/v1/Orders/{ID}/updateEstimatedDeliveryDate` | **Implemented, Phase 4.4.** New response version on accepted order |
| CAP response sender → CI | POST `/http/pih/v1/supplier-responses` | CAP supplier response contract |
| CI → RAP integration service | OData V4 bound `applySupplierResponse` action | Only validated supplier response may change corresponding RAP fields |
| Operations → CAP integration service | GET `/rest/integration/v1/DeliveryReceipts/{deliveryId}` | Resolve an ambiguous delivery, scoped to source client |

CAP supports native [REST and OData adapters](https://cap.cloud.sap/docs/node.js/cds-serve). These REST paths are desired public paths to configure and verify in Phase 4. **`POST /rest/integration/v1/Orders` is now configured and verified**: the documented path was achievable exactly as written, using `@protocol: 'rest'` with `@path: '/rest/integration/v1'` and a service-local `@insertonly` entity, so nothing in the external contract had to move to suit the adapter. Two CAP defaults did have to be overridden to preserve this document's shapes — structured elements are flattened unless `cds.odata.structs` is set, and a `UUID`-typed key is auto-generated when the caller omits it, which silently made the mandatory `deliveryId` optional. **The supplier paths are configured and verified in Phase 4.4**, with bound actions routed as `POST /rest/supplier/v1/Orders/{portalOrderId}/{action}`. Prefer the CAP adapter and handlers; if adapter constraints require a different route, update this document before clients depend on it.

**List pagination, defined and implemented in [Phase 4.5](cap-supplier-portal/docs/phase-4-5-supplier-ui.md).** The supplier order list accepts `?limit=` (default 20, server maximum 100, an oversized value clamped rather than refused) and `?offset=`. These are deliberately not `$top`/`$skip`: assuming OData query syntax on a REST path is what this document ruled out, and neither option had any effect before the parameters were implemented. A non-integer or negative value returns 400 `INVALID_PAGINATION` rather than falling back silently. **The result envelope is a bare JSON array with no total count**, chosen so the Phase 4.4 read contract is not changed for a count the portal has no use for; a client pages until it receives fewer rows than it requested, and a count can be added later as an additive change. Only the order collection is paged — item counts are already bounded by the 100-line ingestion rule, so paging a detail view would risk truncating an order for no gain.

RAP base URL, service version and action namespace come from the actual service binding and `$metadata` — for the buyer service these are now concrete and recorded below. Logical active-instance action form: `POST {RAP_WEB_API_BASE}/PurchaseOrders(<uuid>)/<qualified-action>`. This remains notation rather than a ready-to-run URL; key shape and draft parameters depend on the selected projection, and the qualified action namespace must be read from `$metadata`. **The UI service's draft-specific keys must not be copied into the integration contract**, which is a separate service and remains Phase 5.

RAP UI actions include `submit`, `approve`, `reject`, `cancel` and `removeItem`. `sendToSupplier` is **implemented and SAP runtime-verified** as Phase 5.2f and creates the durable delivery intent without touching the network; Phase 9.5B exposed it through the buyer projection and Fiori metadata for a controlled Create → Submit → Approve → Send to Supplier fixture. That UI action is distinct from the new technical HTTP trigger: the latter never creates an intent. `recordDeliveryResult` remains the non-projected coordinator-only outcome boundary, reached by base EML. `applySupplierResponse` remains exposed only through the restricted integration projection `ZJP_API_PurchaseOrder` on `ZJP_API_SUPPLIERRESPONSE`, not the buyer projection. `retryDelivery` was implemented in Phase 7.6 for explicit UNKNOWN recovery under the same DeliveryUUID; it is not the event trigger. The HTTP Service's `DISPATCH` authority is separate from BUYER, INTEGRATOR, OPERATOR and WORKER. See the [Phase 9.5 evidence](event-mesh/docs/phase-9-5-consumer-trigger.md) for the verified path and limits.

Phase 5 calls CAP directly and uses a small local mapping component; the reverse sender calls RAP directly. Phase 6 switches endpoints to CI without changing business identities or ownership.

## Buyer UI service (RAP, OData V4)

**Runtime-verified in [Phase 3.1](abap-rap/docs/phase-3-1-odata-service-exposure.md).** This is the one endpoint in this document that exists.

| Property | Value |
| --- | --- |
| Service definition | `ZJP_UI_PURCHASEORDER` — [source](abap-rap/service/zjp_ui_purchaseorder.srvd) |
| Service binding | `ZJP_UI_PURCHASEORDER_O4` |
| Binding type | OData V4 – UI |
| Entity set | `PurchaseOrders`, from `ZJP_C_PurchaseOrder` |
| Entity set | `PurchaseOrderItems`, from `ZJP_C_PurchaseOrderItem` |
| Navigation | `_Items`, verified through `$expand` |
| Draft | Exposed; `IsActiveEntity` / `HasActiveEntity` observed |
| Bound business actions | `submit`, `approve`, `reject` (parameter `RejectionReason`), `cancel`, `removeItem` (parameter `PurchaseOrderItemUUID`) |
| Draft actions | `Edit`, `Activate`, `Discard`, `Resume`, `Prepare` |

Service root as published on the current development target:

```text
https://s4h2023.sapdemo.com:44323/sap/opu/odata4/sap/zjp_ui_purchaseorder_o4/srvd/sap/zjp_ui_purchaseorder/0001/?sap-client=100
```

That host, port and client identify one development system, not a stable contract. Treat the **service definition and binding names** as the durable identity and resolve the host per environment; `0001` is the binding's service version. Publishing on this target required transaction `/IWFND/V4_ADMIN` because client 100 is a Customizing client, so ADT's local publish was refused.

**The service adds no rules.** Business behavior is enforced by the Phase 2 handlers and reaches HTTP unchanged: an ineligible `approve` returns 400 with `Only submitted orders can be decided.`, and a content change on a submitted order's draft returns 400 with `Only draft orders can be changed.` `PurchaseOrderNumber` is exposed read-only and is allocated on `submit`, not on `Activate`.

Two limits apply to any client written against this service today. `__OperationControl` advertises bound actions even on orders whose lifecycle would reject them, so a client must handle a 400 rather than trust the advertised availability. And although `OptimisticConcurrency` appears in `$metadata`, no stale-ETag or concurrent-write case has been exercised — see OI-13 in [PROJECT_STATUS.md](PROJECT_STATUS.md). No authorization is enforced; the permissive study stub is unchanged.

## Common rules

- HTTPS outside loopback development. JSON uses UTF-8 and `Content-Type: application/json`.
- Contract field names are case-sensitive. UUIDs use canonical hyphenated text, timestamps UTC RFC 3339, and calendar dates `YYYY-MM-DD`.
- Monetary and quantity fields are decimal strings; no scientific notation. Initial currency support is EUR only. Enforce precision, scale and bounds from the domain model.
- `X-Correlation-ID` identifies a transport attempt. A retry may get a new correlation ID while preserving the business delivery/response ID.
- **The body identity is the idempotency identity.** For ingestion that is `deliveryId`, the key of CAP's `Orders` entity and the value CAP actually deduplicates on; for supplier-response commands it is `responseId`. An `Idempotency-Key` header **is not required and is not sent** by the Phase 6.4 production path or by Cloud Integration; where one is present it must equal the body identity, and mismatches are rejected. RAP action parameters carry identity even if an adapter cannot preserve the custom header.
- Deduplication keys are scoped by authenticated source system, never global caller-controlled strings alone. Unknown schema major versions fail with 400. A breaking change gets a new version; additive changes require compatibility tests.
- Proposed initial bound: 100 items and 256 KiB per request; enforce before expensive processing. Bodies exceeding the byte bound return 413. Exact product limits may impose a lower maximum.
- Retain compact business deduplication records for the lifetime of their associated order in this project. Detailed logs have a separately configurable retention policy. Deleting receipts while retries remain possible would reopen duplicate-processing risk.

## Source order delivery

This is a coordinator-created DTO, not raw RAP OData entity JSON. It extends the user's example with stable identities and organizational context. OData read wrappers and draft fields do not leak across the boundary.

```json
{
  "schemaVersion": "1.0",
  "deliveryId": "0e7df7c7-2427-4700-a7bb-63aa9f1a11af",
  "sourceSystem": "PIH_ABAP_DEV",
  "purchaseOrderId": "82e96537-4ecc-4c34-b2c3-e75486329447",
  "revision": 1,
  "purchaseOrder": "PO000001",
  "supplier": "SUP001",
  "supplierName": "Example Technology Supplier",
  "companyCode": "1000",
  "purchasingOrganization": "1000",
  "purchasingGroup": "001",
  "currency": "EUR",
  "totalAmount": "1500.00",
  "items": [
    {
      "itemId": "77418462-e8d8-4d60-b5fd-98510b5d90b0",
      "item": "10",
      "material": "MAT001",
      "description": "Laptop",
      "quantity": "2.000",
      "unitOfMeasure": "EA",
      "netPrice": "750.0000",
      "totalAmount": "1500.00"
    }
  ]
}
```

## Mapped CAP order

```json
{
  "schemaVersion": "1.0",
  "deliveryId": "0e7df7c7-2427-4700-a7bb-63aa9f1a11af",
  "source": {
    "system": "PIH_ABAP_DEV",
    "orderId": "82e96537-4ecc-4c34-b2c3-e75486329447",
    "orderNumber": "PO000001",
    "revision": 1
  },
  "supplierCode": "SUP001",
  "amount": { "currency": "EUR", "value": "1500.00" },
  "lines": [
    {
      "sourceItemId": "77418462-e8d8-4d60-b5fd-98510b5d90b0",
      "lineNumber": 10,
      "product": { "code": "MAT001", "description": "Laptop" },
      "orderedQuantity": { "value": "2.000", "unit": "PCE" },
      "unitPrice": { "currency": "EUR", "value": "750.0000" },
      "lineAmount": "1500.00"
    }
  ]
}
```

The ingestion DTO is mapped by a custom CAP CREATE handler into persistence entities; it is not an unrestricted deep database insert. Model explicit service-level structured types when implementing the contract. Supplier status is server-owned and defaults to RECEIVED; callers cannot choose ACCEPTED.

| Source field | CAP field | Rule |
| --- | --- | --- |
| purchaseOrderId / purchaseOrder / revision | source.orderId / orderNumber / revision | Preserve source identity separately from CAP UUID |
| sourceSystem | source.system | Validate against authenticated integration client |
| supplier | supplierCode | Resolve active Suppliers record; unknown code is 400 |
| supplierName | Not transmitted | CAP uses its supplier reference, not an untrusted overwrite |
| Company/org/group fields | Not transmitted | Internal SAP context not required by portal |
| currency, totalAmount | amount.currency, amount.value | Nest unchanged decimal value; no repricing |
| items[] | lines[] | Preserve cardinality and source item IDs |
| item | lineNumber | Parse decimal digits; reject invalid/duplicate line number |
| material, description | product.code, product.description | Structured product object |
| quantity, unitOfMeasure | orderedQuantity.value, unit | Decimal string; EA → PCE controlled value mapping |
| netPrice and header currency | unitPrice.value, unitPrice.currency | Propagate currency to each price |
| items[].totalAmount | lines[].lineAmount | Verify arithmetic; do not invent totals during mapping |

Unknown units/currencies, inconsistent totals, no lines, invalid supplier or negative prices fail before persistence. Zero price is valid. CI performs transport/schema checks; RAP and CAP retain their own domain validation even when CI validated the message.

## Receipt and replay

Initial CAP creation targets `201 Created` with a Location header and the following receipt. A matching replay targets `200 OK` with the same business receipt. **Verified locally in Phase 4.3** for the status codes, the receipt shape and the replay semantics: a new delivery returns 201, an exact replay returns 200 carrying the *stored original* receipt with the same `portalOrderId` and `receivedAt`, and a reused `deliveryId` with changed content returns 409 with the committed order unchanged. One deviation is recorded: the handler emits no meaningful Location header, because CAP's automatic `location: Orders/<deliveryId>` points at a route that is insert-only, and the readable receipt resource `GET /rest/integration/v1/DeliveryReceipts/{deliveryId}` belongs to the operations surface and is not implemented. CAP's REST adapter also cannot express a 200 on CREATE without the handler pinning the response status, since its create middleware applies 201 unless the status has already been changed away from the express default of 200.

```json
{
  "deliveryId": "0e7df7c7-2427-4700-a7bb-63aa9f1a11af",
  "sourceOrderId": "82e96537-4ecc-4c34-b2c3-e75486329447",
  "portalOrderId": "cab0d39f-6e2a-4078-b7c5-35832784eab1",
  "status": "RECEIVED",
  "receivedAt": "2026-09-12T15:00:00Z"
}
```

CI returns the receipt with equivalent success semantics. A receipt is sent only after the CAP transaction commits. Same delivery key + same normalized payload returns the original receipt. Same key + different payload returns 409. A different delivery key for an already ingested source order/revision returns 409 with a safe reconciliation reference. Parallel duplicates must be resolved through database uniqueness and rereading the committed receipt.

Normalize known fields, decimal representation and object member ordering before hashing. Stable source identities and immutable snapshots remain authoritative. Raw JSON byte order alone is not a meaningful equality check.

## Supplier commands and callback

Supplier `accept` input contains a client-generated stable responseId and optional estimatedDeliveryDate. `reject` contains responseId and required reason. `updateEstimatedDeliveryDate` contains a new responseId and required estimatedDeliveryDate. Use a version/ETag precondition against the order for a new command; replay detection must recognize an already successful identical command even if its original version is now stale. CAP assigns the next responseVersion atomically and enforces supplier ownership.

**Implemented and locally verified in Phase 4.4**, with the details this section left open now settled by execution. The precondition is the order's `responseVersion` carried as an `expectedResponseVersion` parameter, not an HTTP ETag, so the same value can travel to SAP in the response payload. A stale precondition is **409**, matching "new IDs with stale/conflicting versions return 409"; 412 was considered and not used. An order belonging to another supplier is a scoped **404** with no fields disclosed, the "scoped not-found" option of the design acceptance cases, chosen over 403 because 403 confirms the row exists. Bound actions are routed by CAP's REST adapter as `POST /rest/supplier/v1/Orders/{portalOrderId}/{action}` with the parameters as a flat JSON body — exactly the paths listed above. Supplier identity is read from the authenticated user's attributes and is mocked locally; real identity is Phase 8.

On success, return 200 with the committed portal order/decision and `responseDeliveryStatus: PENDING` if SAP has not acknowledged it. UI acceptance does not claim SAP has been updated. **Phase 4.4 returns exactly this**: `portalOrderId`, `externalOrderNumber`, `status`, `responseVersion`, `estimatedDeliveryDate`, `rejectionReason`, `respondedAt` and `responseDeliveryStatus`, which is `PENDING` at the moment of the decision because delivery happens after commit and never inside the decision transaction. The decision and its pending response commit in one transaction, verified by forcing the second write to fail and observing the first roll back. The Phase 6.5e sender then drains the committed row and submits this immutable DTO:

```json
{
  "schemaVersion": "1.0",
  "responseId": "7f135926-34af-4eb2-a8b3-1b851303afc9",
  "sourceSystem": "PIH_ABAP_DEV",
  "sourceOrderId": "82e96537-4ecc-4c34-b2c3-e75486329447",
  "sourceRevision": 1,
  "deliveryId": "0e7df7c7-2427-4700-a7bb-63aa9f1a11af",
  "portalOrderId": "cab0d39f-6e2a-4078-b7c5-35832784eab1",
  "supplierCode": "SUP001",
  "responseVersion": 1,
  "decision": "ACCEPTED",
  "estimatedDeliveryDate": "2026-09-30",
  "reason": null,
  "respondedAt": "2026-09-12T16:30:00Z"
}
```

**Phase 6.5a has frozen this mapping, and one member of the list moved.** CI maps the payload to the parameters of the bound action `applySupplierResponse`, whose parameter entity **`ZJP_A_ApplySupplierResponse`** is **created and runtime-verified**: `ResponseUUID`, `OrderRevision`, `DeliveryUUID`, `PortalOrderUUID`, `Supplier`, `ResponseVersion`, `SupplierResponse`, `EstimatedDeliveryDate`, `Reason`, `RespondedAt`. **`PurchaseOrderUUID` is not a parameter**: the action is bound, so RAP carries the key in `%tky`, and passing it again would create a second copy that could disagree with the instance being acted on. **There is no correlation parameter** — `X-Correlation-ID` remains transport metadata, exactly as on the outbound leg, and the header's `LastCorrelationId` belongs to the outbound attempt. `RespondedAt` is frozen as `abp_lastchange_tstmpl`, persisted on the header as `SupplierRespondedAt`, and carried on the wire as RFC 3339 at second precision — the precision the verified SAP value keeps, so an idempotent replay is byte-identical to the original. The full design, including guards, lifecycle and version rules, is in the [Phase 6 guide](integration-suite/docs/phase-6-cloud-integration.md). For REJECTED, a reason is mandatory and estimatedDeliveryDate is null. A date update keeps decision ACCEPTED and increments the version.

The RAP action derives Status from the decision; no external caller supplies Status directly. Validate identity, dispatched intent, supplier, revision and version, then update the BO and deduplication receipt atomically. **Frozen in 6.5a:** an `ACCEPTED` response leaves `Status` at **`SENT`** and sets `SupplierResponse = 'ACCEPTED'` — **no `CONFIRMED` status is introduced**, because `SENT` already represents the successful outbound commercial state and `SupplierResponse` is the field reserved for the supplier's answer. A `REJECTED` response is a terminal commercial outcome and does move `Status` to **`REJECTED`**, with `RejectionOrigin = 'SUPPLIER'` and `RejectionReason` from the payload, which is what distinguishes it from a buyer rejection; **the buyer's `reject` action is not reused or reinterpreted**. A later `ACCEPTED` with a higher `responseVersion` is CAP's `updateEstimatedDeliveryDate` path: it replaces `EstimatedDeliveryDate` only, keeps `Status = SENT` and `SupplierResponse = ACCEPTED`, and **must not create a second commercial acceptance event**. Because `estimated_delivery_date` is `dats not null` while the wire field is optional, **absent maps to the initial DATS value `00000000`**. `PurchaseOrderUUID` locates the order; `DeliveryUUID`, `PortalOrderUUID`, `Supplier` and `OrderRevision` are **guards, not lookup keys**, and `PortalOrderUUID` is validated against the **delivery intent**, since it is persisted on `ZJP_PO_DLV` and not on the header. Callback success targets 200 with responseId and outcome APPLIED/ALREADY_APPLIED; OData wraps results according to generated metadata. CI maps that result to `{ "responseId": "…", "outcome": "APPLIED" }` for CAP.

Same response ID + different content is 409. Replayed matching IDs return success. New IDs with stale/conflicting versions return 409 and require reconciliation, never overwrite newer state. A newer accepted/date response contains the complete current supplier response, so version gaps can be applied after validating the allowed state; timestamps alone are not ordering keys. Retain prior processed IDs to recognize old duplicates.

## The CAP response sender

**Phase 6.5e implements it. Source and local tests only — it has not yet run against the deployed environment.**

Delivery happens **after** the decision commits and never inside it. The supplier action writes the order and its `SupplierResponseDeliveries` row in one transaction; an explicit flush command then drains the committed rows, which is the shape ARCHITECTURE.md fixed: *"A CAP development command can similarly flush a committed response. Automatic scheduling is a later enhancement."* It is not an HTTP endpoint — an administrative trigger for an outbox drain would need authorizing and is a far larger surface than a command run against a bound application.

```text
npm run flush-responses -- --dry-run          # build and print payloads, send nothing
npm run flush-responses -- --limit 1          # attempt one row
```

**Configuration is environment-only. This repository holds the variable NAMES and never a value.**

| Variable | What it is |
| --- | --- |
| `PIH_CI_SUPPLIER_RESPONSE_URL` | the `PIH_SupplierResponse_v1` endpoint; must be https |
| `PIH_CI_CLIENT_ID` | Process Integration Runtime client identity |
| `PIH_CI_CLIENT_SECRET` | its secret |
| `PIH_CI_TIMEOUT_MS` | optional bounded ceiling, default 30000 |

A missing variable is a refusal, never a default: falling back to a built-in endpoint or to an unauthenticated call would turn a misconfigured environment into a silent behaviour change against a real system. Authentication is **HTTP Basic** against the CI HTTPS sender, which is the development-phase mechanism that was runtime-proven; a client-credentials token flow is later hardening.

**Headers.** `Content-Type: application/json`, `Accept: application/json`, a fresh `X-Correlation-ID` per attempt, `Idempotency-Key: <responseId>` and `Authorization: Basic`. The `Idempotency-Key` is read **from the payload object itself**, not passed separately, so it cannot drift from the body — which is how the rule above (*"where one is present it must equal the body identity"*) is made unrepresentable to violate rather than merely checked. **The body`s `responseId` remains the authoritative identity**: an adapter that drops custom headers changes nothing about how SAP deduplicates, which is why the header is belt-and-braces rather than the mechanism.

**Delivery state**, following the error policy below rather than a second one:

**The table below is accurate only because of a Phase 6.5f fix.** `PIH_SupplierResponse_v1` originally ran with `Throw Exception on Failure` **ON**, so a deterministic RAP refusal reached CAP as a generic `5xx` and classified `UNKNOWN` instead of `FAILED` — proven in 6.5f when a real conflicting replay produced `SAP 400 SABP_BEHV/100` and CI returned `500`. The setting is now **OFF on the action receiver only** (`SAP_RAP_Action` / `MessageFlow_719`); the CSRF-fetch receiver keeps it ON, because a token failure has no business answer to pass through. The same conflict retested end to end as `SAP 400` → `CI 400` → `FAILED`, with SAP state unchanged.

| Outcome | `state` |
| --- | --- |
| any 2xx, including the verified 204 | `DELIVERED` |
| 400, 401, 403, 404, 409, 412, 413 | `FAILED` |
| 429, 502, 503 | `PENDING`, eligible again |
| 500, 504, or no answer at all | `UNKNOWN` |

Only `PENDING` rows are drained. A `DELIVERED` row is never resent, and **`FAILED` and `UNKNOWN` are never automatically retried** — no code path returns them to `PENDING`. An `UNKNOWN` row means the response may already have been applied at SAP, and the sender deliberately does not guess.

**An operator resolves an `UNKNOWN` row explicitly**, with `reconcile-supplier-response --response-id <uuid>`, which **replays the same durable response under the same `responseId`** through the same Integration Suite endpoint with a fresh `X-Correlation-ID`. It does not read SAP: RAP idempotency answers the question instead, so a response that already landed is a no-op and one that never landed is applied. The result is classified by the table above, `attempts` increments once, and a still-ambiguous answer simply leaves the row `UNKNOWN`. `DELIVERED`, `FAILED` and `PENDING` rows are refused, `Orders` is never written, and there is no automatic loop. `lastCorrelationId` locates each attempt in the Cloud Integration message log. **A retry never manufactures a new `responseId`** — the crash window between SAP applying a response and CAP recording it is survived by replaying the same identity, which RAP answers `ALREADY_APPLIED`. Responses for one order are sent in version order and later ones are held back while an earlier one has not landed. **The sender never writes `Orders`**: a transport outcome must not be able to edit a committed supplier decision.

**Single-runner.** There is no claim or lease. Two concurrent flushes would both send; the receiver is idempotent so nothing is misapplied, but the attempt bookkeeping would race. Run one at a time until scheduling exists.

## Error policy

REST-facing application errors use the following proposed safe envelope. Native RAP OData errors keep the OData error format; CI maps them at the REST boundary. Gateways and identity providers may reject requests before our handler, so clients must tolerate empty/non-JSON error bodies.

```json
{
  "error": {
    "code": "SUPPLIER_UNAVAILABLE",
    "message": "Supplier portal did not respond before the delivery deadline.",
    "correlationId": "ef3755ac-de42-42e8-b957-45ed6208e7b6",
    "retryable": true
  }
}
```

| Condition | Handling | Retry and SAP effect |
| --- | --- | --- |
| 400 / invalid payload | Return actionable field/code detail, exclude confidential values | No automatic retry; correct source/mapping. Failed outbound delivery may set ERROR |
| 401 | Missing, invalid or expired authentication | Refresh a token once if appropriate; no credential-error loop. Record delivery failure |
| 403 | Authenticated client lacks permission | No automatic retry; correct role or supplier scope |
| 404 | Requested order/receipt not found, or incorrect endpoint | Reconcile identity/routing; no blind retry. Unknown inbound order cannot be set to ERROR |
| 409 | Identity reuse, illegal transition or version conflict | No blind retry; matching duplicates should have returned success |
| 412 | Stale ETag/precondition | Reread and reassess; never blindly overwrite newer state |
| 413 | Request exceeds limit | Reduce/correct request; no unchanged replay |
| 429 | Throttling | Honor Retry-After within a bounded retry budget |
| 500 | Unexpected receiver failure | Reconcile ambiguous outcome; bounded retry only for transient causes using the same ID |
| 502 / 503 | Upstream unavailable or transient service failure | Bounded retry; respect Retry-After where supplied |
| Timeout / 504 | Receiver may already have committed | Integration UNKNOWN and RAP ERROR for outbound; query receipt or replay the same ID |
| Supplier business rejection | Successful application exchange | RAP REJECTED, origin SUPPLIER; never an HTTP error |

An upstream 401 caused by CI's receiver credentials is not the same as the original caller being unauthenticated. Normalize that to a safe upstream failure (for example 502 with code UPSTREAM_AUTH_FAILED and retryable false), preserve the original status in restricted diagnostics, and do not instruct the caller to refresh its unrelated token.

**A no-answer outcome is not one condition, and Phase 7.1 splits it.** The table above classifies answered responses; an exchange that produces no HTTP answer falls into one of two categories with opposite handling. A **pre-send / no-delivery failure** — DNS resolution failure, a connection refused before transmission, or an explicitly recognised TLS certificate-verification failure — means the receiver **could not** have committed: it is deterministic, retry-eligible once the cause is fixed, and its durable state is `PENDING`, never `UNKNOWN`. An **ambiguous post-send failure** — a client timeout after dispatch, a connection lost after transmission, or any failure where a receiver commit cannot be ruled out — means the receiver **may** have committed: it is `UNKNOWN`, is never automatically replayed, and is resolved only by explicit operator reconciliation under the same business identity. Phase 7.4b implements that distinction locally on the CAP leg with optional `NOT_SENT` / `MAY_APPLY` certainty; missing or unrecognised certainty stays conservative `UNKNOWN`. SAP parity remains Phase 7.4c, and the Cloud Integration CSRF failure still requires the Phase 7.4d exception-path decision. See the [Phase 7 guide](docs/phase-7-operational-resilience.md#failure-categories).

The frozen retry policy for transient delivery failures is **four total transport attempts**: the initial attempt and three retry opportunities. After transient attempts one, two and three, the row receives a durable eligibility time based on respectively **5 s, 30 s and 120 s plus positive-only uniform jitter from 0% through 20% of that base**. Jitter never shortens the base. It is selected once when the outcome is persisted, not recalculated by each runner. At four attempts the row remains `PENDING`, is excluded indefinitely and is reported as retry-exhausted; no fifth state is added. These are project policy choices, not SAP defaults. **Phase 7 has no scheduler, so this budget is retry *eligibility*:** a runner invocation performs the attempt only if the persisted due time has arrived. Invocations before it skip the row.

The retry cycle starts with the first transient result handled under Phase 7.4 and lasts at most **15 minutes**. `retryWindowStartedAt` freezes that anchor and `nextAttemptAt` freezes the selected due time. A due time outside the window is retained for diagnosis but is never automatically eligible; the block is derived from the two timestamps and no state or boolean is added. Null `nextAttemptAt` means only that no deferred eligibility time exists, so a legacy `PENDING` row below the four-attempt budget remains immediately eligible. On the CAP leg, Phase 7.4b extracts only the raw `Retry-After` header when its complete value is at most 128 characters; overlong values are discarded, never truncated. The policy parses either nonnegative integer delta-seconds from the response-completion time or canonical IMF-fixdate verified by exact UTC round-trip. For answered transient `429`, `502` or `503`, the selected due is `max(normal jittered due, Retry-After due)`; malformed, negative, empty or overflowing values are ignored. Unanswered results and other statuses never consume the header.

Proposed request budgets: CAP receiver 15 s, CI processing 25 s, coordinator request 35 s. Confirm platform ceilings and tune under failure tests. Give inner calls shorter deadlines than their callers. A timeout never proves non-delivery.

**These budgets are proposals and Phase 7.1 confirmed that none of them is implemented as written.** The CAP receiver timeout does not exist; Cloud Integration's `transactionTimeout` is 30 s rather than 25 s on both deployed iFlows, while every receiver call within them is allowed a `httpRequestTimeout` of 60 000 ms that no budget records; the coordinator leaves `i_timeout` at its API default by an explicit decision in `zjp_cl_outbound_transport`, so the 35 s figure is aspirational; and the CAP sender's real 30 s `DEFAULT_TIMEOUT_MS` appears in no table above. The consequence is not cosmetic: the sender abandons an exchange at 30 s while the inner Cloud Integration call it triggered may legitimately continue for 60 s, which **inverts the rule stated immediately above and manufactures ambiguous outcomes by configuration**. The six exact inconsistencies are enumerated as TI-1 to TI-6 in the [Phase 7 guide](docs/phase-7-operational-resilience.md#timeout-reconciliation) and are reconciled in Phase 7.4; no constant has been changed yet.

On exhausted outbound failures, preserve ERROR, the last safe message and the immutable intent. A trusted recovery operation may retry the same approved intent. If a valid callback or receipt subsequently arrives, reconcile without downgrading a terminal business result. Inbound callback failure remains pending/failed in CAP; do not change a valid SAP business status just to represent an invalid incoming message.

## Design acceptance cases

| Case | Expected result once implemented |
| --- | --- |
| Two laptops at EUR 750 each | One CAP order, PCE unit, EUR 1500.00, receipt → SAP SENT |
| Same delivery sent twice concurrently | One order; both callers can resolve the same receipt |
| Same delivery ID with a changed quantity | 409; original order unchanged |
| Timeout after CAP commit | SAP ERROR/UNKNOWN, then reconciliation → SENT without duplicate |
| Acceptance arrives before delivery result is recorded | Matching dispatched intent → CONFIRMED; later receipt cannot downgrade |
| CAP decision commits but callback fails | Portal ACCEPTED, return delivery pending/failed, SAP still SENT until retry succeeds |
| Supplier B requests Supplier A's order | Access denied or scoped not-found response; no fields disclosed |
| Old delivery-date response arrives after newer one | No date regression; duplicate success or explicit conflict |

These cases define later tests. Phase 0 validates document consistency only.

## Phase 2.6 internal EML contract — runtime-verified

The root-bound technical removeItem operation accepts PurchaseOrderItemUUID through abstract parameter ZJP_A_RemoveItem and requires the complete root %tky, including %is_draft, as instance identity. It returns no action result; callers read the root/composition afterward. The handler verifies membership in that exact root/draft instance before deleting, then updates the total from surviving buffered items. Call sequentially for multiple removals from one root.

Standard child DELETE is internal to the behavior implementation; external EML uses removeItem. Root DELETE remains the whole-composition cleanup operation. Callers must inspect FAILED/REPORTED and roll back failed requests before committing. Missing/foreign items are rejected without mutation; this operation is not an idempotent deletion receipt API.

This Phase 2.6 technical BO contract is SAP runtime-verified for active, saved-draft and buffer-only draft instances, including ownership rejection without side effects. It defines no OData URL, external procurement message, UI projection or Phase 2.7 business action. Future buyer UI exposure must preserve this deletion boundary; integration clients do not edit technical drafts. See the [implementation and tests](abap-rap/docs/phase-2-6-technical-draft.md).
