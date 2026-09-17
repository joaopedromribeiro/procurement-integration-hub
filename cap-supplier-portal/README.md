# CAP Supplier Portal

**Phase 4 is complete.** Subphases 4.1 (foundation), 4.2 (persistence), 4.3 (integration ingestion), 4.4 (supplier service) and 4.5 (supplier UI) are locally runtime-verified, and [Phase 4.6](docs/phase-4-6-closure.md) closed the phase with a clean-install re-verification and a contract reconciliation that found no implementation defect. See the [Phase 4.1](docs/phase-4-1-cap-foundation.md), [4.2](docs/phase-4-2-domain-model.md), [4.3](docs/phase-4-3-integration-ingestion.md), [4.4](docs/phase-4-4-supplier-service.md), [4.5](docs/phase-4-5-supplier-ui.md) and [4.6](docs/phase-4-6-closure.md) guides.

The portal does not talk to SAP: supplier decisions are stored as pending outbound responses and nothing is sent. Phase 5 connects the two systems and is open at 5.1, design only.

**Cloud deployment preparation has started.** The database is now selected by CAP profile — SQLite `:memory:` locally, SAP HANA in production — and `cds build --production` produces an HDI deployer. Nothing is deployed, nothing is bound, and no HANA runtime behaviour is verified; see [Production build (HANA)](#production-build-hana).

## Run it locally

```bash
cd cap-supplier-portal
npm ci
npm run typecheck
npm test
npm start
```

`npm start` serves on `http://localhost:4004`. `npm run watch` gives a reloading development server. Node.js 22 or later is required.

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

**Nothing has been deployed and nothing is bound.** `pih-hana` and `pih-hdi` exist in BTP Cloud Foundry space `dev`, but this application has never connected to HANA, so the generated DDL above has been *read*, not *run*. **Two findings remain open** and must be settled before any deployment — authentication, now **partially resolved** (mocked auth can no longer resolve in production and the `IntegrationClient` authority is token-level proven, but deployed enforcement and the supplier attribute mapping are not), and unverified HANA runtime behaviour. They are recorded in [PROJECT_STATUS.md](../PROJECT_STATUS.md) under OI-14, whose **items 1 and 3 are resolved**: the empty persistence artifact the build once generated for `IntegrationService.Orders` is gone, which took the table count from 7 to 6, and the fixture CSVs moved to `test/data`, which took the seed artifacts from 3 `.hdbtabledata` to none. Both are facts about what the build emits; neither is evidence about HANA.

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

## Production authentication (prepared, not runtime-verified)

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

**Still unverified:** CAP is not deployed, so no real token has satisfied `@requires: 'IntegrationClient'` over HTTP; the `supplier` → `req.user.attr.supplier` mapping needs an interactive token, which a technical token cannot provide; and SAP S/4 is not configured to fetch or send a token. Tracked as OI-14 item 2 in [PROJECT_STATUS.md](../PROJECT_STATUS.md), **partially resolved and still open**.

## What is here

- `db/`: [schema.cds](db/schema.cds) — namespace `pih.portal` with `Suppliers`, `Orders`, composed `OrderItems`, `DeliveryReceipts` and `SupplierResponseDeliveries`. The portal's own domain, deliberately not a copy of the SAP tables: `externalOrderNumber`, `productCode`, `lineNumber`, `unitPrice`, `lineAmount`, `uom` `PCE`, and no SAP organizational fields. The folder holds the model only — **no seed data**, deliberately; see `test/data/` below.
- `srv/`: [integration-service.cds](srv/integration-service.cds) — the CI → CAP ingestion boundary; [supplier-service.cds](srv/supplier-service.cds) — the supplier read model and the bound `accept`/`reject`/`updateEstimatedDeliveryDate` actions; plus `HealthService` from Phase 4.1. `srv/lib/` holds exact decimal arithmetic and the contract validation.
- `test/`: the foundation, persistence, ingestion, supplier-service and UI suites — 87 tests, all driven through a running CAP application. `test/data/` holds the three CSV fixtures, and the folder is the point: CAP resolves seed folders **per profile**, reading `db/data`, `db/csv` *and* `test/data` under `[development]` but only the first two under `[production]`. So `test/data` is **intentionally development-only** and its rows are excluded from the production HANA build, while local development and the tests load them exactly as before.
- `app/`: the supplier UI — plain HTML, CSS and ES modules, no framework and no build step, served by CAP at `http://localhost:4004/`. [lib/order-view.mjs](app/lib/order-view.mjs) holds the presentation logic as pure functions, which the tests import directly.

**No writable persistence path is exposed by any service.** `IntegrationService.Orders` is a service-local contract shape with `@insertonly`, so `GET` on it returns 405. The supplier projections are `@readonly` with explicit element lists and a row filter, so `PATCH` and `DELETE` return 405 and no foreign key or SAP correlation field reaches a supplier. `/odata/v4/Orders` returns 404: there is no generic CRUD surface over the database.

That statement is about the **service surface**. It used not to cover the persistence layer, and now it does. Because `IntegrationService.Orders` is an entity definition with its own elements rather than a projection, the compiler persisted it by default and the HANA build rendered `IntegrationService.Orders.hdbtable` — a permanently empty table, since the CREATE handler maps every delivery into `pih.portal`. It now carries **`@cds.persistence.skip`**, so no such artifact is generated.

The annotation fits this entity because it has **no persistence semantics at all**: it is never read, queried, navigated to or written, and its key exists to carry the caller's `deliveryId` for idempotency rather than to identify a stored row. The table was therefore not just unused but unusable, and deploying it would have advertised a persistence path the design exists to deny. `@insertonly` and `@readonly` say who may call a route; only `@cds.persistence.skip` says whether something is stored. It was verified against `@sap/cds-compiler` 7.1.1 before being applied — the annotation is handled in `lib/transform/db/cdsPersistence.js` and the OData/EDM transform never consults it — and the entity stays in the contract with **byte-identical** generated OData metadata. See ADR-034 in [ARCHITECTURE.md](../ARCHITECTURE.md#architecture-decision-register).

## Pinned versions

`@sap/cds@10`, `@sap/cds-dk@10`, `@cap-js/sqlite@3`, `@cap-js/hana@3`, `@cap-js/cds-typer@0`, TypeScript 5.9 and `tsx`, resolved exactly by the committed `package-lock.json`. Local development uses SQLite in memory and production is configured for HANA Cloud, but **HANA runtime behaviour remains unverified** — the application has never run against HANA — so the model continues to use portable CDS types and every query is CQN rather than SQLite-specific SQL.

`.cdsrc.json` sets `cds.odata.structs: true`. That is not cosmetic: without it CAP flattens structured elements and the documented nested request body is rejected.

Business rules and API boundaries are in [architecture](../ARCHITECTURE.md), [contracts](../API_CONTRACTS.md) and the [domain model](../docs/architecture/domain-model.md), which is where the CAP field set is specified. SAP RAP owns the purchase-order lifecycle; this portal owns supplier-facing persistence and supplier decisions, and never becomes a second implementation of the SAP rules.
