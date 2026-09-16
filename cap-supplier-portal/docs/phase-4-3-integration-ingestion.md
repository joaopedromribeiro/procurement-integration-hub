# Phase 4.3 — integration-facing order ingestion

Status: **locally runtime-verified.** From a clean `node_modules`, `npm ci`, `npm run typecheck` and `npm test` all succeeded; 34 tests pass in 8 suites, including every Phase 4.1 and 4.2 test. The four contract scenarios were also exercised by hand against a running server. As in Phases 4.1 and 4.2 this is local Node.js execution evidence, a different and weaker claim than the SAP runtime evidence behind Phases 1–3. Nothing here runs in or against an SAP system, and no ABAP source was touched.

## Purpose

Build the CI → CAP edge: an external caller posts the mapped purchase-order snapshot, the portal validates the integration contract, resolves the supplier, stores the order with its lines and returns a receipt. Deliveries are idempotent, so a replay is safe and a reused identity with different content is refused rather than silently overwriting a committed order.

SAP does not call this endpoint yet — that is Phase 5 — and no Integration Suite component exists between them — that is Phase 6.

## Service boundary

`IntegrationService` is a separate service from the Phase 4.4 `SupplierService` that does not exist yet, so the two can carry different permissions when authorization arrives (ADR-005). It exposes exactly one thing.

| Property | Value |
| --- | --- |
| Route | `POST /rest/integration/v1/Orders` |
| Declaration | `@protocol: 'rest'`, `@path: '/rest/integration/v1'`, entity `Orders` |
| Operations | CREATE only — `@insertonly`, so `GET` returns **405** |
| Persistence exposure | **None.** `IntegrationService.Orders` is a service-local contract entity, not a projection on `pih.portal.Orders` |

The documented route was achievable exactly as written; nothing in the external contract had to move to suit CAP.

Because the service entity is not a projection, there is no generic CRUD path into persistence at all. A test asserts this structurally: no entity in any served service has a `projection` or `query`, so none of them can be a view on the database.

## Inbound contract

The request body is the **Mapped CAP order** from [API_CONTRACTS.md](../../API_CONTRACTS.md), used verbatim. It is nested, and it is deliberately not the persistence shape:

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

No SAP name appears anywhere in it. `product.code` is not `MATNR`, `source.orderNumber` is not `EBELN`, and the unit is the portal's `PCE` rather than SAP's `EA` — the `EA → PCE` value mapping happens upstream, and a delivery still carrying `EA` is refused rather than guessed.

Monetary and quantity values are **decimal strings**, per the contract's common rules: "Monetary and quantity fields are decimal strings; no scientific notation."

### Two CAP behaviours had to be corrected to keep this contract

**CAP flattens structured elements by default.** The first attempt returned `400 Property "source" does not exist in IntegrationService.Orders`, because `source` had been flattened to `source_system`, `source_orderId` and so on. Setting `cds.odata.structs: true` in `.cdsrc.json` keeps structured elements intact, and the nested body is then delivered to the handler exactly as sent. The flag is a CAP-native option, so the contract is preserved without reading the raw request body behind the framework's back.

**CAP generates a value for a `UUID`-typed key when the caller omits it.** With `key deliveryId : UUID`, a delivery with no `deliveryId` at all was accepted with 201 and a server-invented identity — quietly turning the contract's mandatory delivery identity into an optional one, and destroying the idempotency guarantee for that request. A test caught it. The key is declared `String(36)` instead, and the canonical UUID form is enforced in the handler, so an absent `deliveryId` is now a 400.

## Handler flow

```text
POST /rest/integration/v1/Orders
  │
  ├─ 1  correlation id: reuse X-Correlation-ID or mint one; echo it on the response
  ├─ 2  normalizeDelivery(req.data)        → 400 on any contract violation
  ├─ 3  SELECT DeliveryReceipts by (sourceSystem, deliveryId)
  │        found + same hash  → 200 + the original receipt        (replay)
  │        found + other hash → 409 DELIVERY_PAYLOAD_CONFLICT     (conflict)
  ├─ 4  SELECT Suppliers by supplierCode   → 400 UNKNOWN_SUPPLIER if missing/inactive
  ├─ 5  INSERT Orders (deep, with items)  ┐ one transaction
  │     INSERT DeliveryReceipts           ┘
  │        unique violation → translate to 409, or re-read and answer as a replay
  └─ 6  201 + receipt
```

## Persistence mapping

The handler is the only thing that converts the wire shape into the stored shape. There is no deep insert from the payload.

| Inbound | Stored |
| --- | --- |
| `source.system` | `Orders.sourceSystem` |
| `source.orderId` | `Orders.sourceOrderId` |
| `source.revision` | `Orders.sourceRevision` |
| `source.orderNumber` | `Orders.externalOrderNumber` |
| `supplierCode` | resolved → `Orders.supplier_ID` |
| `amount.currency` / `amount.value` | `Orders.currency` / `Orders.totalAmount` |
| `lines[].sourceItemId` | `OrderItems.sourceItemId` |
| `lines[].lineNumber` | `OrderItems.lineNumber` |
| `lines[].product.code` / `.description` | `OrderItems.productCode` / `.description` |
| `lines[].orderedQuantity.value` / `.unit` | `OrderItems.quantity` / `.uom` |
| `lines[].unitPrice.value` / `.currency` | `OrderItems.unitPrice` / `.currency` |
| `lines[].lineAmount` | `OrderItems.lineAmount` |

Server-owned and never read from the payload: the portal `ID`, `status` = `RECEIVED`, `responseVersion` = `0`, `receivedAt` and `modifiedAt`. None of them is in the inbound contract, so a caller has no way to supply them; the handler sets each one explicitly. `receivedAt` is generated once and written to both the order and the receipt, so the receipt's timestamp is the order's timestamp by construction rather than by coincidence.

## Supplier resolution

`supplierCode` is looked up in `pih.portal.Suppliers`. An unknown code, or a known code whose `active` flag is false, is **400 `UNKNOWN_SUPPLIER`**, and nothing is persisted. Unknown suppliers are never created: the contract says "Resolve active Suppliers record; unknown code is 400", and a portal that invents supplier master data from an inbound message has stopped being a controlled reference.

### `Orders.supplier` became `not null`

The Phase 4.2 model declared `supplier : Association to one Suppliers`. It is now `not null`, and the change is justified by contract rather than by preference: ingestion is the only writer of `Orders`, ingestion refuses an unresolvable supplier with 400, and therefore no order can lawfully exist without one. Making it `not null` turns a handler promise into a database fact. The generated DDL now carries `supplier_ID NVARCHAR(36) NOT NULL`, all Phase 4.2 tests still pass unchanged, and the fixtures were already compliant.

## Integration-contract validation

These are the **20 application-defined 400 codes reachable through the HTTP endpoint**. Every rule below checks that the *message* is a faithful, storable snapshot. None of them re-decides anything SAP already decided: whether the order could be submitted, approved or cancelled is RAP's business and stays there (ADR-004). By the time a delivery arrives those questions are settled, and the portal's only job is to refuse a message it cannot store faithfully.

| Code | Rule | Source |
| --- | --- | --- |
| `SCHEMA_VERSION_UNSUPPORTED` | major version must be `1` | "Unknown schema major versions fail with 400" |
| `MISSING_DELIVERY_ID` | required, canonical UUID | "The corresponding body identity remains mandatory" |
| `INVALID_SOURCE_IDENTITY` | `source.system`, `source.orderId`, `source.revision ≥ 1` | "Preserve source identity separately from CAP UUID" |
| `MISSING_SUPPLIER_CODE` / `UNKNOWN_SUPPLIER` | resolves to an active supplier | "unknown code is 400" |
| `UNSUPPORTED_CURRENCY` | `EUR` only | "Initial currency support is EUR only" |
| `UNSUPPORTED_UNIT` | `PCE` only | "Unknown units fail validation; they are not guessed" |
| `NO_LINES` | at least one line | "no lines … fail before persistence" |
| `TOO_MANY_LINES` | at most 100 | "Proposed initial bound: 100 items … enforce before expensive processing" |
| `INVALID_LINE_NUMBER` / `DUPLICATE_LINE_NUMBER` | positive, unique within the delivery | "reject invalid/duplicate line number" |
| `INVALID_SOURCE_ITEM_ID` / `DUPLICATE_SOURCE_ITEM_ID` | canonical UUID, unique within the delivery | `OrderItems(order, sourceItemId)` uniqueness |
| `MISSING_PRODUCT_CODE` | `product.code` is required on every line | `OrderItems.productCode`; a line with no product cannot be stored faithfully |
| `INVALID_QUANTITY` | greater than zero | a line with no quantity is not a storable order line |
| `INVALID_PRICE` | not negative; **zero is valid** | "negative prices fail … Zero price is valid" |
| `LINE_CURRENCY_MISMATCH` | line currency equals header currency | "Propagate currency to each price" |
| `LINE_AMOUNT_MISMATCH` | `round(quantity × unitPrice, 2)` equals `lineAmount` | "Verify arithmetic; do not invent totals during mapping" |
| `TOTAL_AMOUNT_MISMATCH` | header total equals the sum of line amounts | "inconsistent totals … fail before persistence" |
| `INVALID_DECIMAL` | plain decimal string within the model's scale | "decimal strings; no scientific notation" |

### Three layers refuse a bad request, and only one of them is ours

The table above is the externally reachable set. Two other things can produce a 400 at this endpoint, and conflating them with the contract codes would misdescribe the boundary.

| Layer | Produces | Reachable over HTTP |
| --- | --- | --- |
| CAP framework, before any handler runs | `ASSERT_DATA_TYPE` for a non-object JSON scalar body, in CAP's own envelope | **Yes** |
| `IntegrationService` contract validation | the 20 codes above, in the contract envelope | **Yes** |
| `normalizeDelivery` internal guard | `INVALID_PAYLOAD` | **No** |

**`INVALID_PAYLOAD` is an internal defensive code, not part of the HTTP error-code set.** It fires when `normalizeDelivery` is handed something that is not an object, and no request body can put it in that position: a JSON scalar is stopped one layer earlier by CAP's type assertion, and `null`, `[]` and `{}` all arrive at the handler as an empty object, which passes the object check and falls through to `SCHEMA_VERSION_UNSUPPORTED`.

The guard is **retained**, because `normalizeDelivery` is a plain function and Phase 5's local mapping component may call it without an HTTP request in front of it. It is **verified by a direct test** rather than an HTTP one, since a test asserting it over HTTP could not pass. Counting it among the endpoint's error codes would promise callers a response they can never receive.

So: **20 application-defined codes reachable over HTTP**, 21 emitted by the implementation, and the difference is this one guard.

### The arithmetic is exact, not floating point

Decimals are parsed into scaled `BigInt` values — quantity at scale 3, unit price at 4, amounts at 2 — and every comparison and product is integer arithmetic, rounded half up exactly as the domain model specifies. `750.0000` and `120.5000` are not representable in binary floating point, and a total compared after a float multiply is a bug waiting for the first awkward price. `3.000 × 120.5000 = 361.50` is checked, not approximated.

## Delivery idempotency

The primitive is a database constraint, not a check in code:

```sql
CONSTRAINT pih_portal_DeliveryReceipts_delivery UNIQUE (sourceSystem, deliveryId)
```

`DeliveryReceipts` is specified in the CAP persistence table of [docs/architecture/domain-model.md](../../docs/architecture/domain-model.md) — "source system + deliveryId unique; normalized request hash; source order identity; portal order ID; original receipt; createdAt". **That table marks it phase 5 and Phase 4.3 pulls it forward deliberately.** The ingestion contract requires an exact replay to return the *original* receipt and a conflicting reuse to return 409, and neither question is answerable without a stored hash and a stored receipt. The rest of the Phase 5 delivery machinery — `DeliveryIntent`, `SupplierResponseDelivery`, attempt history — is not pulled forward with it.

### The hash is what makes a replay a replay

The contract requires normalizing "known fields, decimal representation and object member ordering before hashing", because "raw JSON byte order alone is not a meaningful equality check". Validation already fixes decimal representation and sorts the lines by line number; the hash is then taken over an explicitly ordered projection of the normalized delivery.

The effect is visible: a replay that reorders every JSON member and writes `"1500.0"`, `"750.00"` and `"2"` instead of `"1500.00"`, `"750.0000"` and `"2.000"` is recognised as the same delivery and answered with the same receipt. A test covers exactly that.

### What is verified, and what is not

**Verified.** Sequential replay returns the original receipt with 200 and creates nothing. A conflicting payload under the same `deliveryId` returns 409 and leaves the stored order untouched. Two concurrent `POST`s with one `deliveryId` are both answered and produce exactly one order, one line and one receipt. The unique constraint is real: inserting a second receipt row for the same source system and delivery id directly through CQN is rejected by the database.

**Not verified.** The handler's race branch — catching a unique-constraint violation raised by a concurrent winner and then re-reading the committed receipt — was never entered. Instrumenting that branch and running the concurrent test three times produced zero hits: on a single local SQLite connection the two requests serialize far enough apart that the second one's pre-check always finds the committed receipt and takes the ordinary replay path. The branch exists for a database with genuine write concurrency and for more than one application instance, and **its correctness is reasoned rather than exercised.** The invariant it protects is verified; the code path that protects it is not.

## Source-order uniqueness is a different rule

Two uniqueness rules operate here and they answer different questions.

| Rule | Question | Answer on violation |
| --- | --- | --- |
| `DeliveryReceipts(sourceSystem, deliveryId)` | "have I already processed *this delivery attempt*?" | identical content → 200 with the original receipt; different content → 409 |
| `Orders(sourceSystem, sourceOrderId, sourceRevision)` | "have I already stored *this version of this order*?" | 409 `SOURCE_ORDER_ALREADY_INGESTED`, naming the original portal order and delivery |

A repeated delivery is a transport event: the same message arriving twice, which must be harmless. A repeated source order under a *new* delivery id is a reconciliation problem: someone believes this order has not been delivered when it has. Collapsing the second into the first would make a genuine duplicate look like a successful replay and hide the discrepancy, which is why the contract gives it its own 409 "with a safe reconciliation reference" — here, the portal order id and the delivery id that originally carried it.

The same source order at a **new revision** is a different order and is accepted. A test covers each of the three cases.

## Transaction boundary

CAP runs each request in one transaction. The deep insert of the order with its lines and the insert of the delivery receipt are both inside it, so either all three kinds of row appear or none does.

Every refusal test asserts this rather than assuming it: a shared helper snapshots the row counts of `Orders`, `OrderItems` and `DeliveryReceipts`, issues the request, and asserts the counts are byte-identical afterwards. That covers validation failures, which fail before any write, and the source-order conflict, which fails at the database after the handler has begun writing.

## Receipt

Exactly the receipt in API_CONTRACTS.md, and nothing else:

```json
{
  "deliveryId": "0e7df7c7-2427-4700-a7bb-63aa9f1a11af",
  "sourceOrderId": "82e96537-4ecc-4c34-b2c3-e75486329447",
  "portalOrderId": "44853146-0db1-4e31-8a89-5cabea8850ab",
  "status": "RECEIVED",
  "receivedAt": "2026-09-16T21:28:41.859Z"
}
```

A test asserts the key set, so a future change cannot quietly widen it. No SQLite detail, generated column name, entity shape or stack trace reaches the caller.

## HTTP semantics

| Situation | Status | Body |
| --- | --- | --- |
| New valid delivery | **201** | receipt |
| Exact replay of a delivery already accepted | **200** | the original receipt |
| Same `deliveryId`, different content | **409** | error, `DELIVERY_PAYLOAD_CONFLICT` |
| New `deliveryId`, source order/revision already ingested | **409** | error, `SOURCE_ORDER_ALREADY_INGESTED` |
| Any contract violation | **400** | error, with one of the 20 application-defined codes |
| Body that is not a JSON object | **400** | CAP's `ASSERT_DATA_TYPE`, raised before the handler |
| `GET`/`PATCH`/`DELETE` on the route | **405** | — |
| Unexpected failure | 500 | CAP's generic error; no internals |

Errors use the envelope from the contract, with `X-Correlation-ID` honoured when the caller sends one and minted when it does not:

```json
{
  "error": {
    "message": "supplierCode \"SUP999\" is not an active supplier in this portal.",
    "correlationId": "fe71e922-2d8b-404f-aee3-17aac001929c",
    "retryable": false,
    "code": "UNKNOWN_SUPPLIER"
  }
}
```

### A framework constraint worth recording

CAP's REST adapter cannot express "this CREATE returns 200". Its create middleware ends with `return { result, status: 201 }`, and the adapter applies it as `if (status && res.statusCode === 200) res.status(status)` — *only set the status if the handler has not already changed it.* Since the express default is already 200, a handler can select any status except the one the replay contract requires. The handler pins the status by setting it and then replacing `res.status` with a no-op for the rest of the response; it is three lines, commented at the point of use, and nothing later in the success path needs to change the status again.

## Test evidence

37 tests, 8 suites, from a clean `npm ci`:

```text
ok 1 - the model deploys
ok 2 - fixtures load
ok 3 - relationships
ok 4 - the CAP runtime serves the health endpoint
ok 5 - a valid delivery
ok 6 - delivery idempotency
ok 7 - source-order uniqueness is a different rule from delivery uniqueness
ok 8 - integration-contract validation
ok 9 - the service boundary
# tests 37
# suites 8
# pass 37
# fail 0
```

Suites 1–4 are the unchanged Phase 4.1 and 4.2 tests. Suite 5 posts a two-line delivery and then reads the stored order back through its supplier association and its items composition, checking every mapped field and every server-owned field. Suite 6 covers replay, normalized replay, conflict, concurrency and the database constraint. Suite 7 covers the two uniqueness rules and the new-revision case. Suite 8 has sixteen refusal cases, each asserting that nothing was persisted, plus one direct assertion on the `INVALID_PAYLOAD` guard, which no HTTP body can reach. Suite 9 asserts the boundary: 405 on `GET`, 404 on every Phase 4.4 route, and no service entity anywhere that projects on persistence.

## Manual HTTP evidence

Against a freshly started server, `npm start`:

```text
$ POST /rest/integration/v1/Orders   (new delivery)
HTTP 201
{"deliveryId":"0e7df7c7-…","sourceOrderId":"82e96537-…","portalOrderId":"44853146-0db1-4e31-8a89-5cabea8850ab","status":"RECEIVED","receivedAt":"2026-09-16T21:28:41.859Z"}

$ POST /rest/integration/v1/Orders   (exact replay)
HTTP 200
{"deliveryId":"0e7df7c7-…","sourceOrderId":"82e96537-…","portalOrderId":"44853146-0db1-4e31-8a89-5cabea8850ab","status":"RECEIVED","receivedAt":"2026-09-16T21:28:41.859Z"}

$ POST /rest/integration/v1/Orders   (same deliveryId, quantity 2 → 3)
HTTP 409
{"error":{"message":"deliveryId 0e7df7c7-… was already accepted with different content. The stored order is unchanged; use a new deliveryId for a corrected snapshot.","correlationId":"18abd8bc-…","retryable":false,"code":"DELIVERY_PAYLOAD_CONFLICT"}}

$ POST /rest/integration/v1/Orders   (supplierCode SUP999)
HTTP 400
{"error":{"message":"supplierCode \"SUP999\" is not an active supplier in this portal.","correlationId":"fe71e922-…","retryable":false,"code":"UNKNOWN_SUPPLIER"}}
```

The replay returns the *same* `portalOrderId` and the *same* `receivedAt` as the original — it is the stored receipt, not a recomputed one.

Phase 4.4 remains unimplemented, verified rather than asserted:

```text
GET /rest/supplier/v1/Orders          -> 404
GET /rest/supplier/v1/Orders/1/accept -> 404
GET /rest/supplier/v1/Orders/1/reject -> 404
GET /odata/v4/Orders                  -> 404
GET /rest/integration/v1/Orders       -> 405   (insert-only)
```

Startup log:

```text
[cds] - loaded model from 4 file(s):
  > init from db\data\pih.portal-Suppliers.csv
  > init from db\data\pih.portal-Orders.csv
  > init from db\data\pih.portal-OrderItems.csv
[cds] - serving HealthService {
[cds] - serving IntegrationService {
[cds] - server listening on { url: 'http://localhost:4004' }
[cds] - server v10.1.0 launched in 1615 ms
```

Two services. No supplier service.

## Known limitations

- **The race branch is unexercised**, as described above. Its invariant is verified; the branch itself is reasoned.
- **No `Location` header is emitted by this handler.** The contract pairs 201 with a Location header, and CAP does set `location: Orders/<deliveryId>` automatically — but that URL returns 405, because the service is insert-only and the receipt-resolution endpoint `GET /rest/integration/v1/DeliveryReceipts/{deliveryId}` from the boundary table is not part of Phase 4.3. Rather than emit a header pointing at a resource that cannot be read, the header is left as CAP produces it and the readable receipt endpoint is deferred. It belongs with the operations surface.
- **No authentication.** `source.system` is checked for presence and shape but not "validated against the authenticated integration client", because there is no authenticated client. That is Phase 8; the check is a stub with a documented gap, not a silent omission.
- **The 256 KiB body bound is not enforced.** The 100-line bound is. Byte-size limiting belongs to the adapter or platform rather than a handler, and `413` is not produced by this code.
- **`@assert.unique` and the database constraint overlap.** Both exist. Which one raises first was not established; the handler translates either into the right status by matching the constraint name in the error text, which is the fragile part of this implementation and the thing most likely to need revisiting on a CAP upgrade.
- **Decimals are stored through SQLite's `REAL_DECIMAL`.** Validation arithmetic is exact `BigInt`; storage is not. On HANA the column types differ and this deserves rechecking.

## What remains for Phase 4.4

The supplier-facing service: supplier-filtered list and detail, `accept`, `reject`, `updateEstimatedDeliveryDate`, `responseVersion` increments, row-level supplier isolation, and the rule that a decision and its pending response commit together. The `Orders` decision columns that Phase 4.2 created and Phase 4.3 still leaves at `RECEIVED` / `0` / null are what that subphase finally writes.

OI-04 is **partly closed**: REST structured ingestion is implemented and verified, and the bound-action wire behaviour of the supplier commands is not.

## Reading the Phase 4.3 code if CAP is new to you

Every construct below is in the files this subphase added. Comparisons are to ABAP RAP, which this project already covers.

**Service CDS versus db schema CDS.** [db/schema.cds](../db/schema.cds) defines *tables*: `pih.portal.Orders` is a thing on disk. [srv/integration-service.cds](../srv/integration-service.cds) defines a *contract*: `IntegrationService.Orders` is a shape on the wire that exists only for the duration of a request. They share a name and almost nothing else — one is nested with `source{}` and `amount{}`, the other is flat with `sourceSystem` and `totalAmount`. In RAP terms the db schema is your tables plus base views, and the service CDS is closest to a service definition over a projection — except that here the projection is deliberately absent, which is the next point.

**Why the db entity is not exposed.** In CAP, writing `entity Orders as projection on portal.Orders` would have given the caller working `GET`, `POST`, `PATCH` and `DELETE` against the table for free. That is convenient and wrong: the wire contract would become the table layout, every column rename would break integration clients, and an external caller could set `status` or `responseVersion` directly. Declaring a standalone entity with `@insertonly` means the only way in is the one handler. RAP makes the same distinction when a projection re-exposes a BO but the behavior definition decides what may actually be called — Phase 3.1's projection listed `use create; use update; use delete;` explicitly rather than inheriting everything.

**The CREATE handler and `this.on(...)`.** `this.on('CREATE', 'Orders', req => this.ingest(req))` registers *the* implementation for POSTs to that entity. `on` replaces the generic behaviour rather than adding to it, which is what you want when there is no generic behaviour worth keeping — CAP also has `before` and `after` for validation and enrichment around a generic handler. The closest RAP parallel is a behavior implementation method for an action: a single place the framework routes the operation to.

**`req.data`.** The parsed request body, already checked against the declared contract shape. `req.data.source.orderId` is the value the caller sent. It is roughly RAP's importing parameter structure for an action — the framework has done the transport work, and the handler starts from typed content. `req.headers` carries the HTTP headers; `req.http.res` is the raw express response, used here only to pin the status code.

**Transaction handling.** CAP wraps each request in one transaction automatically, so the two `INSERT`s in `persist` either both commit or both vanish. There is no explicit commit in the handler — throwing or rejecting is what rolls back. That is the inverse of the EML style in Phase 2, where `COMMIT ENTITIES` was written out and failures had to be inspected before committing; here the default is atomic and you opt out, rather than opting in.

**`SELECT` and `INSERT`.** These are CQN, CAP's query language, written as JavaScript rather than as SQL strings: `SELECT.one.from(Suppliers).where({ supplierCode })` and `INSERT.into(Orders).entries({...})`. They are database-independent — the same statement runs against SQLite now and HANA later — and parameterised, so no value is ever concatenated into SQL. `INSERT.into(Orders).entries({ ..., items: [...] })` is a *deep* insert: the composition is written with its parent in one statement.

**Association resolution.** The inbound message carries `supplierCode`, a string. The database column is `supplier_ID`, a UUID. The handler bridges them with one `SELECT` and stores the resolved key. Nothing else in the payload is allowed to reach into master data. This is why `supplierCode` is "the external mapping key" and `ID` is "the portal's own key" — the same identity split Phase 2.7E made in RAP between `PurchaseOrderUUID` and `PurchaseOrderNumber`.

**201 versus 200 versus 409.** `201 Created` means *I made something new*. `200 OK` on a replay means *this already existed and here it is again* — critically, not an error, because a retried delivery after a network timeout is normal and must be safe. `409 Conflict` means *this identity is already in use for something else, and I will not overwrite it*. The three together are what makes the endpoint safe to retry blindly, which matters because Phase 5's dispatcher will retry on timeout without knowing whether the first attempt committed.

**Idempotency.** An operation is idempotent when doing it twice leaves the same result as doing it once. Here it is achieved with a stored hash and a database unique constraint rather than with a "check then insert", because two simultaneous requests can both pass a check and only a constraint can stop both from inserting.

**`deliveryId` versus `sourceOrderId`.** `sourceOrderId` identifies *the order in SAP* and never changes. `deliveryId` identifies *one attempt to send it* and is new each time a genuinely new delivery is made. Resending the same message reuses the same `deliveryId` — that is a replay, answer 200. Sending the same order under a new `deliveryId` is a different claim: someone thinks it was never delivered. That is a 409 needing reconciliation, not a replay.

**How SAP will call this in Phase 5.** The ABAP dispatch coordinator will build this exact JSON from a committed purchase-order snapshot, `POST` it to this route over HTTPS, and store the returned `portalOrderId` and receipt against its own `DeliveryIntent`. If the call times out it will replay the *same* `deliveryId`, and this endpoint's 200-with-the-original-receipt is what makes that replay safe. Phase 6 then puts Integration Suite between them, and this contract does not change — only the caller does.
