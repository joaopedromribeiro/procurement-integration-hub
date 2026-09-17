# Phase 4.6 — Phase 4 closure and consolidated verification

Status: **complete. Phase 4 is closed.**

**No new capability was added in Phase 4.6.** No entity, no route, no handler, no rule, no UI control and no test assertion about behaviour was introduced. This subphase re-verified Phase 4 from a clean dependency state, reconciled the documentation against the running code, and recorded the handoff Phase 5 will use. The only file changes outside documentation are none.

As throughout Phase 4, every claim here rests on **local Node.js execution evidence**, which is a different and weaker claim than the SAP runtime evidence behind Phases 1–3. Nothing in Phase 4 has ever run in or against an SAP system, and no supplier decision has been sent anywhere.

## Final Phase 4 architecture

```text
                    ┌──────────────────────────────────────────┐
   CI / Phase 5 ───▶ │ IntegrationService   /rest/integration/v1│  insert-only
                    │   POST /Orders  → receipt                │  no persistence exposed
                    └────────────────┬─────────────────────────┘
                                     │ custom CREATE handler
                                     ▼
                    ┌──────────────────────────────────────────┐
                    │ pih.portal   (SQLite local, portable CDS)│
                    │   Suppliers ─▶ Orders ─▶ OrderItems      │
                    │   DeliveryReceipts                       │
                    │   SupplierResponseDeliveries  (PENDING)  │
                    └────────────────▲─────────────────────────┘
                                     │ scoped reads + bound actions
                    ┌────────────────┴─────────────────────────┐
   Supplier   ────▶ │ SupplierService      /rest/supplier/v1   │  authenticated
   (browser)        │   GET Orders, Orders/{id}, .../items     │  row-filtered
                    │   POST .../accept |reject |updateEstim…  │
                    └────────────────▲─────────────────────────┘
                                     │ fetch()
                    ┌────────────────┴─────────────────────────┐
                    │ Supplier UI   /  (static, no framework)  │
                    └──────────────────────────────────────────┘
```

`HealthService` at `/health/ping` sits beside these as the Phase 4.1 startup proof.

## Clean-install verification

Executed with `node_modules` and `@cds-models` deleted first.

```text
$ npm ci
added 99 packages, and audited 211 packages in 30s
found 0 vulnerabilities

$ npm run typecheck
> cds-typer "*" --outputDirectory @cds-models
> tsc --noEmit
(no diagnostics, exit 0)

$ npx cds compile db --to sql
5 tables, 7 unique constraints

$ npm test
# tests 87   # suites 20   # pass 87   # fail 0
```

Reproducible from a clean dependency state: the type generation, the compile and the full suite all run from `npm ci` with no manual step.

## Test count and suite terminology

**87 tests, 20 suites.** The run prints **21 top-level entries**, which is not the same number, and the difference has caused wording drift in three guides.

`health.test.ts` contributes a standalone top-level `test()` rather than a `describe()`. Node's reporter prints it as entry 4 alongside the suites, so the printed entry numbering has run one ahead of the suite count since Phase 4.3. Confirmed from source — `describe()` counts per file are 3, **0**, 5, 6, 6, totalling 20.

| Phase | Tests | Suites | Printed entries |
| --- | --- | --- | --- |
| 4.2 | 9 | 3 | 4 |
| 4.3 | 37 | 8 | 9 |
| 4.4 | 63 | 14 | 15 |
| 4.5 | 87 | 20 | 21 |

The guides now say "entries" where they mean printed entries and reserve "suites" for `describe()` blocks. No recorded run output was altered.

## Regression matrix

Every Phase 4 capability, re-verified together on one clean build. Automated results are from the suite above; smoke results are from `npm start` and live HTTP.

| Phase | Capability | Result |
| --- | --- | --- |
| 4.1 | CAP boots, three services served | `serving HealthService / IntegrationService / SupplierService`, launched in 1897 ms |
| 4.1 | Health endpoint | `{"status":"UP","component":"cap-supplier-portal","phase":"4.1"}` — 200 |
| 4.2 | Persistence deploys | 5 tables, 7 unique constraints |
| 4.2 | Fixtures load, relationships work | suites 1–3 pass; composition cascades, association does not |
| 4.3 | New order ingestion | **201** with receipt |
| 4.3 | Exact replay | **200**, same `portalOrderId` |
| 4.3 | Conflicting replay | **409** `DELIVERY_PAYLOAD_CONFLICT` |
| 4.3 | Supplier resolution | **400** `UNKNOWN_SUPPLIER` |
| 4.3 | Source-order reuse under a new delivery | **409** `SOURCE_ORDER_ALREADY_INGESTED` |
| 4.3 | Validation boundary | **400** `TOTAL_AMOUNT_MISMATCH`, **400** `UNSUPPORTED_UNIT` |
| 4.3 | Transaction rollback | suite 7 — order write rolled back on the second-statement failure |
| 4.3 | Insert-only | `GET` → **405** |
| 4.4 | Anonymous access | **401** |
| 4.4 | Row isolation | SUP001 → `PO00001001`, `PO00001002`; SUP002 → `PO00001003` |
| 4.4 | Cross-supplier read | **404**, no fields |
| 4.4 | Cross-supplier decision | **404** `ORDER_NOT_FOUND` |
| 4.4 | Order and item reads | 200; items `MAT001`, `MAT002` |
| 4.4 | Accept | **200** `"status":"ACCEPTED","responseVersion":1` |
| 4.4 | Reject | **200**, `REJECTED` persisted |
| 4.4 | Estimated delivery date | **200**, version 1 → 2, decision stays `ACCEPTED` |
| 4.4 | `responseId` replay | **200**, original decision returned |
| 4.4 | Stale version | **409** `STALE_RESPONSE_VERSION` |
| 4.4 | Pending response | written `PENDING` with every decision |
| 4.4 | Atomicity | suite 15 — decision rolled back when the response write fails |
| 4.5 | UI assets | `/`, `/styles.css`, `/supplier-ui.mjs`, `/lib/order-view.mjs` → 200, correct content types |
| 4.5 | List, detail, actions | suites 16–21; browser-verified in Phase 4.5 |
| 4.5 | Stale handling | `refresh: true`, no automatic retry |
| 4.5 | Identity not browser-supplied | asserted structurally against the shipped script |
| 4.5 | Pagination | `limit=1` → 1 row; `limit=abc` → **400** `INVALID_PAGINATION` |

No test was rewritten to make this matrix pass.

## Contract reconciliation

Documented contract compared against the running code, route by route.

| Contract point | Documented | Implemented | Verdict |
| --- | --- | --- | --- |
| Integration route | `POST /rest/integration/v1/Orders` | same | matches |
| Ingestion DTO | nested `source{}`, `amount{}`, `lines[].product{}`, decimals as strings | same, kept nested by `cds.odata.structs` | matches |
| Receipt | `deliveryId`, `sourceOrderId`, `portalOrderId`, `status`, `receivedAt` | same; key set pinned by a test | matches |
| Receipt semantics | 201 new, 200 replay, 409 conflict | same | matches |
| `deliveryId` idempotency | database uniqueness, not read-before-insert | `UNIQUE (sourceSystem, deliveryId)` + normalized hash | matches |
| Source-order uniqueness | distinct rule, 409 with reconciliation reference | `UNIQUE (sourceSystem, sourceOrderId, sourceRevision)`; message names the original order and delivery | matches |
| Supplier routes | list, detail, `accept`, `reject`, `updateEstimatedDeliveryDate` | same paths | matches |
| Bound action wire shape | — | `POST /…/Orders/{key}/{action}`, flat JSON parameters, `returns` type as body | **resolved by Phase 4.4 evidence** |
| Supplier identity | authenticated user attributes, never a browser-supplied code | `req.user.attr.supplier`; asserted in both tiers | matches |
| Isolation semantics | "access denied or scoped not-found; no fields disclosed" | scoped **404** | matches, the discloses-nothing option |
| `responseVersion` | portal assigns the next atomically; precondition on new commands | `expectedResponseVersion` required; 409 when stale | matches |
| `responseId` replay | duplicate with same content is a no-op, opposite decision is a conflict | 200 replay / 409 `RESPONSE_PAYLOAD_CONFLICT` | matches |
| Pending response | `SupplierResponseDelivery` with identity, version, payload, state | implemented as a Phase 4.4 subset; `PENDING` only | matches, subset recorded |
| Pagination | "explicit parameters and result envelope, not OData syntax" | `?limit=`/`?offset=`, bare-array envelope, max 100 | **defined in 4.5**, recorded in API_CONTRACTS.md |
| Error envelope | `{ error: { code, message, correlationId, retryable } }` | same on both services | matches |

**No implementation defect was found.** Every mismatch encountered in this pass was documentation drift, and each is listed below.

### Documentation drift corrected in 4.6

1. **Suite terminology**, in the Phase 4.3 and 4.4 guides — printed entries were called suites. Reworded; no run output changed.
2. **Phase 4.3 guide described `SupplierService` as not existing.** True when written, false since Phase 4.4. Reworded.
3. **Phase 4.3 guide's "Phase 4.4 remains unimplemented"** with its 404 evidence. The 404s are preserved as the Phase 4.3 result and now framed as a checkpoint, noting that the same routes return 401 today.
4. **Phase 4.4 guide listed "no pagination" as an open limitation.** Resolved in Phase 4.5; marked as such.
5. **Phase 4.4 guide's supplier error-code count.** Phase 4.5 added `INVALID_PAGINATION`, making **14**, not the thirteen that was correct at 4.4. Noted in place.
6. **Both supplier route tables were incomplete.** `GET /rest/supplier/v1/OrderItems/{ID}` is served — `OrderItems` is an exposed `@readonly` projection with a key — and neither the Phase 4.4 nor the Phase 4.6 table listed it, so the documented count was seven where the runtime serves **eight**. Verified in this pass that it carries the same isolation as every other read: a supplier's own line returns 200, another supplier's line returns a scoped **404** with no fields, and an anonymous request returns 401, because the `before READ` hook on `OrderItems` narrows the query rather than the result. **Not a defect** — a documentation omission. Both tables now list it.

## Final persistence entities

Namespace `pih.portal`, 5 entities, 7 unique constraints:

| Entity | Purpose | Constraints |
| --- | --- | --- |
| `Suppliers` | portal supplier reference | `UNIQUE (supplierCode)` |
| `Orders` | received purchase-order snapshot | `UNIQUE (sourceSystem, sourceOrderId, sourceRevision)` |
| `OrderItems` | composed lines | `UNIQUE (order_ID, lineNumber)`, `UNIQUE (order_ID, sourceItemId)` |
| `DeliveryReceipts` | ingestion deduplication and the original receipt | `UNIQUE (sourceSystem, deliveryId)` |
| `SupplierResponseDeliveries` | pending outbound supplier response | `UNIQUE (responseId)`, `UNIQUE (order_ID, version)` |

Two of these — `DeliveryReceipts` and `SupplierResponseDeliveries` — were pulled forward from their documented Phase 5 slot, each carrying only the fields its subphase needed, each recorded as a deviation in the schema itself.

## Final public HTTP surfaces

| Surface | Methods | Auth |
| --- | --- | --- |
| `/health/ping` | `GET` | none |
| `/rest/integration/v1/Orders` | `POST` only; anything else **405** | none yet — Phase 8 |
| `/rest/supplier/v1/Orders` | `GET` with `limit`/`offset` | authenticated, row-filtered |
| `/rest/supplier/v1/Orders/{portalOrderId}` | `GET` | authenticated, scoped 404 |
| `/rest/supplier/v1/Orders/{portalOrderId}/items` | `GET` | authenticated, scoped 404 |
| `/rest/supplier/v1/OrderItems` | `GET` | authenticated, row-filtered |
| `/rest/supplier/v1/OrderItems/{ID}` | `GET` | authenticated, scoped 404 |
| `/rest/supplier/v1/Orders/{portalOrderId}/accept` | `POST` | authenticated |
| `/rest/supplier/v1/Orders/{portalOrderId}/reject` | `POST` | authenticated |
| `/rest/supplier/v1/Orders/{portalOrderId}/updateEstimatedDeliveryDate` | `POST` | authenticated |
| `/`, `/styles.css`, `/supplier-ui.mjs`, `/lib/order-view.mjs` | `GET` | none |

The supplier service serves **eight** routes: five `GET` reads and three `POST` bound actions, every one of them authenticated and row-filtered. **No persistence entity is writable through any service**, and `/odata/v4/…` returns 404: there is no generic CRUD surface over the database anywhere in the portal.

Application-defined error codes: **21 in `IntegrationService`** (20 reachable over HTTP, plus the internal `INVALID_PAYLOAD` guard) and **14 in `SupplierService`**.

## Final UI surface

One page at `/`: mock sign-in, a paged list of the caller's own orders, a detail view with items, and the three decision controls shown by lifecycle state. Plain HTML, CSS and ES modules — no framework, no build step, no runtime dependency. Presentation logic is isolated in `app/lib/order-view.mjs` as pure functions that the tests import directly.

## Security limitations

State them plainly, because none of them is subtle.

- **Authentication is mocked.** Basic auth against users in `.cdsrc.json`, over plain HTTP, with credentials held in `sessionStorage`. Isolation logic is enforced server-side and tested; identity assurance is not addressed at all. XSUAA, IAS and token validation are Phase 8.
- **The integration endpoint is unauthenticated.** `source.system` is checked for presence and shape, not "validated against the authenticated integration client" as the contract requires. Anyone who can reach the port can ingest.
- **No transport security.** Local HTTP only.
- **No authorization beyond supplier scoping.** There are no roles, and every authenticated supplier can do everything to its own orders.
- **The 256 KiB body bound is not enforced.** The 100-line bound is.

## Idempotency and concurrency guarantees

**Guaranteed, and verified.** A repeated `deliveryId` with identical content returns the original receipt and creates nothing. A repeated `responseId` with identical content returns the original decision and creates nothing. A reused identity with different content is refused and changes nothing. A stale `responseVersion` is refused. A decision and its pending response commit or roll back together, demonstrated by forcing the second write to fail. Order and lines commit or roll back together. The uniqueness rules that protect all of this are real database constraints, shown in the generated DDL.

**Not guaranteed, and not claimed.** No concurrent race was ever exercised. In Phase 4.3 the delivery race branch was instrumented and recorded **zero hits** across three runs, because a single local SQLite connection serializes the requests; the equivalent supplier-side race was not attempted. The constraints are what would hold these invariants under real write concurrency, and they are proven to fire — the atomicity test works by triggering one — but **the concurrent code paths themselves are reasoned, not exercised.** This needs re-testing on a database with genuine write concurrency.

## Open items

| Item | Status |
| --- | --- |
| OI-04 — CAP REST ingestion and supplier bound-action wire behaviour | **Closed**, and the closure still holds: both halves were executed over HTTP in Phases 4.3 and 4.4, and re-verified in the 4.6 smoke test above |
| OI-13 — RAP stale ETag / concurrency | **Open**, untouched by Phase 4 |
| RAP `__OperationControl` UX gap | **Open**, untouched by Phase 4 |
| Permissive RAP authorization study stub | **Open**, untouched by Phase 4 |
| `sendToSupplier` | **Phase 5**, not implemented |

### CAP-specific debt carried into Phase 5

1. **No concurrency has been raced** on either service, as described above.
2. **No authentication on the integration endpoint**, which Phase 5 will be the first real caller of.
3. **Decimals are stored through SQLite's `REAL_DECIMAL`.** Validation arithmetic is exact `BigInt`; storage is not. Column types differ on HANA and this deserves rechecking.
4. **HANA portability is an intention, not a fact.** Portable CDS types and CQN only, never verified against HANA.
5. **The uniqueness-violation translation matches on constraint names in the error text** — the most fragile line in the ingestion handler, and the thing most likely to break on a CAP upgrade.
6. **No `Location` header** on the ingestion 201, and no `GET /rest/integration/v1/DeliveryReceipts/{deliveryId}` operations endpoint, which the boundary table lists.
7. **`SupplierResponseDeliveries` has no attempt count or last error**, which a sender will need.
8. **No pagination on the item list**, deliberate, but worth revisiting if an order ever exceeds 100 lines.

## Phase 5 handoff

Phase 5 connects RAP and CAP. Phase 4 provides the CAP half; nothing below is new, and none of it is Phase 5 design.

**Outbound, SAP → CAP.** The dispatcher builds the nested mapped order and `POST`s it to `/rest/integration/v1/Orders`. On 201 it stores the receipt. On a timeout it **replays the same `deliveryId`**, and the 200-with-the-original-receipt is what makes that replay safe. A 409 means either the content changed under one delivery id or the source order was already ingested under another — both need reconciliation, never a blind retry.

**Inbound, CAP → SAP.** The sender reads `SupplierResponseDeliveries` rows in state `PENDING` and submits the supplier response DTO. Phase 4 writes those rows and never sends them; the transport state field exists so the sender can move a row beyond `PENDING`.

**Identifiers Phase 5 must carry**, all verified present:

| Identifier | Owner | Where it lives in CAP | Role in Phase 5 |
| --- | --- | --- | --- |
| `deliveryId` | dispatcher | `Orders.deliveryId`, `DeliveryReceipts.deliveryId` | idempotency key for one delivery attempt; replay it unchanged |
| `sourceSystem` | SAP | `Orders.sourceSystem` | scopes every deduplication key; never global |
| `sourceOrderId` | SAP | `Orders.sourceOrderId` | the SAP order identity, correlation only |
| `sourceRevision` | SAP | `Orders.sourceRevision` | a new revision is a different order and is accepted |
| `portalOrderId` | CAP | `Orders.ID`, returned in the receipt | what SAP stores to refer to the portal's copy |
| `responseId` | supplier client | `SupplierResponseDeliveries.responseId` | idempotency key for one supplier response |
| `responseVersion` | CAP | `Orders.responseVersion`, `SupplierResponseDeliveries.version` | ordering and conflict detection; a newer response must not be overwritten by an older one |

There are **no cross-database foreign keys**. The two systems correlate through `sourceSystem` + `sourceOrderId` + `sourceRevision` and through the two idempotency keys, exactly as the domain model specified before any of this existed.

## What Phase 4.6 did not do

No entity, route, handler, rule, UI control or behavioural test was added. The verification commands were run; the documentation was reconciled to what they showed. Phase 5 is not started.
