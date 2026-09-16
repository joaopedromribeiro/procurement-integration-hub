# Procurement Integration Hub

A guided SAP portfolio project connecting a custom procurement application to an external supplier portal.

**Current milestone: Phase 2 is complete and SAP runtime-verified through Phase 2.7E.** The purchase-order lifecycle runs `DRAFT` → `SUBMITTED` → `APPROVED` or `REJECTED` through the root actions `submit`, `approve` and `reject`, with a mandatory reason on rejection and `RejectionOrigin = APPROVER`, and the root action `cancel` carries `DRAFT`, `SUBMITTED` or `APPROVED` to the terminal `CANCELLED`. All four are active-instance only and refuse technical drafts. Commercial content is editable only while business `Status` is `DRAFT`: once an order leaves that state, root and item commercial updates, adding items by association and `removeItem` are all rejected by RAP prechecks, on active and technical draft instances alike — `CANCELLED` is covered by that same invariant with no new code. Business `Status = 'DRAFT'` stays distinct from RAP technical draft state. Authorization is still a permissive study stub, so `approve` and `cancel` name transitions and not access controls. `APPROVED` → `CANCELLED` has no delivery-request guard because no Phase 2 capability can make that condition reachable; it belongs with `DeliveryIntent` in Phase 5. Physical root `DELETE` is restricted to `DRAFT`, and `PurchaseOrderNumber` is allocated on a successful `submit` as `PO` plus eight digits from number range object `ZJP_PO` — never on create or save, and never through a determination, so an order cancelled straight from `DRAFT` carries no number. `sendToSupplier` belongs to Phase 5 and is outside Phase 2.

Published repository: [Procurement Integration Hub on GitHub](https://github.com/joaopedromribeiro/procurement-integration-hub). The local main branch tracks origin/main. New working-tree edits must be committed and pushed before they appear on GitHub.

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
| ABAP Cloud and CDS view entities | Activated tables and composed CDS model | Phase 1 complete; successful ADT activation reported by learner |
| Managed RAP and EML | BO behavior and ABAP runtime checks | CRUD/composition, validations, determinations, technical draft and ownership-safe active/draft `removeItem` verified in SAP |
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

The six domain-model objects have been activated in the learner's SAP system; there is no transactional application or OData service yet. The [Phase 1 ADT guide](abap-rap/docs/phase-1-domain-model.md) contains the manual reproduction steps and confirmed compatibility fixes. The source files are not a serialized ABAP import package. No npm installation is needed.

The [Phase 2.5A guide](abap-rap/docs/phase-2-5a-supplier-validation.md) records the successful Supplier-validation evidence. The [Phase 2.5B guide](abap-rap/docs/phase-2-5b-quantity-validation.md) contains the Quantity-validation source and SAP runtime test procedure; the successful SAP execution evidence is recorded.

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

Phases 0 and 1 and the whole of Phase 2, through 2.7E, are complete within their documented scope. [Phase 2.6](abap-rap/docs/phase-2-6-technical-draft.md) is SAP runtime-verified for active, saved-draft and buffer-only draft item removal. [Phase 2.7A](abap-rap/docs/phase-2-7a-submit-action.md) is SAP runtime-verified for the active `DRAFT` → `SUBMITTED` transition. [Phase 2.7B](abap-rap/docs/phase-2-7b-post-submission-immutability.md) added precheck-enforced commercial immutability, [Phase 2.7C](abap-rap/docs/phase-2-7c-approve-reject.md) is SAP runtime-verified for the `approve` and `reject` transitions and for the lifecycle invariant that makes every state after `DRAFT` immutable, and [Phase 2.7D-1](abap-rap/docs/phase-2-7d-1-cancel-action.md) is SAP runtime-verified for the `cancel` transitions into the terminal `CANCELLED`. [Phase 2.7D-2](abap-rap/docs/phase-2-7d-1-cancel-action.md#phase-27d-2-root-delete-narrowed-to-draft-runtime-verified) narrowed physical root `DELETE` to `DRAFT` and [Phase 2.7E](abap-rap/docs/phase-2-7e-purchase-order-number.md) allocates `PurchaseOrderNumber` on a successful `submit`; both are SAP runtime-verified, and they close Phase 2. `sendToSupplier` and Phases 3–11 remain unstarted.

## Lessons learned

See [LEARNINGS.md](LEARNINGS.md) for studied and practiced concepts, and [PROJECT_STATUS.md](PROJECT_STATUS.md) for evidence and remaining work. Current portfolio wording: “Implemented a managed RAP purchase-order BO in SAP S/4HANA with header/item CDS composition and managed UUID numbering; runtime-verified CRUD, EML, determinations, validations, technical RAP draft, ownership-protected item removal for active and draft instances, an active-only submit transition with state and content preconditions, precheck-enforced lifecycle immutability for header, items and item removal, and approver approve/reject decisions with a recorded rejection reason.” Cancellation, display-number allocation, root-deletion lifecycle rules, supplier dispatch and the integrations remain unimplemented.

Technical references are collected in [SAP sources](docs/architecture/references.md).
