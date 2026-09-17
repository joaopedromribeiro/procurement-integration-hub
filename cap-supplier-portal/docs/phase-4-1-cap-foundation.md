# Phase 4.1 — CAP project foundation and local runtime

Status: **locally runtime-verified.** `npm ci`, `npm run typecheck`, `npm test` and `npm start` were executed on this machine and their output is reproduced below. This is local Node.js execution evidence, which is a different and weaker claim than the SAP runtime evidence behind Phases 1–3: nothing here was run in or against an SAP system, and Phase 4 makes no contact with SAP at all.

No ABAP source, CDS view, behavior definition, metadata extension, service definition, test class or persistence object was touched. Phase 3 remains complete and SAP runtime-verified.

## Purpose

Establish a CAP project that boots, serves a TypeScript handler and can be tested locally — and nothing else. The supplier-portal domain model and its two business APIs are deliberately absent, so that a failure in a later subphase is attributable to that subphase rather than to the toolchain underneath it.

## Architecture boundary

Phase 4 integrates with nothing. It builds one independently runnable application.

| Owner | Responsibility | Not allowed to |
| --- | --- | --- |
| SAP RAP | Procurement and commercial rules: the purchase-order lifecycle, approvals, numbering, immutability | — |
| CAP Supplier Portal | Supplier-facing persistence, supplier decisions, the receipt and response record | Re-implement the SAP purchase-order lifecycle, or edit SAP-owned commercial data |

This restates ADR-004. The portal receives immutable snapshots and records what a supplier decided about them; it never becomes a second authority on what an order *is*. The CAP entities arriving in Phase 4.2 are therefore shaped by the ingestion contract in [API_CONTRACTS.md](../../API_CONTRACTS.md), not by the ABAP tables — no CAP definition may mirror `ZJP_PO_H` or `ZJP_PO_I` field for field, because a portable portal schema and an SAP persistence layout are different artifacts that merely overlap.

Phase 5 connects RAP and CAP directly. Phase 6 inserts Integration Suite between them. Neither is anticipated in source here.

## Phase 4 subphase plan

| Subphase | Scope | Completion gate |
| --- | --- | --- |
| **4.1** | CAP project foundation and local runtime. Manifest, pinned dependencies, TypeScript, local persistence configuration, scripts, one non-business health service | Install, typecheck, test and server start all succeed locally — **this document** |
| 4.2 | Persistence and domain model: `Suppliers`, `Orders`, composed `OrderItems`, portable CDS types, synthetic fixtures | Model deploys to local SQLite; fixtures load; generated types are available to handlers |
| 4.3 | Integration-facing ingestion: the `POST /rest/integration/v1/Orders` contract, a custom CREATE handler over the structured DTO, `deliveryId` deduplication and the receipt response | A new delivery is stored and returns a receipt; a replay of the same `deliveryId` returns the original receipt rather than a second order |
| 4.4 | Supplier-facing read and decision API: supplier-filtered list and detail, `accept`, `reject`, `updateEstimatedDeliveryDate`, and row-level supplier isolation | A supplier sees only their own orders; a decision and its pending response commit together; rejection is recorded as a business outcome |
| 4.5 | Minimal supplier UI over the Phase 4.4 service | A supplier can list orders, inspect items and submit a decision through a browser |
| 4.6 | Phase 4 closure: coverage across ingestion, decisions and isolation; documentation and evidence | The full local suite passes from a clean checkout; OI-04 is closed or restated with what remains |

The boundaries follow this repository's existing contracts rather than a generic CAP tutorial order. Ingestion and the supplier surface are separated at 4.3 and 4.4 because [ARCHITECTURE.md](../../ARCHITECTURE.md) requires the integration-facing and supplier-facing services to stay separable with distinct permissions; merging them into one subphase would make that separation an afterthought. Supplier isolation stays inside 4.4 rather than becoming its own subphase, because a read surface that is not supplier-scoped is not a half-finished feature — it is a wrong one.

OI-04, "CAP REST structured ingestion and bound-action wire behavior", is answered by 4.3 and 4.4 and stays open until then.

## Created files

| File | Role |
| --- | --- |
| [package.json](../package.json) | Manifest, pinned dependency ranges, the four local scripts |
| [package-lock.json](../package-lock.json) | Exact resolved versions, committed so the foundation is reproducible |
| [.cdsrc.json](../.cdsrc.json) | CAP configuration: local persistence only |
| [tsconfig.json](../tsconfig.json) | TypeScript configuration, including the `#cds-models/*` path Phase 4.2 will need |
| [srv/health-service.cds](../srv/health-service.cds) | The single non-business service definition |
| [srv/health-service.ts](../srv/health-service.ts) | Its TypeScript handler |
| [test/health.test.ts](../test/health.test.ts) | Boots the project and calls the endpoint over HTTP |
| [test/cds-typescript.ts](../test/cds-typescript.ts) | Declares the TypeScript runtime for tests started by `node --test` |

`srv/.gitkeep` and `test/.gitkeep` were removed because both directories now hold real files. `db/.gitkeep` and `app/.gitkeep` stay: those directories are filled by Phases 4.2 and 4.5.

The repository `.gitignore` already covered everything generated here — `node_modules/`, `gen/`, `@cds-models/`, `*.sqlite`, `*.db` — so it needed no addition.

## Technology choices

**CAP 10 on Node.js 22.** `@sap/cds@10.1.0` declares `engines.node >= 22` and the installed runtime is Node 22.18.0. `@cap-js/sqlite@3.1.1` peers on `@sap/cds ^10`. The three pin to one consistent generation rather than a mix that happens to install.

**TypeScript, per ADR-008.** The decision register already chose TypeScript, with JavaScript as the acceptable simpler alternative. Keeping that choice means type errors arrive at `npm run typecheck` instead of at a failing request — which the first draft of the test here demonstrated immediately, by rejecting two `cds` API calls that do not exist before either was ever executed.

**SQLite in memory for local development.** `.cdsrc.json` sets `db` to `sqlite` with `url: ":memory:"`. An in-memory database has nothing to reset between runs, which is what will keep the later subphases' tests independent of each other. HANA Cloud is not configured and is not named in configuration: portability is maintained by using portable CDS types and CQN queries from 4.2 onward, not by declaring a production database this project cannot yet test against.

**A health service rather than no service at all.** CAP needs a model to serve, so "a foundation with no service" cannot be started, and a foundation that cannot be started cannot be verified. `HealthService` is deliberately not a business surface: one function, no entity, no persistence access. It is served over the REST adapter because the portal's documented contracts are REST/JSON, so this also confirms the adapter Phases 4.3 and 4.4 depend on. It can stay untouched for the rest of Phase 4, or be deleted once real services exist, with no consequence either way.

**Committed lockfile.** The component README already required this once implementation started. The versions recorded below are only meaningful if the next install resolves the same ones.

## Exact commands

```bash
cd cap-supplier-portal
npm ci
npm run typecheck
npm test
npm start
```

*Superseded, and kept as a Phase 4.1 checkpoint: `start` was changed to `cds-serve` when the first Cloud Foundry deployment crashed with `cds-tsx: not found`, because `cds-tsx` ships in the `@sap/cds-dk` devDependency and is absent from a production install. **The TypeScript development command is now `npm run watch`**, and `npm start` is the production command. The paragraph below describes the original Phase 4.1 arrangement.*

`npm start` runs `cds-tsx serve`, which serves the project with the TypeScript runtime registered. `npm run watch` runs `cds-tsx watch` for a reloading development server.

## Observed execution evidence

Executed on this machine on 2026-09-16. Node v22.18.0, npm 10.9.3.

### Install

```text
$ npm ci
added 98 packages, and audited 210 packages in 14s
found 0 vulnerabilities
```

Resolved top-level versions: `@sap/cds@10.1.0`, `@sap/cds-dk@10.1.1`, `@cap-js/sqlite@3.1.1`, `@cap-js/cds-test@1.0.2`, `@cap-js/cds-types@0.19.0`, `typescript@5.9.3`, `tsx@4.23.13`, `@types/node@22.20.3`.

### Typecheck

```text
$ npm run typecheck
> tsc --noEmit
(no diagnostics, exit 0)
```

### Test

```text
$ npm test
> node --import tsx --import ./test/cds-typescript.ts --test test/health.test.ts
ok 1 - the CAP runtime serves the health endpoint
# tests 1
# pass 1
# fail 0
```

### Server start and live request

```text
$ npm start
> cds-tsx serve

[cds] - loaded model from 1 file(s):

  srv\health-service.cds

[cds] - connect to db > sqlite { url: ':memory:' }
/> successfully deployed to in-memory database.

[cds] - using auth strategy {
  kind: 'mocked',
  impl: 'node_modules\@sap\cds\lib\srv\middlewares\auth\basic-auth.js'
}
[cds] - serving HealthService {
  at: [ '/health' ],
  decl: 'srv\health-service.cds:14',
  impl: 'srv\health-service.ts'
}
[cds] - server listening on { url: 'http://localhost:4004' }
[cds] - server v10.1.0 launched in 1515 ms
[rest] - GET /health/ping
```

```text
$ curl http://localhost:4004/health/ping
HTTP 200
{"status":"UP","component":"cap-supplier-portal","phase":"4.1","uptimeMs":179}
```

The log line that matters is `impl: 'srv\health-service.ts'`. It proves CAP resolved the **TypeScript** handler rather than a compiled artifact, which is the one thing about this toolchain that could have silently not worked.

### Empty by design

```text
$ npx cds compile srv --to sql
(no output)
```

There are no entities yet, so the model compiles to no SQL at all. That is the expected Phase 4.1 result and the clearest available statement of what has *not* been built.

## Two findings worth keeping

**CAP resolves TypeScript handlers only when `CDS_TYPESCRIPT` is set.** `@sap/cds/lib/srv/factory.js` chooses its implementation-file extensions from that environment variable: without it the candidate list is `['.js','.mjs']`, and a perfectly correct `.ts` handler is simply never found. The failure mode is not a module error but `501 - Service "HealthService" has no handler for "ping"`, which reads like a missing handler rather than a missing runtime. The `cds` CLI sets the variable, so `cds-tsx serve` and `cds-tsx watch` work; a test started by `node --test` bypasses that CLI and has to declare it, which is the entire purpose of [test/cds-typescript.ts](../test/cds-typescript.ts).

**`cds.test` moved out of `@sap/cds` in version 10.** `@sap/cds/lib/test/cds-test.js` is now a one-line re-export of `@cap-js/cds-test`, which is not installed as a transitive dependency. Calling `cds.test(...)` without it fails with `Cannot find module '@cap-js/cds-test'` raised from inside `@sap/cds`, so the diagnostic points at the framework rather than at the missing devDependency.

Both were found by running the thing. Neither would have been found by reading the source that was written.

## Deliberately deferred

Not implemented here, and not to be treated as missing:

- `Suppliers`, `Orders` and composed `OrderItems`, and any fixture data — Phase 4.2.
- `@cap-js/cds-typer` and generated `#cds-models` types. The path mapping is in `tsconfig.json`, but the generator is not installed, because with no entities it would generate nothing. It arrives in Phase 4.2 alongside the model it types.
- The ingestion contract, its structured DTO, `deliveryId` deduplication and the receipt — Phase 4.3.
- Supplier accept and reject, `EstimatedDeliveryDate` rules, response versioning and supplier isolation — Phase 4.4.
- The supplier UI — Phase 4.5.
- Any call to or from SAP — Phase 5. Integration Suite — Phase 6. OAuth, XSUAA and real identities — Phase 8. HANA Cloud — conditional on access. Event Mesh — Phase 9.

The mocked authentication strategy visible in the start-up log is CAP's local default, not an authorization design. It is replaced in Phase 4.4 by explicit supplier identity and in Phase 8 by platform identity.

## Next subphase

**Phase 4.2 — CAP persistence and domain model.** Define `Suppliers`, `Orders` and composed `OrderItems` in `db/` using portable CDS types that will survive a later move to HANA, with the field set derived from the mapped CAP order in [API_CONTRACTS.md](../../API_CONTRACTS.md). Add `@cap-js/cds-typer`, load synthetic fixtures, and extend the local suite to assert that the model deploys and the fixtures are queryable. No service handler and no business rule belongs in 4.2.
