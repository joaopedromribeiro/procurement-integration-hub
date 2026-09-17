# Phase 4.5 — minimal supplier UI

Status: **locally runtime-verified.** From a clean `node_modules`, `npm ci`, `npm run typecheck` and `npm test` all succeeded; **87 tests pass in 20 suites**, including every Phase 4.1–4.4 test. All eleven browser scenarios were driven by hand against a running server. As in the earlier Phase 4 subphases this is local Node.js execution evidence, a different and weaker claim than the SAP runtime evidence behind Phases 1–3. No ABAP source was touched, `SupplierService` was not redesigned, and **nothing is sent to SAP**.

## Purpose

Prove the supplier flow end to end in a browser: list your orders, open one, read its lines, and answer with an acceptance, a rejection or a revised delivery date. Not a design exercise — a demonstration that the Phase 4.4 service is usable by a person.

## UI architecture

Plain HTML, CSS and ES modules. No framework, no build step, no bundler, no dependency added to `package.json`.

CAP serves `app/` as static content at the web root, so `index.html` is available at `http://localhost:4004/` with no configuration. The page is one screen with two views — list and detail — swapped by toggling `hidden`.

| File | Role |
| --- | --- |
| [app/index.html](../app/index.html) | The page: sign-in bar, list table, detail view, three decision controls |
| [app/styles.css](../app/styles.css) | Enough styling to read the screen |
| [app/supplier-ui.mjs](../app/supplier-ui.mjs) | DOM wiring and every `fetch` to the service |
| [app/lib/order-view.mjs](../app/lib/order-view.mjs) | Pure presentation logic — no DOM, no fetch, no state |

The split is what makes this testable without a browser-automation framework. Everything with a decision in it — which controls a status permits, what a command payload contains, how an error is phrased — lives in `order-view.mjs` as pure functions, and the test suite imports **the same file the browser loads**. What is tested is what runs.

`.mjs` rather than `.js` so Node treats the module as ESM without an extra `package.json`; the served content type is `text/javascript`, verified.

## Routes and service calls

The UI has no routes of its own: it is one page, and the detail view is state rather than a URL. Every call goes to `SupplierService` and nowhere else.

| User action | Call |
| --- | --- |
| Sign in | none — credentials are stored for the next request |
| Show list | `GET /rest/supplier/v1/Orders?limit=20&offset=N` |
| Open an order | `GET /rest/supplier/v1/Orders/{portalOrderId}` and `GET …/items` |
| Accept | `POST /rest/supplier/v1/Orders/{portalOrderId}/accept` |
| Reject | `POST …/reject` |
| Update date | `POST …/updateEstimatedDeliveryDate` |

A test asserts this structurally against the shipped script: the only base path is `/rest/supplier/v1`, `/rest/integration/v1` and `/odata/` appear nowhere, and the strings `'PATCH'`, `'PUT'` and `'DELETE'` appear nowhere. The single write verb in the file is `method: 'POST'`.

## Supplier identity

Reuses the Phase 4.4 mechanism unchanged. The page collects a username and password, keeps them in `sessionStorage`, and sends `Authorization: Basic …` on every request. The backend derives the supplier from the authenticated user's attributes.

**The browser never sends a supplier code.** A test greps both shipped scripts for an assignment to `supplierCode` and fails if one appears; the field is read from responses and never written into a request. That is the frontend half of the rule ARCHITECTURE.md states for the backend: *"never a trusted supplier code supplied by the browser."*

**This is local mock sign-in, not production authentication.** The page says so in a banner, in the words "not production authentication", above everything else. Mocked basic auth over plain HTTP on a developer machine demonstrates that isolation is enforced server-side; it demonstrates nothing about identity assurance. XSUAA, IAS and token validation are Phase 8.

## List

Columns: order number, status, total with currency, estimated delivery date, response version, and an Open button.

`portalOrderId` is used for routing to the detail view and is **never rendered**. `sourceSystem`, `sourceOrderId`, `sourceRevision`, `deliveryId` and the pending-response records are not exposed by the Phase 4.4 read model at all, so the UI could not show them even by mistake.

## Detail

Header: order number, status, total, estimated delivery date, response version, and rejection reason when one exists. Items: line number, product code, description, quantity with unit, unit price with currency, line amount with currency.

Decision controls are shown by status, from `actionsFor()`:

| Status | Accept | Reject | Update date |
| --- | --- | --- | --- |
| `RECEIVED` | shown | shown | hidden |
| `ACCEPTED` | hidden | hidden | shown |
| `REJECTED` | hidden | hidden | hidden |

This mirrors the backend lifecycle and duplicates none of it. Getting it wrong would show a button the service then refuses — the rule is still enforced in exactly one place.

## Accept, reject, update date

All three build their payload the same way:

```js
{ responseId: crypto.randomUUID(), expectedResponseVersion: order.responseVersion, … }
```

`responseId` is generated per user command, so a *new* action is a new command while a retry of the same action would be recognised as a replay. `expectedResponseVersion` is read from the loaded order — **the user never types a version**; it is a precondition the client observed, not an input it chooses.

- **Accept** sends the date only when one was picked. An omitted date means unknown and is never defaulted to today, so the key is absent from the payload rather than null.
- **Reject** requires a reason. The page checks for a blank one as a convenience; the service is what actually enforces it, and a blank reason still returns `MISSING_REJECTION_REASON` if the check is bypassed.
- **Update date** sends a new `responseId` with the current version and the chosen date.

After every success the order is **re-read from the service** rather than patched from the response body, so the screen shows committed state. The success line quotes the new status, the new version and — for accept — `responseDeliveryStatus`, which is always `PENDING`: the UI never implies SAP has been told.

## Pagination

API_CONTRACTS.md required this and deferred the specifics: *"Lists need bounded pagination; define actual supported query parameters and result envelope … rather than assuming OData query syntax on REST."* Phase 4.4 deferred it again to here. Neither `$top` nor `limit` had any effect before this subphase — verified by trying both.

**The contract, defined here and now implemented:**

| Element | Decision |
| --- | --- |
| Parameters | `?limit=` and `?offset=`, not `$top`/`$skip` — the contract explicitly rules out assuming OData syntax on REST |
| Default | `limit=20` |
| Server maximum | `100`; a larger value is **clamped**, not refused |
| Invalid value | `400` `INVALID_PAGINATION` for anything non-integer or negative |
| Result envelope | **A bare JSON array, unchanged.** No wrapper, no total count |
| Scope | The `Orders` collection only |

Two choices are worth defending.

**No envelope, and therefore no total count.** Wrapping the array would have changed a read contract that Phase 4.4 verified and tested, for a count this portal has no use for. The client pages until it receives fewer rows than it asked for — `hasNextPage()` is that rule — which is enough for Previous/Next and costs nothing. A count can be added later as an additive change; removing an envelope could not.

**Items are not paged.** A single order read needs no bound, and item counts are already bounded: Phase 4.3 ingestion refuses a delivery of more than 100 lines. Applying a 20-row default to the detail view would silently truncate a 30-line order — a bound where there is no risk, at the cost of showing a supplier an incomplete order.

A malformed value is refused rather than silently defaulted, because a client that asked for something specific should be told it was not understood; an oversized limit is clamped instead, because that request is meaningful and merely larger than the portal serves.

## Error handling

`describeError(status, body)` turns any failure into one line. The service's own envelope — `{ error: { code, message, correlationId } }` — is shown as written, because those messages were composed for this audience. Anything else gets a generic line: an unexpected failure's text is not meant for a user and may not be safe to show. A test feeds it a body containing a stack trace and asserts none of it reaches the screen.

| Case | Shown |
| --- | --- |
| 400 validation | the service's message and code |
| 401 | "Sign in to continue", session cleared, views hidden |
| 403 no supplier | the service's message, or "This user has no supplier access" |
| 404 | "That order is not available to you" |
| 409 lifecycle or response conflict | the service's message and code |
| 409 `STALE_RESPONSE_VERSION` | the service's message **plus an automatic reload of the order** |
| 500 or unparseable | "The portal could not complete that request" |
| Network failure | "The portal is unreachable" |

**Stale version is the only case with behaviour attached.** The order is reloaded so the supplier can decide against current state. The command is **not** resent — a retry with a new `responseId` could apply a decision the supplier no longer intends, now that the order has changed underneath them. No retry logic exists anywhere in this UI.

## Runtime evidence

Server started with `npm start`; all eleven scenarios driven in a real browser against `http://localhost:4004/`.

**1 — mock sign-in as SUP001.** Signed in as `supplier1`; header shows "Signed in as supplier1".

**2 — SUP001 order list:**

```text
ORDER        STATUS     TOTAL         DELIVERY DATE  VERSION
PO00001001   RECEIVED   1861.50 EUR   —              0       [Open]
PO00001002   RECEIVED   750.00 EUR    —              0       [Open]
Previous   Showing 1–2   Next
```

**3 & 4 — open an order and see its items.** `PO00001001`, status `RECEIVED`, total `1861.50 EUR`, version `0`, and:

```text
LINE  PRODUCT  DESCRIPTION       QUANTITY    UNIT PRICE      LINE AMOUNT
10    MAT001   Laptop            2.000 PCE   750.0000 EUR    1500.00 EUR
20    MAT002   Docking station   3.000 PCE   120.5000 EUR    361.50 EUR
```

Only **Accept** and **Reject** were rendered — no date control, because the order was `RECEIVED`.

**5 & 6 — accept with a date.** Chose `2026-11-15`, clicked Accept:

```text
Accepted. Status ACCEPTED, version 1, delivery response PENDING.

Status                     ACCEPTED
Estimated delivery date    2026-11-15
Response version           1
```

The controls flipped in the same render: Accept and Reject disappeared, **Update estimated delivery date** appeared.

**11 — update the delivery date.** Chose `2026-12-20`:

```text
Delivery date updated to 2026-12-20, version 2.
Status ACCEPTED · Estimated delivery date 2026-12-20 · Response version 2
```

Status stayed `ACCEPTED` and the version advanced to 2, as the contract requires.

**URL/id tampering — another supplier's order, while signed in as SUP001:**

```text
GET  /rest/supplier/v1/Orders/22222222-…-000000000003          -> 404
GET  /rest/supplier/v1/Orders/22222222-…-000000000003/items    -> 404
POST /rest/supplier/v1/Orders/22222222-…-000000000003/accept   -> 404
     {"error":{"code":"ORDER_NOT_FOUND","message":"No order 22222222-…-000000000003 exists for this supplier.", …}}
```

Refused on every route, by the backend, with no field disclosed.

**Stale version, exercised in the browser:** a command carrying `expectedResponseVersion: 0` against an order already at 2 returned `409 STALE_RESPONSE_VERSION`, and `describeError` resolved it to `refresh: true` — reload, do not retry.

**7 & 8 — sign in as SUP002.** The list showed exactly one order, `PO00001003`. SUP001's orders were not present.

**9 & 10 — reject as SUP002.** Reason "Out of stock until Q1":

```text
Rejected. Status REJECTED, version 1.

Status             REJECTED
Response version   1
Rejection reason   Out of stock until Q1
```

All three decision controls were then hidden — `REJECTED` is terminal.

### One bug the browser caught

The first render showed the sign-in panel *and* the signed-in bar at once. `#session { display: flex }` is an author rule, and it beats the user-agent stylesheet's `[hidden] { display: none }` — so every panel toggled by `hidden` was permanently visible. `[hidden] { display: none !important; }` fixes it. No test would have found this; it took looking at the page.

## Tests

**87 tests, 20 suites.** The run prints 21 top-level entries but reports 20 suites, because `health.test.ts` contributes a standalone `test()` rather than a `describe()` — entry 4 is that test. Entries 1–15 are Phases 4.1–4.4 unchanged, fourteen suites plus that one test; entries 16–21 are the six new suites:

| Suite | Covers |
| --- | --- |
| the UI is served as static assets | all four assets return 200; the page loads anonymously while the service still returns 401 |
| the browser code talks only to SupplierService | one base path; no integration or OData path; no `PATCH`/`PUT`/`DELETE`; no `supplierCode` written into a request |
| lifecycle controls follow the order status | the full status matrix, including an unknown status |
| command payloads | version taken from the order, fresh UUID per command, supplied id reused, date omitted when absent, no `status` or `supplierCode` in any payload |
| error presentation | stale version sets `refresh`, contract errors shown verbatim, stack traces suppressed, 401/404 explained |
| the list is bounded | client clamping, next-page detection, `limit`/`offset` over HTTP, `400` on malformed values, clamping of oversized limits, single read and items unpaged |

No browser-automation framework was added. The presentation logic is imported directly, and everything else is asserted over HTTP against the running application.

## Known limitations

- **Mock authentication.** Basic auth against users in `.cdsrc.json`, credentials held in `sessionStorage`. Fine for a local demonstration, not an authentication design.
- **No deep links.** The detail view is state, not a URL, so an order cannot be bookmarked or shared and the browser Back button leaves the page. A router was out of scope for a minimal UI.
- **No total count** in the list, by the pagination decision above; Previous/Next only.
- **No optimistic concurrency in the UI beyond the version precondition.** Two browser tabs on one order were not raced — the same limitation Phase 4.4 recorded, unchanged here.
- **No accessibility audit, no responsive design pass, no i18n.** Labels, a table and keyboard-usable controls, and nothing more.
- **No client-side date minimum.** The date input accepts a past date and the service refuses it with `DELIVERY_DATE_IN_PAST`. Deliberate: the rule has one home.

## What remains for Phase 4.6

Phase 4 closure: a consolidated pass over the four subphases, confirmation that the full local suite passes from a clean checkout, and a decision on whether anything in Phase 4 remains open before Phase 5 connects RAP and CAP. No new capability is planned.

## Reading the Phase 4.5 code if CAP and frontends are new to you

**How the browser reaches CAP.** There is no SDK and no generated client. `fetch('/rest/supplier/v1/Orders')` is an ordinary HTTP request to the same origin that served the page, and CAP's REST adapter answers it. The service is a normal web API; the browser is a normal web client.

**`fetch()`** returns a `Response` whose `ok` flag is false for 4xx and 5xx — it does *not* throw on an error status, only on a network failure. That is why `call()` checks `response.ok` explicitly; forgetting to is how a 409 gets rendered as if it were success.

**GET versus POST.** `GET` reads and is safe to repeat. `POST` changes something. Reading the list and the detail is `GET`; accepting, rejecting and re-dating are `POST`, because each records a decision.

**Why the decisions are POSTed actions, not a PATCH.** A `PATCH` would say "set this field". The supplier is not setting a field; they are making a decision that the portal turns into a status, a version, a timestamp and an outbound response. Those are outcomes, not inputs. Sending `{"status":"ACCEPTED"}` would mean the browser decides what the new state is — and then nothing would enforce the transition, require a reason, allocate a version or write the pending response. The action keeps the rule and the write inseparable. The service makes this structural rather than advisory: the projections are `@readonly`, so a `PATCH` returns 405.

**`responseId`.** A UUID minted per user command, sent with the request. If the same command arrives twice — a double-click, a flaky connection — the service recognises the id and returns the original decision instead of applying a second one. It is the idempotency key, and it exists because the network is allowed to be unreliable.

**`expectedResponseVersion`.** The version the page loaded. If someone else has since changed the order, the service refuses with 409 rather than letting a stale screen overwrite a newer decision. The user never types it; typing it would make it a wish rather than an observation.

**Why no `supplierCode` is sent.** Whoever you are is established by authentication, not by what you claim. If the browser sent a supplier code, every supplier could send a different one. The backend reads it from the authenticated user, so the worst a tampered request can do is ask about an order it does not own — and get a 404.

**Stale-version handling.** Show the message, reload the order, stop. No automatic retry: the order changed, so the decision the supplier made a moment ago may not be the one they would make now. Retrying with a new id would quietly apply it anyway.

**Compared with a Fiori UI over RAP.** Phase 3.2's Fiori Elements app is generated: annotations in the CDS describe the columns and facets, and the framework builds the screens and calls the OData actions itself. Here everything is hand-written, and the difference is instructive rather than a downside — the call this page makes, `POST /Orders/{key}/accept` with parameters in the body, is the same shape Fiori generates for a bound RAP action such as `submit` or `approve`. Same pattern, one written by a framework from metadata and one written by hand, and both ending at a handler that owns the rule.
