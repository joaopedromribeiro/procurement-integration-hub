# CAP Supplier Portal

Phase 4 in progress. **Phase 4.1, the project foundation and local runtime, is locally runtime-verified**: the project installs, typechecks, tests and starts, and serves a TypeScript handler over the REST adapter. See the [Phase 4.1 guide](docs/phase-4-1-cap-foundation.md).

No business model and no business API exist yet. The portal does not talk to SAP in Phase 4 and runs entirely on its own.

## Run it locally

```bash
cd cap-supplier-portal
npm ci
npm run typecheck
npm test
npm start
```

`npm start` serves on `http://localhost:4004`; `GET /health/ping` returns `{"status":"UP", ...}`. `npm run watch` gives a reloading development server. Node.js 22 or later is required.

## What is here

- `srv/`: `HealthService` only — one function, no entity, no persistence. It exists to prove the runtime boots and to confirm the REST adapter. The real integration-facing and supplier-facing services arrive in Phases 4.3 and 4.4 with separate permissions.
- `test/`: the foundation test that boots the project and calls the endpoint over HTTP.
- `db/`: empty. Suppliers, Orders and composed OrderItems, with synthetic fixtures, arrive in Phase 4.2.
- `app/`: empty. The minimal supplier interface — list orders, inspect items, submit decisions — arrives in Phase 4.5.

`npx cds compile srv --to sql` currently produces no output, because there are no entities. That is the accurate picture of Phase 4.1.

## Pinned versions

`@sap/cds@10`, `@sap/cds-dk@10`, `@cap-js/sqlite@3`, TypeScript 5.9 and `tsx`, resolved exactly by the committed `package-lock.json`. Local development uses SQLite in memory; HANA Cloud compatibility stays an intention that must later be verified on HANA, so the domain model uses portable CDS types and CQN queries rather than SQLite-specific SQL.

Business rules and API boundaries are in [architecture](../ARCHITECTURE.md) and [contracts](../API_CONTRACTS.md). SAP RAP owns the purchase-order lifecycle; this portal owns supplier-facing persistence and supplier decisions, and never becomes a second implementation of the SAP rules.
