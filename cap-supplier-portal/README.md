# CAP Supplier Portal

**Phase 7 CLOSED within recorded acceptance scope:** explicit flush atomically claims `PENDING` or expired `IN_FLIGHT` under a 60-second lease; `UNKNOWN` is never automatic and dry-run never claims. A deployed concurrent-drainer test had one owner, one skip and one attempt/history; an expired abandoned lease was reclaimed with one real attempt and then cleared. The read-only production reporter is `npm run operational-status:prod` and is runtime-proven. The CAP-to-iFlow timeout is 35,000 ms. The complete unchanged suite passed outside the Codex host: 231 tests in 44 suites, zero failures; typecheck and production CDS build passed. The earlier Windows `tsx` startup failure was host-only.

**Phase 4 is complete.** Subphases 4.1 (foundation), 4.2 (persistence), 4.3 (integration ingestion), 4.4 (supplier service) and 4.5 (supplier UI) are locally runtime-verified, and [Phase 4.6](docs/phase-4-6-closure.md) closed the phase with a clean-install re-verification and a contract reconciliation that found no implementation defect. See the [Phase 4.1](docs/phase-4-1-cap-foundation.md), [4.2](docs/phase-4-2-domain-model.md), [4.3](docs/phase-4-3-integration-ingestion.md), [4.4](docs/phase-4-4-supplier-service.md), [4.5](docs/phase-4-5-supplier-ui.md) and [4.6](docs/phase-4-6-closure.md) guides.

**The portal never talks to SAP directly, and after Phase 6 it still does not.** A supplier decision commits as a durable pending response, and an explicit sender drains it through SAP Integration Suite, which is the only mediation layer. Phase 6 is complete: acceptance, date update and rejection have all travelled CAP → Cloud Integration → SAP RAP for real.

**The portal is deployed to SAP BTP Cloud Foundry and authenticated runtime access is verified.** It runs at [`0badc38dtrial-dev-cap-supplier-portal-srv.cfapps.us10-003.hana.ondemand.com`](https://0badc38dtrial-dev-cap-supplier-portal-srv.cfapps.us10-003.hana.ondemand.com) on SAP HANA through the pre-existing `pih-hdi` container, with XSUAA enforcing two named roles. Every route is authenticated: an anonymous request gets 401. See [Deployed state](#deployed-state-sap-btp-cloud-foundry). **No business order has yet been written to HANA**, so HANA runtime behaviour is still unverified.

## Run it locally

```bash
cd cap-supplier-portal
npm ci
npm run typecheck
npm test
npm run watch
```

**`npm run watch` is the local TypeScript development command** — it runs `cds-tsx watch`, which registers the TypeScript runtime and reloads on change, and serves on `http://localhost:4004`. Node.js 22 or later is required.

**`npm start` is the production command, not the development one.** It runs `cds-serve` from `@sap/cds`, plain Node against the JavaScript that `cds build --production` precompiles, so it does **not** register a TypeScript runtime and will not load the `.ts` handlers from source. This used to be `cds-tsx serve`, and that is what broke the first deployment; see [Startup command](#startup-command-cds-serve-not-cds-tsx).

**`npm run flush-responses` is the Phase 6.5e supplier-response sender**, an explicit command rather than a scheduler or an HTTP route. `-- --dry-run` builds and prints the payloads without sending anything and without reading a credential; `-- --limit 1` attempts a single row. It refuses to run unconfigured rather than defaulting, and the three variables it needs — `PIH_CI_SUPPLIER_RESPONSE_URL`, `PIH_CI_CLIENT_ID` and `PIH_CI_CLIENT_SECRET` — are read from the environment only. **Never put those values in a tracked file.** Locally the command deploys the model into the in-memory SQLite database first, which is why a dry run works from a clean checkout; against the deployed application it uses the existing HANA binding and deploys nothing.

**`npm run reconcile-response -- --response-id <uuid>` resolves one `UNKNOWN` delivery** (Phase 6.5g). It replays that exact durable response through Cloud Integration under the same `responseId`, with a fresh correlation ID for the new attempt. It never reads SAP — RAP idempotency answers the question instead — refuses anything that is not `UNKNOWN`, makes exactly one attempt and never loops. It needs the same environment variables as the flush command.

`npm run typecheck` and `npm test` each regenerate the `#cds-models` types first, because that output is git-ignored. `npx cds compile db --to sql` prints the DDL the model deploys — note that it compiles the `db/` folder only, so it shows 5 tables; the whole model including the services compiles to 7 tables and 2 views.

## Production build (HANA)

The database is chosen **by CAP profile**, so the same source runs on SQLite locally and on SAP HANA in production:

```bash
npx cds env requires.db                      # -> kind sqlite, url :memory:
npx cds env requires.db --profile production # -> kind hana, impl @cap-js/hana
npx cds build --production                   # -> gen/db (HDI deployer) + gen/srv
```

Neither profile is configured by hand. `.cdsrc.json` deliberately says **nothing** about `db`: `@cap-js/sqlite` contributes `requires.db = "sql"` with `kinds.sql.[development]` resolving to SQLite `:memory:`, and `@cap-js/hana` contributes `kinds.sql.[production]` resolving to HANA. Pinning `requires.db` in the project file would apply to every profile and silently keep production on SQLite, which is exactly what it did before this step.

`cds build --production` emits a `db` build task `for: 'hana'` and writes `gen/db` as an HDI deployer module — `@sap/hdi-deploy` with the pure-JS `hdb` driver — containing 6 `.hdbtable`, 7 `.hdbindex`, 2 `.hdbview`, `.hdiconfig`, `.hdinamespace` and `undeploy.json`. The 6 tables are the five `pih.portal` entities plus CAP's own `cds.outbox.Messages`; the 7 indexes are the 7 `@assert.unique` rules rendered as `UNIQUE INVERTED INDEX`, so the constraints the idempotency guarantees rest on survive into HANA. **It contains no seed data at all** — no `.hdbtabledata` and no CSV — because the fixtures live in the development-only `test/data` folder described above, so deploying this build cannot load synthetic records into HANA. Decimals become real `DECIMAL(19,2)`, `DECIMAL(19,4)` and `DECIMAL(13,3)` columns rather than SQLite's `REAL_DECIMAL`.

`tsconfig.cdsbuild.json` exists only for this build. The `cds-typer` build plugin looks for that exact filename and, when it is missing, falls back to `tsc --outDir gen/srv`, which fails with `TS2210` because emitting against the `package.json` `imports` map needs a `rootDir`. It has no effect on `npm run typecheck` or `npm test`, which both use `tsconfig.json`.

This application **is deployed, bound and exercised** — see [Deployed state](#deployed-state-sap-btp-cloud-foundry) and [HANA runtime evidence](#hana-runtime-evidence-ingestion-path). The DDL above is no longer only *deployed*: one real order has been written to and read back from HANA, and the decimal columns round-tripped with their scale intact. Of the four OI-14 findings in [PROJECT_STATUS.md](../PROJECT_STATUS.md), **items 1, 2 and 3 are resolved** — the empty `IntegrationService.Orders` persistence artifact is gone, which took the table count from 7 to 6 and is now confirmed absent from the deployed HANA catalog; the fixture CSVs moved to `test/data`, which took the seed artifacts from 3 `.hdbtabledata` to none and is now confirmed by an empty container; and production authentication is enforced by XSUAA in the deployed runtime. **Item 4 is split: the HANA ingestion path is verified and the supplier decision/update path is open**, because every write exercised was an INSERT. The supplier attribute mapping also remains open.

## Deployed state (SAP BTP Cloud Foundry)

| | |
| --- | --- |
| Landscape | SAP BTP **Trial**, Cloud Foundry region **`us10-003`**, space **`dev`** |
| Application | `cap-supplier-portal-srv` — **started, 1/1 running**, `nodejs_buildpack`, Node 24 |
| Route | `https://0badc38dtrial-dev-cap-supplier-portal-srv.cfapps.us10-003.hana.ondemand.com` |
| Database | existing HDI container **`pih-hdi`** (`hana`/`hdi-shared`), bound to the app *and* to the deployer |
| Schema deployer | `cap-supplier-portal-db-deployer` — ran the HANA artifacts into that container |
| Authentication | real XSUAA instance **`cap-supplier-portal-auth`** (`xsuaa`/`application`), bound to the app |

**No duplicate database or container was created.** The `org.cloudfoundry.existing-service` resource in [mta.yaml](mta.yaml) held: there is still exactly one `hana-cloud` instance and one `hdi-shared` container in the space. `pih-xsuaa-probe` still exists from the earlier token experiment, is **bound to nothing** and is not an application dependency — it is cleanup debt.

### Authenticated runtime evidence

Anonymous requests are refused everywhere, because CAP with XSUAA restricts all services by default:

| Request | Result |
| --- | --- |
| `GET /health/ping` — no token | **401** |
| `POST /rest/integration/v1/Orders` — no token | **401** |
| `GET /rest/supplier/v1/Orders` — no token | **401** |

A real `client_credentials` token from `cap-supplier-portal-auth` carries `uaa.resource` and `<xsappname>.IntegrationClient`, and **does not carry `SupplierPortalUser`**. With that token:

| Request | Result |
| --- | --- |
| `GET /health/ping` | **200** — `{"status":"UP",…}` |
| `POST /rest/integration/v1/Orders` with `{}` | **400** `SCHEMA_VERSION_UNSUPPORTED`, in our own error envelope with a `correlationId` |
| `GET /rest/supplier/v1/Orders` | **403** — `User 'system' is lacking required roles: [SupplierPortalUser]` |

### HANA runtime evidence (ingestion path)

The deployed application resolves the production profile to **`HANAService`**. Inspected before any test data existed, the `pih-hdi` container held **0 rows** in `Suppliers`, `Orders`, `OrderItems` and `DeliveryReceipts` while all four tables existed and were queryable — the HDI deployment worked, and `test/data` really did keep the fixtures out of production. Because ingestion requires an active supplier, **one synthetic supplier** was created through a CAP-aware Cloud Foundry task over the application's own binding (not raw SQL, not a fixture CSV, not a code change, not a new endpoint): `supplierCode` **`RTTEST001`**, active. Deliveries use `sourceSystem` **`PIH_RUNTIME_TEST`**.

| Request (real `IntegrationClient` token) | Result |
| --- | --- |
| `POST /rest/integration/v1/Orders` — valid one-line order | **201**, receipt with `deliveryId`, `sourceOrderId`, `portalOrderId`, `status RECEIVED`, `receivedAt` |
| the same bytes again | **200** — same `portalOrderId`, **original** `receivedAt` |
| business-equivalent but byte-different (keys reordered, decimals with fewer trailing zeros) | **200** — same receipt, so the replay hash is over a normalized projection, not raw bytes |
| changed payload, same `deliveryId` | **409** `DELIVERY_PAYLOAD_CONFLICT`, stored order unchanged |

Persistence was then verified in HANA directly rather than inferred from the 201: exactly **one Order**, **one OrderItem** and **one DeliveryReceipt**, the supplier association resolving through an expanded read, `sourceSystem`/`sourceOrderId`/`sourceRevision` as sent, server-owned `status RECEIVED` and `responseVersion 0`, and **decimal scale and Timestamp precision intact** — `37.50`, `3.000` and `12.5000` returned with scale preserved and no float drift, and `receivedAt` keeping millisecond precision. The stored `requestHash` matched the hash computed locally before the request was sent. Counts stayed **1 Order / 1 Item / 1 Receipt** across all four requests, and the final read was byte-identical to the first **including `modifiedAt`**, so no UPDATE touched the row either.

The container's catalog lists six tables — the five `pih.portal` entities plus CAP's framework `cds.outbox.Messages` — and **no `IntegrationService.Orders` table**, which runtime-confirms the `@cds.persistence.skip` design. **No HANA-specific runtime defect was found.**

**Not verified:** the supplier decision/update path against HANA, because every write exercised was an INSERT — the accept/reject UPDATE, the `responseVersion` increment, the `@cds.on.update: $now` behaviour of `modifiedAt` and `SupplierResponseDeliveries` persistence are all untested — plus the interactive `SupplierPortalUser` identity and the `supplier` → `req.user.attr.supplier` mapping.

The synthetic supplier, order, item and receipt **remain in Trial `dev` on purpose** as labelled runtime-test data. `DeliveryReceipts.order` is an association rather than a composition, so deleting the order would orphan the receipt and the referential effect was not established; deleting the receipt would destroy the idempotency record and make that `deliveryId` re-ingestable. `runtime-test-key` on the XSUAA instance and the unbound `pih-xsuaa-probe` remain cleanup debt.

The 400 is the decisive one: it is not a framework rejection but `srv/lib/ingestion.ts` compiled and running in the cloud, which proves the request cleared XSUAA, cleared the `IntegrationClient` check and entered the handler. Nothing was persisted, because `schemaVersion` is the first validation in `normalizeDelivery`. The 403 proves the two surfaces stay isolated in the deployed app: the token that reaches ingestion cannot read supplier data.

No token, client id, client secret or service-key content is recorded in this repository.

## Startup command: `cds-serve`, not `cds-tsx`

The first deployment staged cleanly and then crashed with `sh: 1: cds-tsx: not found`, exit 127. `cds-tsx` is declared only by `@sap/cds-dk`, a `devDependency`, so the production install does not contain it — and its shebang is `#!/usr/bin/env tsx`, needing a second devDependency even if it were present. `cds-serve` comes from `@sap/cds`, a production dependency, and is plain Node. It is sufficient because `cds build --production` precompiles every handler: `gen/srv` contains compiled `.js` and **zero `.ts`**. The fix was one word in `package.json`, and `gen/srv/package.json` inherits it.

### Deliver an order

```bash
curl -i -X POST http://localhost:4004/rest/integration/v1/Orders \
  -H 'Content-Type: application/json' \
  -d '{"schemaVersion":"1.0","deliveryId":"0e7df7c7-2427-4700-a7bb-63aa9f1a11af","source":{"system":"PIH_ABAP_DEV","orderId":"82e96537-4ecc-4c34-b2c3-e75486329447","orderNumber":"PO000001","revision":1},"supplierCode":"SUP001","amount":{"currency":"EUR","value":"1500.00"},"lines":[{"sourceItemId":"77418462-e8d8-4d60-b5fd-98510b5d90b0","lineNumber":10,"product":{"code":"MAT001","description":"Laptop"},"orderedQuantity":{"value":"2.000","unit":"PCE"},"unitPrice":{"currency":"EUR","value":"750.0000"},"lineAmount":"1500.00"}]}'
```

`201` with a receipt the first time. Send it again unchanged and it is `200` with the *same* receipt. Change the quantity but keep the `deliveryId` and it is `409` with the stored order untouched. `GET /health/ping` reports that the runtime is up.

### Use the supplier UI

Open `http://localhost:4004/` and sign in as `supplier1` (SUP001) or `supplier2` (SUP002); the password matches the user name. You will see only that supplier's orders, can open one to read its lines, and can accept, reject or revise the delivery date. **This is local mock sign-in, not production authentication** — the banner on the page says so, and the supplier is derived server-side from the signed-in user.

### Act as a supplier

```bash
curl -u supplier1:supplier1 http://localhost:4004/rest/supplier/v1/Orders

curl -u supplier1:supplier1 -X POST \
  http://localhost:4004/rest/supplier/v1/Orders/22222222-2222-4222-8222-000000000001/accept \
  -H 'Content-Type: application/json' \
  -d '{"responseId":"7f135926-34af-4eb2-a8b3-1b851303afc9","expectedResponseVersion":0,"estimatedDeliveryDate":"2026-12-01"}'
```

`supplier1` is `SUP001` and `supplier2` is `SUP002`, mapped in `.cdsrc.json` under the `[development]` profile. Each sees only its own orders; another supplier's order id returns 404. **This is local supplier isolation, not production authentication** — real interactive identity is Phase 8.

Delivering an order also needs a role now. The ingestion endpoint is no longer open: send it as `sapintegration`, the mocked stand-in for SAP's technical client, which in production is an XSUAA scope on a client-credentials token.

```bash
curl -i -u sapintegration:sapintegration -X POST http://localhost:4004/rest/integration/v1/Orders ...
```

## Production authentication (runtime-verified in the deployed app)

Authentication is chosen by profile, the same way the database is:

```bash
npx cds env requires.auth                      # -> kind: mocked, with the four mock users
npx cds env requires.auth --profile production # -> kind: xsuaa, and no `users` key at all
```

Two named application roles, not CAP's `authenticated-user` pseudo-role:

| Role | Grants | Caller |
| --- | --- | --- |
| `SupplierPortalUser` | `/rest/supplier/v1` | a person at a supplier |
| `IntegrationClient` | `/rest/integration/v1` | SAP's technical client |

The pseudo-role was wrong twice over: CAP's generator skips it, so it produced no XSUAA scope, and a client-credentials token *is* an authenticated user — it would have granted SAP's integration client the supplier read surface. [xs-security.json](xs-security.json) is generated from these annotations with `npx cds compile srv --to xsuaa`.

**One thing needed real cloud evidence.** A scope plus a role-template does **not** put that scope into the application's own `client_credentials` token — a probe against a temporary XSUAA instance returned only `uaa.resource`. Top-level `authorities: ["$XSAPPNAME.IntegrationClient"]` is the same-application mechanism, and with it the token carries the resolved `IntegrationClient` scope while `SupplierPortalUser` stays absent. Role-templates serve interactive users through role-collections; `authorities` serves the app's own client. `SupplierPortalUser` is deliberately excluded from `authorities`, because including it would give every machine token the supplier surface.

`xsappname` is deliberately **not** in the tracked descriptor — the deployment descriptor owns the application identity. Note that `cf create-service` refuses a descriptor without one.

**Now verified in the deployed application**, not just at token level: a real token satisfies `@requires: 'IntegrationClient'` over HTTP and reaches the handler, anonymous access is refused 401, and the same token is refused 403 on the supplier surface. See [Authenticated runtime evidence](#authenticated-runtime-evidence). OI-14 item 2 is **resolved**.

**Still unverified:** the `supplier` → `req.user.attr.supplier` mapping, which needs an interactive login with a role-collection assignment — a client-credentials token has no user, so it structurally cannot test this — and SAP S/4 is not yet configured to fetch or send a token.

## What is here

- `db/`: [schema.cds](db/schema.cds) — namespace `pih.portal` with `Suppliers`, `Orders`, composed `OrderItems`, `DeliveryReceipts`, `SupplierResponseDeliveries` and, since Phase 7.3, the composed `SupplierResponseDeliveryAttempts` history child. The portal's own domain, deliberately not a copy of the SAP tables: `externalOrderNumber`, `productCode`, `lineNumber`, `unitPrice`, `lineAmount`, `uom` `PCE`, and no SAP organizational fields. The folder holds the model only — **no seed data**, deliberately; see `test/data/` below.
- `srv/`: [integration-service.cds](srv/integration-service.cds) — the CI → CAP ingestion boundary; [supplier-service.cds](srv/supplier-service.cds) — the supplier read model and the bound `accept`/`reject`/`updateEstimatedDeliveryDate` actions; plus `HealthService` from Phase 4.1. `srv/lib/` holds exact decimal arithmetic, the contract validation and, since Phase 6.5e, the supplier-response sender: `supplier-response.ts` (the frozen wire payload and the delivery classification, as pure functions), `ci-transport.ts` (the only file that opens a socket or reads a credential) and `response-sender.ts` (reads the outbox, sends, classifies, records). **Since Phase 7.3 `record()` also appends one `SupplierResponseDeliveryAttempts` row, inside the same transaction as the guarded parent update and only when that update matched** — a compare-and-set loser writes none, and a dry run writes nothing at all. `supplier-response.ts` gained `categorise()` beside the unchanged `classify()`: the first answers *why* an attempt ended (`NONE` / `REFUSED` / `TRANSIENT` / `AMBIGUOUS` / `NO_ANSWER` / `PAYLOAD`), the second still answers what the row's durable state becomes. That history is **inbound CAP → SAP attempts only**; SAP's own `AttemptCount` counts outbound attempts and the two are never added together.
- `scripts/`: [flush-supplier-responses.ts](scripts/flush-supplier-responses.ts) — the explicit Phase 6.5e flush command — and [reconcile-supplier-response.ts](scripts/reconcile-supplier-response.ts), the Phase 6.5g command that resolves one `UNKNOWN` delivery by replaying it under its existing `responseId`. Both are compiled into `gen/srv/scripts/` by the production build so they can run as Cloud Foundry tasks over the application’s existing bindings.
- `test/`: the foundation, persistence, ingestion, supplier-service, UI, supplier-response-sender and attempt-history suites — **159 tests in 37 suites**, all driven through a running CAP application. `test/data/` holds the three CSV fixtures, and the folder is the point: CAP resolves seed folders **per profile**, reading `db/data`, `db/csv` *and* `test/data` under `[development]` but only the first two under `[production]`. So `test/data` is **intentionally development-only** and its rows are excluded from the production HANA build, while local development and the tests load them exactly as before.
- `app/`: the supplier UI — plain HTML, CSS and ES modules, no framework and no build step, served by CAP at `http://localhost:4004/`. [lib/order-view.mjs](app/lib/order-view.mjs) holds the presentation logic as pure functions, which the tests import directly.

**No writable persistence path is exposed by any service.** `IntegrationService.Orders` is a service-local contract shape with `@insertonly`, so `GET` on it returns 405. The supplier projections are `@readonly` with explicit element lists and a row filter, so `PATCH` and `DELETE` return 405 and no foreign key or SAP correlation field reaches a supplier. `/odata/v4/Orders` returns 404: there is no generic CRUD surface over the database.

That statement is about the **service surface**. It used not to cover the persistence layer, and now it does. Because `IntegrationService.Orders` is an entity definition with its own elements rather than a projection, the compiler persisted it by default and the HANA build rendered `IntegrationService.Orders.hdbtable` — a permanently empty table, since the CREATE handler maps every delivery into `pih.portal`. It now carries **`@cds.persistence.skip`**, so no such artifact is generated.

The annotation fits this entity because it has **no persistence semantics at all**: it is never read, queried, navigated to or written, and its key exists to carry the caller's `deliveryId` for idempotency rather than to identify a stored row. The table was therefore not just unused but unusable, and deploying it would have advertised a persistence path the design exists to deny. `@insertonly` and `@readonly` say who may call a route; only `@cds.persistence.skip` says whether something is stored. It was verified against `@sap/cds-compiler` 7.1.1 before being applied — the annotation is handled in `lib/transform/db/cdsPersistence.js` and the OData/EDM transform never consults it — and the entity stays in the contract with **byte-identical** generated OData metadata. See ADR-034 in [ARCHITECTURE.md](../ARCHITECTURE.md#architecture-decision-register).

## Pinned versions

`@sap/cds@10`, `@sap/cds-dk@10`, `@cap-js/sqlite@3`, `@cap-js/hana@3`, `@cap-js/cds-typer@0`, TypeScript 5.9 and `tsx`, resolved exactly by the committed `package-lock.json`. Local development uses SQLite in memory and production runs on HANA Cloud, where **the ingestion path is runtime-verified and the supplier decision/update path is not** — see [HANA runtime evidence](#hana-runtime-evidence-ingestion-path). The model therefore continues to use portable CDS types and every query is CQN rather than SQLite-specific SQL, which is what let the same source serve both databases unchanged.

`.cdsrc.json` sets `cds.odata.structs: true`. That is not cosmetic: without it CAP flattens structured elements and the documented nested request body is rejected.

Business rules and API boundaries are in [architecture](../ARCHITECTURE.md), [contracts](../API_CONTRACTS.md) and the [domain model](../docs/architecture/domain-model.md), which is where the CAP field set is specified. SAP RAP owns the purchase-order lifecycle; this portal owns supplier-facing persistence and supplier decisions, and never becomes a second implementation of the SAP rules.
