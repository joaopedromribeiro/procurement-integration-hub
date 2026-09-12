# API contracts

Phase 0 proposed version: v1 / design draft. None of these endpoints exists yet. Freeze machine-readable schemas and test actual protocol serialization when implementing the relevant phase.

Phase 1 compatibility note: `ZJP_` table/view names are internal ADT object names; they do not change these external DTOs or establish an OData service path. The persistence/CDS model preserves the planned field sizes and decimal scales. Optional values use ABAP initial values in the tables; the future boundary adapter must map blank response text, initial UUIDs and initial dates to the contract's null/absence convention. Do not serialize date `00000000` as a valid external calendar date. Phase 1 adds no API implementation.

## Boundaries

| Consumer → provider | Proposed interface | Ownership |
| --- | --- | --- |
| Buyer UI → RAP UI service | OData V4 entity CRUD, draft operations, business actions | Buyer edits permitted fields; RAP enforces rules |
| Coordinator → CI | POST `/http/pih/v1/order-deliveries` | Source delivery contract |
| CI → CAP integration service | POST `/rest/integration/v1/Orders` | Mapped portal ingestion contract |
| Supplier UI → CAP supplier service | GET `/rest/supplier/v1/Orders`, GET `/rest/supplier/v1/Orders/{ID}` | Supplier-filtered list and detail |
| Supplier UI → CAP supplier service | POST `/rest/supplier/v1/Orders/{ID}/accept` | Explicit acceptance command |
| Supplier UI → CAP supplier service | POST `/rest/supplier/v1/Orders/{ID}/reject` | Explicit rejection command |
| Supplier UI → CAP supplier service | POST `/rest/supplier/v1/Orders/{ID}/updateEstimatedDeliveryDate` | New response version on accepted order |
| CAP response sender → CI | POST `/http/pih/v1/supplier-responses` | CAP supplier response contract |
| CI → RAP integration service | OData V4 bound `applySupplierResponse` action | Only validated supplier response may change corresponding RAP fields |
| Operations → CAP integration service | GET `/rest/integration/v1/DeliveryReceipts/{deliveryId}` | Resolve an ambiguous delivery, scoped to source client |

CAP supports native [REST and OData adapters](https://cap.cloud.sap/docs/node.js/cds-serve). These REST paths are desired public paths to configure and verify in Phase 4, including bound-action routing and CREATE response codes. Prefer the CAP adapter and handlers; if adapter constraints require a different route, update this document before clients depend on it. Lists need bounded pagination; define actual supported query parameters and result envelope in Phase 4 rather than assuming OData query syntax on REST.

RAP base URL, service version and action namespace come from the actual service binding and `$metadata`. Logical active-instance action form: `POST {RAP_WEB_API_BASE}/PurchaseOrders(<uuid>)/<qualified-action>`. This is notation, not a ready-to-run URL; key shape and draft parameters depend on the selected projection. The UI service's draft-specific keys must not be copied blindly into the integration contract.

Planned RAP UI actions: `submit`, `approve`, `reject`, `sendToSupplier`, `cancel`. Planned restricted operations: `applySupplierResponse`, `retryDelivery`, `recordDeliveryResult`. Prefer EML-only access for coordinator bookkeeping where possible; do not expose an administrative HTTP operation just because a class uses it internally. A callback action checks correlation and deduplication under the BO lock; normal UI edits use framework ETags. Confirm any required callback `If-Match` behavior against the actual binding in Phase 3/5 and test concurrent duplicate calls.

Phase 5 calls CAP directly and uses a small local mapping component; the reverse sender calls RAP directly. Phase 6 switches endpoints to CI without changing business identities or ownership.

## Common rules

- HTTPS outside loopback development. JSON uses UTF-8 and `Content-Type: application/json`.
- Contract field names are case-sensitive. UUIDs use canonical hyphenated text, timestamps UTC RFC 3339, and calendar dates `YYYY-MM-DD`.
- Monetary and quantity fields are decimal strings; no scientific notation. Initial currency support is EUR only. Enforce precision, scale and bounds from the domain model.
- `X-Correlation-ID` identifies a transport attempt. A retry may get a new correlation ID while preserving the business delivery/response ID.
- `Idempotency-Key` equals `deliveryId` for ingestion or `responseId` for supplier-response commands. The corresponding body identity remains mandatory; mismatches are rejected. RAP action parameters carry identity even if an adapter cannot preserve the custom header.
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

Initial CAP creation targets `201 Created` with a Location header and the following receipt. A matching replay targets `200 OK` with the same business receipt. The adapter-specific realization will be tested in Phase 4/5.

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

On success, return 200 with the committed portal order/decision and `responseDeliveryStatus: PENDING` if SAP has not acknowledged it. UI acceptance does not claim SAP has been updated. A local/hosted response sender then submits this immutable DTO:

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

CI maps this to logical RAP action parameters `ResponseUUID`, `PurchaseOrderUUID`, `OrderRevision`, `DeliveryUUID`, `PortalOrderUUID`, `Supplier`, `ResponseVersion`, `SupplierResponse`, `EstimatedDeliveryDate`, `Reason`, `RespondedAt`. Actual ABAP parameter field names and date/null encoding will be frozen against `$metadata` in Phase 3/5. For REJECTED, a reason is mandatory and estimatedDeliveryDate is null. A date update keeps decision ACCEPTED and increments the version.

The RAP action derives Status from the decision; no external caller supplies Status directly. Validate identity, dispatched intent, supplier, revision and version, then update the BO and deduplication receipt atomically. Callback success targets 200 with responseId and outcome APPLIED/ALREADY_APPLIED; OData wraps results according to generated metadata. CI maps that result to `{ "responseId": "…", "outcome": "APPLIED" }` for CAP.

Same response ID + different content is 409. Replayed matching IDs return success. New IDs with stale/conflicting versions return 409 and require reconciliation, never overwrite newer state. A newer accepted/date response contains the complete current supplier response, so version gaps can be applied after validating the allowed state; timestamps alone are not ordering keys. Retain prior processed IDs to recognize old duplicates.

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

Initial retry proposal for transient delivery failures: three retries after the initial attempt, with approximately 5 s, 30 s and 120 s delays plus jitter. These are project policy choices, not SAP defaults. Use scheduled attempts, not a long-lived HTTP request sleeping through the entire budget. Honor a longer Retry-After by scheduling within an explicitly configured maximum age; otherwise stop for operator review.

Proposed request budgets: CAP receiver 15 s, CI processing 25 s, coordinator request 35 s. Confirm platform ceilings and tune under failure tests. Give inner calls shorter deadlines than their callers. A timeout never proves non-delivery.

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
