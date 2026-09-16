# CAP Supplier Portal

Phase 4 in progress. **Phase 4.1 (foundation), 4.2 (persistence), 4.3 (integration ingestion) and 4.4 (supplier service) are locally runtime-verified**: the project installs, typechecks, tests and starts; the `pih.portal` model deploys to SQLite with synthetic fixtures; `POST /rest/integration/v1/Orders` accepts a purchase-order snapshot idempotently; and a supplier can list and read only its own orders and answer with an accept, a reject or a revised delivery date. See the [Phase 4.1](docs/phase-4-1-cap-foundation.md), [Phase 4.2](docs/phase-4-2-domain-model.md), [Phase 4.3](docs/phase-4-3-integration-ingestion.md) and [Phase 4.4](docs/phase-4-4-supplier-service.md) guides.

The supplier UI is Phase 4.5 and does not exist. The portal does not talk to SAP in Phase 4: supplier decisions are stored as pending outbound responses and nothing is sent.

## Run it locally

```bash
cd cap-supplier-portal
npm ci
npm run typecheck
npm test
npm start
```

`npm start` serves on `http://localhost:4004`. `npm run watch` gives a reloading development server. Node.js 22 or later is required.

`npm run typecheck` and `npm test` each regenerate the `#cds-models` types first, because that output is git-ignored. `npx cds compile db --to sql` prints the DDL the model deploys.

### Deliver an order

```bash
curl -i -X POST http://localhost:4004/rest/integration/v1/Orders \
  -H 'Content-Type: application/json' \
  -d '{"schemaVersion":"1.0","deliveryId":"0e7df7c7-2427-4700-a7bb-63aa9f1a11af","source":{"system":"PIH_ABAP_DEV","orderId":"82e96537-4ecc-4c34-b2c3-e75486329447","orderNumber":"PO000001","revision":1},"supplierCode":"SUP001","amount":{"currency":"EUR","value":"1500.00"},"lines":[{"sourceItemId":"77418462-e8d8-4d60-b5fd-98510b5d90b0","lineNumber":10,"product":{"code":"MAT001","description":"Laptop"},"orderedQuantity":{"value":"2.000","unit":"PCE"},"unitPrice":{"currency":"EUR","value":"750.0000"},"lineAmount":"1500.00"}]}'
```

`201` with a receipt the first time. Send it again unchanged and it is `200` with the *same* receipt. Change the quantity but keep the `deliveryId` and it is `409` with the stored order untouched. `GET /health/ping` reports that the runtime is up.

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
- `test/`: the foundation, persistence and ingestion suites — 63 tests, all driven through a running CAP application.
- `app/`: empty. The minimal supplier interface arrives in Phase 4.5.

**No writable persistence path is exposed by any service.** `IntegrationService.Orders` is a service-local contract shape with `@insertonly`, so `GET` on it returns 405. The supplier projections are `@readonly` with explicit element lists and a row filter, so `PATCH` and `DELETE` return 405 and no foreign key or SAP correlation field reaches a supplier. `/odata/v4/Orders` returns 404: there is no generic CRUD surface over the database.

## Pinned versions

`@sap/cds@10`, `@sap/cds-dk@10`, `@cap-js/sqlite@3`, `@cap-js/cds-typer@0`, TypeScript 5.9 and `tsx`, resolved exactly by the committed `package-lock.json`. Local development uses SQLite in memory; HANA Cloud compatibility stays an intention that must later be verified on HANA, so the model uses portable CDS types and every query is CQN rather than SQLite-specific SQL.

`.cdsrc.json` sets `cds.odata.structs: true`. That is not cosmetic: without it CAP flattens structured elements and the documented nested request body is rejected.

Business rules and API boundaries are in [architecture](../ARCHITECTURE.md), [contracts](../API_CONTRACTS.md) and the [domain model](../docs/architecture/domain-model.md), which is where the CAP field set is specified. SAP RAP owns the purchase-order lifecycle; this portal owns supplier-facing persistence and supplier decisions, and never becomes a second implementation of the SAP rules.
