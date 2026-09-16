# CAP Supplier Portal

Phase 4 in progress. **Phase 4.1 (foundation and local runtime) and Phase 4.2 (persistence and domain model) are locally runtime-verified**: the project installs, typechecks, tests and starts; `Suppliers`, `Orders` and composed `OrderItems` deploy to SQLite with synthetic fixtures; and a TypeScript handler is served over the REST adapter. See the [Phase 4.1 guide](docs/phase-4-1-cap-foundation.md) and the [Phase 4.2 guide](docs/phase-4-2-domain-model.md).

No business API exists yet. The portal does not talk to SAP in Phase 4 and runs entirely on its own.

## Run it locally

```bash
cd cap-supplier-portal
npm ci
npm run typecheck
npm test
npm start
```

`npm start` serves on `http://localhost:4004`; `GET /health/ping` returns `{"status":"UP", ...}`. `npm run watch` gives a reloading development server. Node.js 22 or later is required.

`npm run typecheck` and `npm test` each regenerate the `#cds-models` types first, because that output is git-ignored. `npx cds compile db --to sql` prints the DDL the model deploys.

## What is here

- `db/`: [schema.cds](db/schema.cds) — namespace `pih.portal` with `Suppliers`, `Orders` and composed `OrderItems`, plus CSV fixtures in `db/data/`. This is the portal's own domain, deliberately not a copy of the SAP tables: `externalOrderNumber`, `productCode`, `lineNumber`, `unitPrice`, `lineAmount`, `uom` `PCE`, and no SAP organizational fields.
- `srv/`: `HealthService` only — one function, no entity, no persistence access. The integration-facing and supplier-facing services, with separate permissions, arrive in Phases 4.3 and 4.4.
- `test/`: the foundation test and the persistence tests. Both run against a real CAP server on an in-memory database.
- `app/`: empty. The minimal supplier interface — list orders, inspect items, submit decisions — arrives in Phase 4.5.

The entities are reachable by query and by nothing else: `/rest/supplier/v1/Orders` and `/odata/v4/Orders` both return 404, and the startup log shows `HealthService` as the only service served. That is the Phase 4.2 boundary.

## Pinned versions

`@sap/cds@10`, `@sap/cds-dk@10`, `@cap-js/sqlite@3`, `@cap-js/cds-typer@0`, TypeScript 5.9 and `tsx`, resolved exactly by the committed `package-lock.json`. Local development uses SQLite in memory; HANA Cloud compatibility stays an intention that must later be verified on HANA, so the model uses portable CDS types and every query is CQN rather than SQLite-specific SQL.

Business rules and API boundaries are in [architecture](../ARCHITECTURE.md), [contracts](../API_CONTRACTS.md) and the [domain model](../docs/architecture/domain-model.md), which is where the CAP field set is specified. SAP RAP owns the purchase-order lifecycle; this portal owns supplier-facing persistence and supplier decisions, and never becomes a second implementation of the SAP rules.
