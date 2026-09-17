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

`cds build --production` emits a `db` build task `for: 'hana'` and writes `gen/db` as an HDI deployer module — `@sap/hdi-deploy` with the pure-JS `hdb` driver — containing 7 `.hdbtable`, 7 `.hdbindex`, 2 `.hdbview`, the fixture `.hdbtabledata`, `.hdiconfig`, `.hdinamespace` and `undeploy.json`. The 7 indexes are the 7 `@assert.unique` rules rendered as `UNIQUE INVERTED INDEX`, so the constraints the idempotency guarantees rest on survive into HANA. Decimals become real `DECIMAL(19,2)`, `DECIMAL(19,4)` and `DECIMAL(13,3)` columns rather than SQLite's `REAL_DECIMAL`.

`tsconfig.cdsbuild.json` exists only for this build. The `cds-typer` build plugin looks for that exact filename and, when it is missing, falls back to `tsc --outDir gen/srv`, which fails with `TS2210` because emitting against the `package.json` `imports` map needs a `rootDir`. It has no effect on `npm run typecheck` or `npm test`, which both use `tsconfig.json`.

**Nothing has been deployed and nothing is bound.** `pih-hana` and `pih-hdi` exist in BTP Cloud Foundry space `dev`, but this application has never connected to HANA, so the generated DDL above has been *read*, not *run*. Four findings are open and must be settled before any deployment — a physical persistence artifact for `IntegrationService.Orders`, mocked authentication carried into the production build, fixture CSVs in the deployment output, and unverified HANA runtime behaviour. They are recorded in [PROJECT_STATUS.md](../PROJECT_STATUS.md) under OI-14.

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

`supplier1` is `SUP001` and `supplier2` is `SUP002`, mapped in `.cdsrc.json`. Each sees only its own orders; another supplier's order id returns 404. **This is local supplier isolation, not production authentication** — real identity is Phase 8.

## What is here

- `db/`: [schema.cds](db/schema.cds) — namespace `pih.portal` with `Suppliers`, `Orders`, composed `OrderItems`, `DeliveryReceipts` and `SupplierResponseDeliveries`, plus CSV fixtures in `db/data/`. The portal's own domain, deliberately not a copy of the SAP tables: `externalOrderNumber`, `productCode`, `lineNumber`, `unitPrice`, `lineAmount`, `uom` `PCE`, and no SAP organizational fields.
- `srv/`: [integration-service.cds](srv/integration-service.cds) — the CI → CAP ingestion boundary; [supplier-service.cds](srv/supplier-service.cds) — the supplier read model and the bound `accept`/`reject`/`updateEstimatedDeliveryDate` actions; plus `HealthService` from Phase 4.1. `srv/lib/` holds exact decimal arithmetic and the contract validation.
- `test/`: the foundation, persistence, ingestion, supplier-service and UI suites — 87 tests, all driven through a running CAP application.
- `app/`: the supplier UI — plain HTML, CSS and ES modules, no framework and no build step, served by CAP at `http://localhost:4004/`. [lib/order-view.mjs](app/lib/order-view.mjs) holds the presentation logic as pure functions, which the tests import directly.

**No writable persistence path is exposed by any service.** `IntegrationService.Orders` is a service-local contract shape with `@insertonly`, so `GET` on it returns 405. The supplier projections are `@readonly` with explicit element lists and a row filter, so `PATCH` and `DELETE` return 405 and no foreign key or SAP correlation field reaches a supplier. `/odata/v4/Orders` returns 404: there is no generic CRUD surface over the database.

That statement is about the **service surface**, and it holds. It is not a statement about the persistence layer: because `IntegrationService.Orders` is an entity definition with its own elements rather than a projection, the compiler gives it a table, which the HANA production build renders as `IntegrationService.Orders.hdbtable`. Nothing reads or writes that table — the CREATE handler maps into `pih.portal` — so it would deploy as a permanently empty table. This is database-agnostic and pre-existing, not a HANA effect: the same table appears when the whole model is compiled for SQLite. `@cds.persistence.skip` is the likely answer and is deliberately **not** applied yet, because it edits a runtime-verified service contract. Tracked as OI-14 in [PROJECT_STATUS.md](../PROJECT_STATUS.md).

## Pinned versions

`@sap/cds@10`, `@sap/cds-dk@10`, `@cap-js/sqlite@3`, `@cap-js/hana@3`, `@cap-js/cds-typer@0`, TypeScript 5.9 and `tsx`, resolved exactly by the committed `package-lock.json`. Local development uses SQLite in memory and production is configured for HANA Cloud, but **HANA runtime behaviour remains unverified** — the application has never run against HANA — so the model continues to use portable CDS types and every query is CQN rather than SQLite-specific SQL.

`.cdsrc.json` sets `cds.odata.structs: true`. That is not cosmetic: without it CAP flattens structured elements and the documented nested request body is rejected.

Business rules and API boundaries are in [architecture](../ARCHITECTURE.md), [contracts](../API_CONTRACTS.md) and the [domain model](../docs/architecture/domain-model.md), which is where the CAP field set is specified. SAP RAP owns the purchase-order lifecycle; this portal owns supplier-facing persistence and supplier decisions, and never becomes a second implementation of the SAP rules.
