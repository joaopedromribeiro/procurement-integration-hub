# Procurement Integration Hub

A guided SAP portfolio project connecting a custom procurement application to an external supplier portal.

**Current milestone: Phase 1 — RAP persistence and domain model.** Six ZJP_ table/CDS source files and a guided ADT lesson are prepared. Activation and data-model checks in the learner's SAP S/4HANA system are pending. No RAP behavior, CAP application, deployed iFlows, security configuration, or event infrastructure has been implemented.

## Project overview

The planned solution lets a buyer create and submit a purchase order, an approver release it, and a supplier accept or reject it through a separate portal. SAP remains responsible for procurement rules; the supplier portal records supplier decisions; SAP Integration Suite mediates the exchange.

This is a custom learning business object. It does not create standard SAP MM purchase orders, update SAP standard tables, or implement a complete procure-to-pay process.

## Business problem

Procurement teams need reliable visibility into supplier acknowledgements without manually copying data between systems. Different API structures, delayed responses, duplicate requests, and unavailable suppliers make this an integration problem as well as an application-development problem.

## Architecture

```mermaid
flowchart LR
    Buyer[Buyer and approver] --> UI[Fiori Elements]
    UI -->|OData V4| RAP[ABAP RAP purchase orders]
    RAP -->|Committed delivery intent| Dispatch[ABAP dispatch coordinator]
    Dispatch -->|HTTPS JSON| CI[SAP Integration Suite]
    CI -->|Mapped REST JSON| CAP[CAP Supplier Portal]
    Supplier[Supplier] --> CAP
    CAP -->|Separate HTTPS response request| CI
    CI -->|OData V4 action| RAP
```

All runtime components above are planned. Phase 5 connects the dispatcher and CAP directly for testing. Phase 6 introduces Cloud Integration. Phase 9 adds SAP Event Mesh. Supplier decisions happen later in a separate request; an HTTP connection never waits for human approval.

## Technology stack

| Planned technology | Intended evidence | Status |
| --- | --- | --- |
| ABAP Cloud and CDS view entities | Activated tables and composed CDS model | Phase 1 sources prepared; SAP verification pending |
| Managed RAP and EML | BO behavior, actions, validations and ABAP tests | Planned, phase 2 |
| OData V4, SAP Fiori Elements | Service metadata and buyer UI demonstration | Planned, phase 3 |
| SAP CAP, Node.js, TypeScript, CDS, SQLite | Running portal API and handler tests | Planned, phase 4 |
| REST, JSON | Direct round trip with receipts and supplier response | Planned, phase 5 |
| SAP BTP Integration Suite, Cloud Integration, XML mapping | Deployed iFlows and message processing evidence | Planned, phase 6 |
| Error handling and monitoring | Fault-injection and recovery demonstrations | Planned, phase 7 |
| OAuth 2.0, XSUAA, destinations, authorization | Positive and negative security tests | Planned, phase 8 |
| SAP Event Mesh | Deployed queues, event delivery and duplicate tests | Planned, phase 9 |
| API Management | Deployed proxy and policy verification | Planned, phase 10 |
| SAP HANA Cloud and BTP Cloud Foundry | Optional deployment evidence | Conditional on access |

Clean Core is a design constraint throughout. A mock demonstrates the contract or pattern it exercises; it does not demonstrate hands-on use of the SAP service it represents.

## Business flow

1. Buyer creates a draft, enters a supplier and items, and saves an active order.
2. Buyer submits the active order; the application validates it and freezes commercial data.
3. Approver approves or rejects the submission.
4. Buyer requests delivery of an approved order; a committed snapshot is sent to the portal.
5. Portal stores the order and returns a receipt. SAP marks the order `SENT`.
6. Supplier accepts or rejects the order and may provide an estimated delivery date on acceptance.
7. A separate return request updates SAP to `CONFIRMED` or `REJECTED`.
8. Technical failures retain enough information for diagnosis, reconciliation, and controlled retry.

## ABAP RAP architecture

Managed, draft-enabled header/item composition over custom persistence; root and child CDS view entities; UI and integration projections; behavior definitions and implementations; service definitions and OData V4 bindings. EML is the internal BO interface. See [architecture](ARCHITECTURE.md) and [domain model](docs/architecture/domain-model.md).

## CAP architecture

CAP CDS models describe Suppliers, Orders, and composed OrderItems. TypeScript handlers enforce ingestion, supplier decisions, and row-level supplier access. SQLite supports local development; portable CDS and queries prepare for a later HANA Cloud deployment. Integration and supplier-facing services have separate permissions.

## Integration Suite flow

Two Cloud Integration iFlows mediate order delivery and supplier responses. The proposed outbound design uses an HTTPS sender, Content Modifier, JSON/XML conversion, XML validation, Router, graphical Message Mapping, JSON conversion, and HTTP receiver. REST is the API style; the Cloud Integration receiver adapter used here is HTTP. Groovy will be added only if a documented requirement cannot be handled clearly with standard steps.

## API contracts

[API_CONTRACTS.md](API_CONTRACTS.md) defines proposed boundaries, a realistic field mapping, request identities, and error behavior. Routes are design targets, not callable endpoints. Actual RAP paths will be taken from generated service metadata in Phase 3.

## Security

Production target: HTTPS, authenticated machine clients, supplier-scoped authorization, buyer/approver roles, and separately protected operational actions. Phase 8 adds OAuth and platform configuration. Earlier hosted tests must still use the authentication required by the host; unauthenticated development is restricted to local execution.

## Error handling

Delivery IDs and immutable snapshots make retry safe. A timeout means the delivery result is unknown. Supplier rejection is a business outcome, not a transport error. See [error policy](API_CONTRACTS.md#error-policy).

## Event-driven architecture

Phase 9 will replace the delivery trigger with committed RAP business events, SAP Event Mesh queues, and integration consumers. HTTP receipt and business-response semantics remain distinct. Event contracts, durable publication, idempotency, eventual consistency, and dead-letter recovery are designed in [ARCHITECTURE.md](ARCHITECTURE.md).

## How to run

There is no executable application yet. Follow the [Phase 1 ADT guide](abap-rap/docs/phase-1-domain-model.md) to create the two persistence tables, two base CDS entities and two projection entities manually, with a test after each step. The source files are not a serialized ABAP import package. No npm installation is needed.

The [Phase 0 review exercise](docs/phase-0-review.md) remains available as architecture background. The Phase 0 ZIP is an archived foundation snapshot and does not contain Phase 1 changes.

For future setup, consult [environments and services](docs/environments.md). Each implementation phase will add its own verified run instructions.

## Repository layout

```text
procurement-integration-hub/
  abap-rap/{cds,behavior,classes,service,persistence,docs}/
  cap-supplier-portal/{db,srv,app,test}/
  integration-suite/{iflows,mappings,groovy,payloads,docs}/
  event-mesh/{docs,payloads}/
  api-management/docs/
  docs/{architecture,diagrams,screenshots}/
  README.md
  ARCHITECTURE.md
  API_CONTRACTS.md
  PROJECT_STATUS.md
  LEARNINGS.md
```

Empty directories are reserved with `.gitkeep`. Component READMEs explain the intended contents. The ABAP folders are a navigation plan; the actual serialization and package mapping will be selected for the target system before export.

## Screenshots

No runtime screenshots yet. Verified screenshots will be added under `docs/screenshots/` with the environment, phase, and scenario identified. Architecture diagrams are designs, not execution evidence.

## Project roadmap

| Phase | Deliverable | Completion gate |
| --- | --- | --- |
| 0 | Architecture and repository | Consistent documents and walkthrough |
| 1 | RAP domain model | Tables and CDS activate; composition can be inspected |
| 2 | RAP behavior | EML tests verify totals, draft lifecycle and transitions |
| 3 | OData V4 and Fiori Elements | Buyer flow works through generated service and UI |
| 4 | CAP Supplier Portal | API handlers and minimal supplier UI work locally |
| 5 | Direct RAP–CAP integration | Delivery and return response work with stable identities |
| 6 | Integration Suite | Both deployed iFlows transform and route correctly |
| 7 | Error handling and monitoring | Fault matrix, retries and reconciliation demonstrated |
| 8 | Authentication and security | OAuth and supplier isolation verified |
| 9 | Event Mesh | Committed events, duplicates and dead-letter recovery verified |
| 10 | API Management | Proxy authentication, throttling and routing verified |
| 11 | Tests and portfolio presentation | Evidence-backed README, diagrams, screenshots and lessons |

Phase 0 is complete. Phase 1 source preparation is complete, with learner activation/verification pending; later phases are unstarted. Testing and documentation accompany every phase; Phase 11 consolidates them.

## Lessons learned

See [LEARNINGS.md](LEARNINGS.md) for concepts studied versus practiced. [PROJECT_STATUS.md](PROJECT_STATUS.md) tracks progress, decisions, open issues, and technical debt. Current portfolio wording: “Designed the architecture and API contracts, and prepared the RAP persistence and CDS domain-model sources for a procurement integration learning project.” SAP execution claims will be added only with activation/test evidence.

Technical references are collected in [SAP sources](docs/architecture/references.md).
