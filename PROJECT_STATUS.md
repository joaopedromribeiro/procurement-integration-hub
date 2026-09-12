# Project status

Last updated: 2026-09-12.

## Completed

- Phase 0 architecture, business ownership and complete phase roadmap.
- RAP header/item and CAP logical domain models, draft distinction and lifecycle rules.
- Proposed API boundaries, mapped payload examples, receipts and supplier-response contract.
- Transaction boundaries, retry/idempotency design and error policy.
- Local-versus-SAP environment matrix and future account/service prerequisites.
- Initial README, architecture, API contracts, learning journal and review exercise.
- Repository folders reserved for later source artifacts; local Git initialization.
- Learner confirmed Phase 0 complete and selected SAP S/4HANA with ABAP Cloud for Phase 1.
- Phase 1 local source preparation: ZJP_PO_H, ZJP_PO_I, ZJP_I_PurchaseOrder, ZJP_I_PurchaseOrderItem, ZJP_C_PurchaseOrder and ZJP_C_PurchaseOrderItem.
- Prepared the [step-by-step ADT guide](abap-rap/docs/phase-1-domain-model.md), including complete source, purpose, object names, explanations and tests for each object.
- Updated the architecture, domain model, API compatibility notes, environment record, README and learning journal.

Phase 1 source preparation does not establish SAP activation. No SAP compilation, data preview or ABAP Cloud/ATC check has run through this workspace. No behavior definitions, actions, draft tables, EML consumers, service artifacts, CAP code or iFlows were created.

## Current phase

**Phase 1 — RAP persistence and domain model: source preparation complete; learner activation and verification pending.** Phase 0 is complete. Phase 1 is not yet complete against its SAP activation gate. Phase 2 remains unstarted.

## Next steps

1. Verify the exact S/4HANA/ABAP release and ABAP for Cloud Development package settings; suggested package ZJP_PIH. Record non-secret details in [environments](docs/environments.md).
2. Follow the guide to create and activate ZJP_PO_H; inspect keys/types and preview the expected empty table.
3. Repeat for ZJP_PO_I, then create/activate the base CDS pair and projection pair, recording the actual outcome of each checkpoint.
4. Review structural semantics versus behavior. Continue to Phase 2 only after the learner completes this model step and requests continuation.

## Architecture decisions

The full register is in [ARCHITECTURE.md](ARCHITECTURE.md#architecture-decision-register). Key decisions: custom BO instead of standard MM posting; managed RAP and UUID composition; draft separated from business status; post-commit dispatch with synchronous HTTP first; RAP commercial ownership and CAP supplier-response ownership; standard CI mapping; explicit mock labels and evidence-based portfolio claims.

Phase 1 refinements: ZJP_ naming replaces the provisional names; explicit DEC monetary storage carries CDS currency semantics; optional persistence values use ABAP initial values with later API conversion. The root/child buyer projection redirects both relationships and omits four bookkeeping fields. Standard RAP audit types/annotations are prepared; managed writes, ETags, locking and draft tables remain Phase 2 work.

## Open issues

| ID | Issue | Resolve by |
| --- | --- | --- |
| OI-01 | S/4HANA with ABAP Cloud confirmed; exact release, package permissions and released-type checks pending | Phase 1 activation |
| OI-02 | Number-range availability, default/number assignment and actual draft/ETag behavior | Phase 2 |
| OI-03 | Actual OData metadata, active integration projection, action signatures and concurrency headers | Phase 3, finalized before phase 5 clients |
| OI-04 | CAP REST structured ingestion and bound-action wire behavior | Phase 4 |
| OI-05 | Bidirectional network reachability, HTTP client and outbox persistence/dispatch API | Phase 5 |
| OI-06 | Integration Suite availability, adapter capabilities and conversion/XSD details | Phase 6 |
| OI-07 | Identity provider, XSUAA, technical-client trust and supplier attributes | Phase 8; host-required authentication earlier |
| OI-08 | Exact Event Mesh offering, RAP channel support and dead-letter configuration | Phase 9 |
| OI-09 | API Management access and proxy endpoints | Phase 10 |
| OI-10 | ABAP export/import tooling and package-to-folder serialization | Phase 1 setup, verified with first real export |
| OI-11 | Activation and preview of the six table/CDS objects on the learner's system | Phase 1 |

## Technical debt

Six model source files exist; no application behavior is implemented. Phase 1 intentionally has no business validation, DCL, numbering, calculations or managed audit writes. NOT_REQUIRED without DCL provides no row-level business authorization; implement a policy before claiming a secured service. Initial optional dates/UUIDs/text need deliberate API conversion later. Display-order/item-number uniqueness is not enforced by current table keys.

Intentional scope limits remain EUR-only precision, synthetic master data, single-tenant supplier isolation, manual approval, no order revisions after submission, and no cancellation after delivery request. These are documented constraints, not hidden production capabilities.

Pending engineering work includes machine-readable API schemas, runtime version pinning, real service contract tests, dispatch/reconciliation implementation, operational retention settings, HANA verification, and deployment evidence. They belong to future phases rather than being reported as completed or bypassed.

## Evidence policy

Phase 0 historical verification passed: 16 Markdown documents, 35 relative links/anchors and five JSON examples checked, with matching example identities and amounts. No implementation files existed at that milestone. The Phase 0 ZIP is an unchanged historical snapshot.

Phase 1 verification is limited to local source/document consistency; the guide records pending SAP activation and preview results. No SAP runtime verification is claimed. Git remains on main, with uncommitted files and no remote.

Local checks passed for 17 Markdown documents, 51 relative links/anchors, five JSON examples, all six complete guide/source listings, table-to-CDS field mappings, projected field references and CDS amount/unit references. These checks do not compile ABAP or prove target-system compatibility.

| Evidence level | Meaning | Current project |
| --- | --- | --- |
| Designed | Reviewed architecture, contracts or model | Phase 0 documents and Phase 1 refinements |
| Source prepared | Authored source with local structural review | Six table/CDS definitions and ADT guide |
| Validated on SAP | Activated/deployed artifacts and recorded test results | None |
| Published | GitHub remote or deployed demonstration with accessible evidence | None |

Update this file after each phase with completed work, current phase, next steps, decisions, issues and debt. Record failed checks honestly and keep mocks separate from SAP execution evidence.
