# Phase 4.2 — CAP persistence and domain model

Status: **locally runtime-verified.** `npm ci`, `npm run typecheck` and `npm test` were executed from a clean `node_modules` and all succeeded; nine tests pass, including the Phase 4.1 health test. As in Phase 4.1 this is local Node.js execution evidence, which is a different and weaker claim than the SAP runtime evidence behind Phases 1–3. Nothing in Phase 4 runs in or against an SAP system.

No ABAP source, CDS view, behavior definition, metadata extension, service definition, RAP test class or SAP persistence object was touched. Phase 3 remains complete and SAP runtime-verified; Phase 4.1 remains complete.

## Purpose

Give the portal its own persistence: the three entities it needs to hold a received purchase-order snapshot and, later, a supplier's decision about it. Persistence only — no service, no handler, no rule. Phase 4.3 adds ingestion and Phase 4.4 adds the supplier surface, and both are easier to attribute failures in if the tables underneath them are already proven.

## Where the model came from

The field set was **not** designed in this subphase and **not** derived from the SAP tables. It already existed in the repository, in the CAP persistence table of [docs/architecture/domain-model.md](../../docs/architecture/domain-model.md), with the mapping rules in the *Mapped CAP order* section of [API_CONTRACTS.md](../../API_CONTRACTS.md). Phase 4.2 implements that specification and changes none of it.

That is why the portal's names differ from SAP's, and the differences are the whole point of the boundary:

| SAP RAP calls it | The portal calls it | Why |
| --- | --- | --- |
| `PurchaseOrderNumber` | `externalOrderNumber` | It is external *to the portal*; the portal's identity is its own `ID` |
| `Material` / `MaterialDescription` | `productCode` / `description` | A supplier portal has products, not SAP materials |
| `ItemNumber` | `lineNumber` | A line on a received document, not an SAP item key |
| `NetPrice` | `unitPrice` | Portal vocabulary; the contract maps the two explicitly |
| `TotalAmount` (item) | `lineAmount` | Distinguishes a line total from the header total |
| `UnitOfMeasure`, value `EA` | `uom`, value `PCE` | The contract's controlled `EA → PCE` value mapping happens at the boundary |
| `CompanyCode`, `PurchasingOrganization`, `PurchasingGroup` | **absent** | "Internal SAP context not required by portal" |
| `SupplierName` | **absent on Orders** | The portal resolves its own `Suppliers` record rather than trusting a transmitted name |

A model that copied `ZJP_PO_H` and `ZJP_PO_I` would have carried all three organizational fields, the RAP status values and the SAP names, and would have made the portal a second, weaker copy of the SAP order. ADR-004 says RAP owns commercial facts and CAP owns the supplier response; the field list is where that decision either holds or quietly stops holding.

## Namespace

`pih.portal`. `pih` is the project's established prefix — `PIH_OrderDelivery_v1`, `PIH_SupplierResponse_v1`, `/http/pih/v1/…`, and the fixture source system `PIH_ABAP_DEV`. `portal` says which side of the integration owns these tables. The generated table names follow from it: `pih_portal_Suppliers`, `pih_portal_Orders`, `pih_portal_OrderItems`.

## Final entity model

```text
Suppliers ──(Association to many)──▶ Orders ──(Composition of many)──▶ OrderItems
     ▲                                  │                                  │
     └────(Association to one)──────────┘                                  │
                                        └────(Association to one, backlink)┘
```

| Entity | Responsibility |
| --- | --- |
| `Suppliers` | The portal's own supplier reference. Resolves an incoming `supplierCode` in Phase 4.3 and scopes supplier access in Phase 4.4. Deliberately thin: code, name, active flag — a controlled synthetic reference, not master-data replication |
| `Orders` | One received purchase-order snapshot. Holds the portal identity, the full source identity, the commercial summary it was sent, and the columns a supplier decision will later fill |
| `OrderItems` | One line of a received order, with the source item identity preserved so a later response can be correlated line by line |

### Two identities on every order, on purpose

`Orders` carries `ID` — the portal's own UUID — and, separately, `sourceSystem`, `sourceOrderId` and `sourceRevision`. Neither can replace the other. The portal needs a key it controls and can hand out in a receipt (`portalOrderId`) before SAP knows anything about it; SAP's UUID is a key the portal did not issue and must not pretend to own. There are no cross-database foreign keys anywhere in this project: the two systems correlate through that triple and through `deliveryId`, which is exactly what the uniqueness rule `Orders(sourceSystem, sourceOrderId, sourceRevision)` protects.

`Suppliers` follows the same shape: `ID` is the portal's key, `supplierCode` is the external mapping key.

### Supplier-decision columns exist and nothing writes them

`status`, `estimatedDeliveryDate`, `rejectionReason` and `responseVersion` are on `Orders` because the documented persistence contract puts them there. Phase 4.2 implements no way to change any of them. `status` defaults to `#RECEIVED` and `responseVersion` to `0`, which matches the contract's "supplier status is server-owned and defaults to RECEIVED" and the domain model's "0 before response".

Every fixture order is therefore `RECEIVED` with a null delivery date and null reason. No fixture pretends a decision happened, because no code in this subphase could have produced one.

## Association versus Composition

Both relationships were chosen, not defaulted.

**`Orders.items` is a `Composition of many OrderItems`.** A line has no meaning apart from its order, arrives with it in one deep insert in Phase 4.3, and must disappear with it. Composition is CAP's containment relationship: the child is part of the parent document, and deleting the parent cascades. This is the same ownership statement as the RAP composition between `ZJP_I_PurchaseOrder` and its items — and, as in RAP, it is what stops an item from being addressable as an independent object.

**`Orders.supplier` is an `Association to one Suppliers`.** A supplier exists before any order arrives and outlives every one of them. If this were a composition, deleting an order would delete the supplier, and the supplier would become part of the order document rather than a thing the order refers to.

**`Suppliers.orders` is an `Association to many Orders`, not a composition.** This is the direction most worth getting right. An order does not belong to the supplier's lifecycle — it belongs to the delivery that brought it. Modelling it as a composition would make `Suppliers` a document root whose deletion cascades into orders the portal is obliged to keep, and would invert who owns what.

The distinction is asserted rather than described: one test creates an order with a line, deletes the order, and checks that the line is gone **and** that the supplier is still there.

## Portability

Everything is a CDS-native type: `UUID`, `String(n)`, `Integer`, `Boolean`, `Date`, `Timestamp`, `Decimal(p,s)` with the precisions and scales from the domain model — `Decimal(19,2)` for amounts, `Decimal(13,3)` for quantity, `Decimal(19,4)` for unit price. No SQLite-specific SQL, no raw SQL at all: the tests use CQN only, so the same queries are what would run against HANA.

HANA compatibility remains an intention, not a verified fact. It cannot become one until the project has a HANA to deploy to.

### Aspects: `cuid` yes, `managed` no

`cuid` from `@sap/cds/common` is used on all three entities. It contributes exactly `key ID : UUID`, which is what the documented model specifies, and it makes "the portal issues its own key" a declaration rather than three repeated lines.

`managed` was **not** used, deliberately. It would have supplied `createdAt`, `createdBy`, `modifiedAt` and `modifiedBy`. Two of those are wrong here: the contract names the timestamp `receivedAt`, because in this domain the fact being recorded is *when the portal received the snapshot*, and adopting `createdAt` would have renamed a contract field to suit a convenience aspect. The other two, `createdBy` and `modifiedBy`, have nothing to populate them — there is no authenticated user until Phase 4.4 and no platform identity until Phase 8 — so they would have been two permanently empty columns implying an audit trail that does not exist. That is the same restraint Phase 3.2 applied when it refused to annotate fields no code writes.

What `managed` does internally is still used: `receivedAt` carries `@cds.on.insert: $now` and `modifiedAt` carries `@cds.on.insert: $now` and `@cds.on.update: $now`, which is precisely how the standard aspect is defined. The mechanism was kept and the naming was not.

### Semantic annotations, following the Phase 3.2 lesson

`@Measures.ISOCurrency` points each amount at its currency element and `@Measures.Unit` points `quantity` at `uom`. These are semantics, not presentation — the CAP equivalent of the `@Semantics.amount.currencyCode` and `@Semantics.quantity.unitOfMeasure` markers placed on the ABAP base views in Phase 1. Phase 3.2 showed what that buys: Fiori rendered `2 EA` and `1,500.00 EUR` with no UI annotation anywhere, purely because meaning had been declared at the layer that owns it. Declaring it here costs nothing and means no service or UI in Phases 4.3 to 4.5 has to restate which column carries the currency.

### Uniqueness became real database constraints

The three uniqueness rules in the domain model are declared with `@assert.unique`, and the generated DDL shows them as actual `CONSTRAINT … UNIQUE` clauses rather than runtime-only checks:

```sql
CONSTRAINT pih_portal_Suppliers_supplierCode UNIQUE (supplierCode)
CONSTRAINT pih_portal_Orders_sourceOrder UNIQUE (sourceSystem, sourceOrderId, sourceRevision)
CONSTRAINT pih_portal_OrderItems_line UNIQUE (order_ID, lineNumber)
CONSTRAINT pih_portal_OrderItems_sourceItem UNIQUE (order_ID, sourceItemId)
```

That matters for Phase 4.3, because the ingestion contract requires parallel duplicates to be "resolved through database uniqueness and rereading the committed receipt" rather than by a read-before-insert check. The constraint the contract asks for exists. Whether the runtime surfaces it as the contract's 409 is a Phase 4.3 question and is not answered here.

### Generated DDL

`npx cds compile db --to sql`:

```sql
CREATE TABLE pih_portal_Suppliers (
  ID NVARCHAR(36) NOT NULL,
  supplierCode NVARCHAR(10) NOT NULL,
  name NVARCHAR(100),
  active BOOLEAN DEFAULT TRUE,
  PRIMARY KEY(ID),
  CONSTRAINT pih_portal_Suppliers_supplierCode UNIQUE (supplierCode)
);

CREATE TABLE pih_portal_Orders (
  ID NVARCHAR(36) NOT NULL,
  sourceSystem NVARCHAR(30) NOT NULL,
  sourceOrderId NVARCHAR(36) NOT NULL,
  sourceRevision INTEGER NOT NULL,
  externalOrderNumber NVARCHAR(20),
  supplier_ID NVARCHAR(36),
  currency NVARCHAR(3),
  totalAmount REAL_DECIMAL(19, 2),
  status NVARCHAR(10) DEFAULT 'RECEIVED',
  estimatedDeliveryDate DATE_TEXT,
  rejectionReason NVARCHAR(255),
  responseVersion INTEGER DEFAULT 0,
  deliveryId NVARCHAR(36) NOT NULL,
  receivedAt TIMESTAMP_TEXT,
  modifiedAt TIMESTAMP_TEXT,
  PRIMARY KEY(ID),
  CONSTRAINT pih_portal_Orders_sourceOrder UNIQUE (sourceSystem, sourceOrderId, sourceRevision)
);

CREATE TABLE pih_portal_OrderItems (
  ID NVARCHAR(36) NOT NULL,
  order_ID NVARCHAR(36) NOT NULL,
  sourceItemId NVARCHAR(36) NOT NULL,
  lineNumber INTEGER NOT NULL,
  productCode NVARCHAR(40),
  description NVARCHAR(100),
  quantity REAL_DECIMAL(13, 3),
  uom NVARCHAR(3),
  unitPrice REAL_DECIMAL(19, 4),
  currency NVARCHAR(3),
  lineAmount REAL_DECIMAL(19, 2),
  PRIMARY KEY(ID),
  CONSTRAINT pih_portal_OrderItems_line UNIQUE (order_ID, lineNumber),
  CONSTRAINT pih_portal_OrderItems_sourceItem UNIQUE (order_ID, sourceItemId)
);
```

`supplier_ID` and `order_ID` are generated by CAP from the associations. No foreign-key column was written by hand and no SAP naming convention was imported.

## Fixtures

Three CSV files under `db/data/`, named `<namespace>-<Entity>.csv` as CAP expects. All values are obviously synthetic.

Two suppliers: `SUP001` "Example Technology Supplier" and `SUP002` "Example Components Supplier", both active. `SUP001` is the code the domain model already nominates as the shared synthetic supplier.

Three orders, all `RECEIVED`, all `EUR`, all from `PIH_ABAP_DEV` at revision 1:

| Number | Supplier | Total | Lines |
| --- | --- | --- | --- |
| `PO00001001` | SUP001 | 1861.50 | 2 |
| `PO00001002` | SUP001 | 750.00 | 1 |
| `PO00001003` | SUP002 | 602.50 | 1 |

Four lines, each `PCE` and `EUR`:

| Order | Line | Product | Qty | Unit price | Line amount |
| --- | --- | --- | --- | --- | --- |
| PO00001001 | 10 | MAT001 Laptop | 2.000 | 750.0000 | 1500.00 |
| PO00001001 | 20 | MAT002 Docking station | 3.000 | 120.5000 | 361.50 |
| PO00001002 | 10 | MAT001 Laptop | 1.000 | 750.0000 | 750.00 |
| PO00001003 | 10 | MAT002 Docking station | 5.000 | 120.5000 | 602.50 |

The arithmetic is consistent because the contract requires it — "verify arithmetic; do not invent totals during mapping" — and a test recomputes the header total from the lines rather than trusting the CSV. Two suppliers with 2 and 1 orders make the `Suppliers → Orders` association testable by count rather than by existence.

`receivedAt` and `modifiedAt` are given explicit values in the CSV, because `cds deploy` inserts CSV rows directly and does not run the `@cds.on.insert` handler that fills them for a normal insert.

## Generated TypeScript types

`@cap-js/cds-typer@0.41.1` is now a devDependency and `npm run generate-types` produces `@cds-models/`. That directory stays git-ignored, as it already was, so the generation step is wired into the workflow instead: `pretypecheck` and `pretest` both run it, and a clean checkout therefore only needs `npm ci && npm test`.

The generated module is imported by its documented subpath:

```ts
import { OrderItems, Orders, Suppliers } from '#cds-models/pih/portal'
```

and used directly as the query target — `SELECT.from(Orders)` — so the import is itself a test: it has to resolve for the TypeScript compiler *and* for Node at runtime, or the suite fails.

### One configuration change to Phase 4.1, and why it was necessary

`tsconfig.json` moved from `module: commonjs` / `moduleResolution: node` to `module: node16` / `moduleResolution: node16`, and the `paths` entry for `#cds-models/*` was removed. Resolution now comes from the `imports` field added to `package.json`:

```json
"imports": { "#cds-models/*": "./@cds-models/*/index.js" }
```

The reason is a genuine conflict rather than a preference. cds-typer emits two parallel artifacts per module: `index.js` for the runtime and `index.d.ts` for the compiler. A `tsconfig` `paths` entry is read by the TypeScript compiler **and** by `tsx` at runtime, so a single mapping has to satisfy both consumers, and no target satisfies both:

- pointing `paths` at `index.ts` — the value Phase 4.1 carried, and the one CAP's own docs show — made `tsc` crash outright with `Error: Debug Failure` at `resolveExternalModule`, because with the default generator output no `index.ts` exists;
- pointing it at `index.d.ts` satisfied `tsc`, and then `tsx` followed the same mapping at runtime and tried to execute a declaration file: `ERROR: The constant "PortalOrderStatus" must be initialized`;
- generating `.ts` files instead, with `--outputDTsFiles false`, satisfied both resolvers and then failed at runtime with `TypeError: Class extends value undefined is not a constructor or null`, because those files are compiler input, not a loadable runtime module.

`moduleResolution: node16` is what breaks the tie: it is the first resolution mode that understands the `imports` field, so TypeScript follows `#cds-models/*` to `index.js` and picks up `index.d.ts` beside it, while Node resolves the same subpath to `index.js` on its own. One declaration, two correct answers, and no `paths` entry for either resolver to fight over.

The Phase 4.1 health service and its test compile and run unchanged under the new setting.

## Exact commands

```bash
cd cap-supplier-portal
npm ci
npm run typecheck        # runs generate-types first
npm test                 # runs generate-types first
npx cds compile db --to sql
npm start
```

## Observed execution evidence

Executed on 2026-09-16. Node v22.18.0, npm 10.9.3. Resolved versions: `@sap/cds@10.1.0`, `@sap/cds-dk@10.1.1`, `@cap-js/sqlite@3.1.1`, `@cap-js/cds-typer@0.41.1`, `@cap-js/cds-test@1.0.2`, `@cap-js/cds-types@0.19.0`, `typescript@5.9.3`, `tsx@4.23.13`, `@types/node@22.20.3`.

### Clean install and typecheck

```text
$ npm ci
added 99 packages, and audited 211 packages in 21s
found 0 vulnerabilities

$ npm run typecheck
> cds-typer "*" --outputDirectory @cds-models
> tsc --noEmit
(no diagnostics, exit 0)
```

### Tests

```text
$ npm test
    ok 1 - all three entities are in the deployed model
    ok 2 - the composition and the association are modelled as different things
ok 1 - the model deploys
    ok 1 - suppliers are queryable with their fixture values
    ok 2 - orders are queryable and carry both identities
    ok 3 - order items are queryable and use portal-side names and units
ok 2 - fixtures load
    ok 1 - an order composes its items, and the line totals sum to the header total
    ok 2 - a supplier reaches its orders through the association
    ok 3 - deleting an order deletes its items but never its supplier
ok 3 - relationships
ok 4 - the CAP runtime serves the health endpoint
# tests 9
# suites 3
# pass 9
# fail 0
```

The last line is Phase 4.1's test, unchanged and still passing.

### Deployment and the absence of a business API

```text
$ npm start
[cds] - loaded model from 3 file(s):

  srv\health-service.cds
  db\schema.cds
  node_modules\@sap\cds\common.cds

[cds] - connect to db > sqlite { url: ':memory:' }
  > init from db\data\pih.portal-Suppliers.csv
  > init from db\data\pih.portal-Orders.csv
  > init from db\data\pih.portal-OrderItems.csv
/> successfully deployed to in-memory database.

[cds] - serving HealthService {
  at: [ '/health' ],
  decl: 'srv\health-service.cds:14',
  impl: 'srv\health-service.ts'
}
[cds] - server listening on { url: 'http://localhost:4004' }
[cds] - server v10.1.0 launched in 1282 ms
```

```text
$ curl http://localhost:4004/health/ping          -> 200 {"status":"UP", ...}
$ curl http://localhost:4004/rest/supplier/v1/Orders -> 404
$ curl http://localhost:4004/odata/v4/Orders         -> 404
```

The three CSVs load and the tables deploy, and **`HealthService` is still the only thing served**. The entities exist in persistence and are reachable by query, and by nothing else. That is the Phase 4.2 boundary, verified rather than asserted.

## Deliberately deferred

Not implemented here, and not to be treated as missing:

- `IntegrationService`, `SupplierService`, `POST /rest/integration/v1/Orders`, the custom CREATE ingestion handler, structured service-level DTOs, `deliveryId` deduplication and receipt generation — Phase 4.3.
- Supplier row-level authorization, `accept`, `reject`, `updateEstimatedDeliveryDate` and `responseVersion` increments — Phase 4.4.
- `DeliveryReceipts` and `SupplierResponseDelivery`. The domain model marks both "phase 5" and they are not in this schema.
- Validation of any kind: unknown supplier codes, unsupported currencies or units, inconsistent totals, negative prices and duplicate line numbers all fail at the boundary in Phase 4.3, not in persistence.
- The supplier UI — Phase 4.5. SAP calls — Phase 5. Integration Suite — Phase 6. OAuth and XSUAA — Phase 8. HANA Cloud — conditional on access. Event Mesh — Phase 9.

OI-04 stays open: nothing about REST structured ingestion or bound-action wire behaviour was answered here.

## Next subphase

**Phase 4.3 — integration-facing order ingestion.** An `IntegrationService` exposing `POST /rest/integration/v1/Orders`, with an explicit structured service-level type for the mapped CAP order, a custom CREATE handler that maps it into `Orders` and `OrderItems` rather than accepting an unrestricted deep insert, supplier resolution against `Suppliers`, the documented boundary validations, `deliveryId` deduplication, and the `201`/`200`/`409` receipt semantics.

## Reading `schema.cds` if CAP is new to you

Every construct below is in [db/schema.cds](../db/schema.cds). The comparisons are to ABAP RAP/CDS, which this project already covers.

**`namespace pih.portal;`** — a prefix applied to every definition in the file, so the entity written as `Orders` is really `pih.portal.Orders` and its table is `pih_portal_Orders`. It plays the role `ZJP_` plays in the ABAP objects, except it is a language construct rather than a naming habit, and CAP applies it for you.

**`using {cuid} from '@sap/cds/common';`** — imports a reusable definition from CAP's standard library. There is no ABAP equivalent to importing a fragment like this; the closest idea is an ABAP CDS `extend`/include.

**`entity Suppliers : cuid { … }`** — `entity` declares both a persistent table and a type. The `: cuid` part applies an *aspect*: a named bundle of elements mixed into the entity. `cuid` contributes exactly one thing, `key ID : UUID`, which is why `Suppliers` has an `ID` column that never appears in the file. In RAP you would write the UUID key into `ZJP_PO_H` and mark it `key` in the view; the aspect is the same intent, declared once and reused.

**`key`** — the primary key. Here it arrives through `cuid`. **`UUID`** is a CDS type stored as `NVARCHAR(36)`, the same 36-character canonical form RAP uses for `PurchaseOrderUUID`. Both systems chose a UUID key for the same reason: a stable identity that no human types and no other system can collide with.

**`Association to one Suppliers`** on `Orders.supplier` — a reference to a row that lives its own life. CAP turns it into a `supplier_ID` foreign-key column automatically; you never write that column. This is the CAP counterpart of an ABAP CDS association, and, as there, it implies no ownership: deleting an order does nothing to the supplier.

**`Composition of many OrderItems on items.order = $self`** on `Orders.items` — containment. The items are part of the order document: they are created with it, they are deleted with it, and they are not meant to be addressed independently. This is exactly the RAP composition between `ZJP_I_PurchaseOrder` and `ZJP_I_PurchaseOrderItem`, and it carries the same consequence that Phase 2.6 relied on — in RAP, item deletion stayed behind the root action `removeItem` because the child is not an independent object. `$self` means "the row on the parent side", so the clause reads: link the items whose `order` points back at me.

**`Association to many Orders on orders.supplier = $self`** on `Suppliers.orders` — the reverse navigation, and deliberately *not* a composition. It lets you ask a supplier for its orders without making the orders belong to the supplier.

**`order : Association to one Orders`** on `OrderItems` — the backlink the composition's `on` condition refers to. A CAP composition is defined from the parent and resolved through a real association on the child.

**`cuid` used, `managed` not** — `managed` is the other aspect you will meet everywhere in CAP examples; it adds `createdAt`, `createdBy`, `modifiedAt`, `modifiedBy`. It is not used here for the reasons given above: it would rename `receivedAt` and add two columns nothing can fill. The two `@cds.on.insert: $now` annotations do the part of its job this model actually needs.

**Why SQLite ends up with tables at all.** `schema.cds` is not SQL and is not database-specific. At startup CAP compiles it to DDL for whichever database is configured and runs it — the exact statements are in the *Generated DDL* section above, and you can print them yourself with `npx cds compile db --to sql`. The same source compiles to HANA DDL without being edited, which is what "portable" means in practice. This is the one place where the CAP and ABAP worlds genuinely differ in kind: in RAP you create the tables first and model views over them, while in CAP the model *is* the definition and the tables are generated from it.
