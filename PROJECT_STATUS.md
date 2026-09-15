# Project status

Last updated: 2026-09-15.

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
- Learner manually created and successfully activated all six Phase 1 persistence/CDS objects in SAP S/4HANA using ADT/Eclipse. Phase 1 is complete on that reported activation evidence.
- Reconciled the root currency annotation and child projection provider-contract clause to the two working compiler adjustments; synchronized the Phase 1 guide's full listings.
- Confirmed the configured GitHub remote and that local main tracks origin/main.
- Phase 2.1–2.3: corrected managed BDEF, minimal behavior pool/stub and successful SAP EML CRUD/composition runtime test, supported by the learner's console output.
- Phase 2.7A: root business action `submit`, business `Status` `DRAFT` → `SUBMITTED` on active instances only, runtime-verified on SAP with its draft, status and empty-order rejections and the full Phase 2.5/2.6 regression.
- Phase 2.7B: post-submission commercial immutability through RAP prechecks on root update, item update and `_Items` create-by-association, plus a status guard in `removeItem`, runtime-verified on SAP for active and technical draft instances.

The learner reports Phase 2.4C runtime-verified complete: header totals 1900 → 2650 → 2800 → 2400 → 0, successful relevant COMMIT ENTITIES calls (sy-subrc 0), and `PASS: header totals 1900/2650/2800/2400/0; cleanup complete.` The Phase 2.4C persisted-parent lookup did not support uncommitted-item deletion; Phase 2.6 replaces it with the runtime-verified root `removeItem` path for active and draft instances. Phase 2.5A validateSupplier is also runtime-verified: blank Supplier create/update are rejected during save with `Supplier is required.`, negative commits return nonzero sy-subrc, persistence remains unchanged, and the valid regression flow passes. No independent SAP execution by the assistant is claimed.

## Current phase

**Phase 2.7B post-submission commercial immutability is SAP runtime-verified complete.** Once business `Status` reaches `SUBMITTED`, root commercial updates, item commercial updates, create-by-association and `removeItem` are all rejected, for active and technical draft instances alike. Enforcement is server-side through RAP prechecks declared as operation options — `update ( precheck )` on root and item, `create ( precheck )` on `_Items` — scoped by `%control` so that only user-writable commercial fields are guarded and the framework's own `Status` and `TotalAmount` writes still pass. The learner's run confirms all six rejections with persistence unchanged, root `DELETE` still working on a submitted order, a `DRAFT` control that still recalculates correctly, and a draft taken from a submitted order that carries `SUBMITTED` and rejects both root and item changes. See the [Phase 2.7B guide](abap-rap/docs/phase-2-7b-post-submission-immutability.md). No validation-on-save backstop and no feature control were needed. `PurchaseOrderNumber` is still deferred, root `DELETE` of a submitted order remains allowed by design, and `Activate` over a `SUBMITTED` instance is untested.

**Phase 2.7A root action `submit` is SAP runtime-verified complete.** It moves business `Status` from `DRAFT` to `SUBMITTED` on active instances only, requires at least one current item, and duplicates no Supplier/Quantity/NetPrice logic. The learner's run confirms the active transition with the buffered total unchanged at 1500, `sy-subrc` 0 on commit, `SUBMITTED` persisted in ZJP_PO_H and `PurchaseOrderNumber` still initial. All three rejections returned their exact texts and changed nothing: `Only orders in status DRAFT can be submitted.` for a re-submit, `Submit requires at least one item.` for an order with no items, and `Submit is not allowed on a draft instance.` for both a buffer-only and a saved technical draft, whose totals stayed 1500 and 1900. The Phase 2.5 and 2.6 regressions still pass. See the [Phase 2.7A guide](abap-rap/docs/phase-2-7a-submit-action.md). Phase 2.7B has since closed the editability gap; `PurchaseOrderNumber` allocation remains deferred.

**Phase 2.6 technical RAP draft and `removeItem` are SAP runtime-verified complete.** Target: SAP_BASIS 758 SP01, S4CORE 108 SP01, ADT Core 3.60.3 / Business Object Tools 1.209.0. The supported item-deletion path is the root-bound `removeItem` operation for both active and draft instances. It preserves the complete root `%tky`, verifies that the requested item belongs to that exact root/draft instance, deletes through managed internal EML, and recalculates the header from surviving items, including zero after the last item. Standard child DELETE remains internal. The ownership-negative runtime test returned FAILED for `removeItem` plus `Item does not belong to this Purchase Order.`, while both roots, all items and totals remained unchanged.

**Phase 2.5C validateNetPrice is SAP runtime-verified complete.** It rejects NetPrice < 0 on item create/price change while allowing zero. See the [Phase 2.5C guide](abap-rap/docs/phase-2-5c-net-price-validation.md). The [Phase 2.5B evidence](abap-rap/docs/phase-2-5b-quantity-validation.md) remains runtime-verified: both Quantity negative commits returned 4 with unchanged persistence and the full regression passed.

| Subphase | Status |
| --- | --- |
| 2.1 Behavior Definition | Complete for the current managed BO |
| 2.2 Behavior pool / instance authorization stub | Complete; permissive study policy only |
| 2.3 EML CRUD runtime verification | Complete; learner-supplied successful SAP console output |
| 2.4 Determinations | Complete: Status, item totals and scoped header aggregation runtime-verified |
| 2.5 Validations | 2.5A Supplier and 2.5B Quantity runtime-verified; 2.5C NetPrice runtime-verified |
| 2.6 Technical draft | Complete; technical draft and active/draft `removeItem` runtime-verified on SAP |
| 2.7 Business actions | 2.7A `submit` and 2.7B post-submission immutability runtime-verified; approve/reject/cancel pending |

## Next steps

Phase 2.5C compiler feedback: the console test's elementary PRICES table constructor rejected the integer literal 750 as incompatible with its row type. Both test prices now use explicit CONV zjp_po_i-net_price expressions. The learner's successful SAP run verifies the corrected test; BDEF and handlers were unchanged by this correction.

Phase 2.4C partial SAP evidence: create 1900, Quantity update 2650 and NetPrice update 2800 passed with persistence. The debugger confirmed different ME objects across delete precheck/determination: delete_context went from one row to empty (sy-subrc 4). The stateful bridge is withdrawn. The historical stateless correction read only immutable parent identities from ZJP_PO_I for previously committed active items, then reads current amounts and updates totals through local-mode EML. No direct SQL writes or shared state are used. Delete totals 2400 and 0 subsequently passed in SAP; Phase 2.4C is complete within the documented committed-item scope. Uncommitted-item deletion and technical draft were explicitly unsupported by that lookup. The verified known-root navigation supports the Phase 2.6 replacement, which is now runtime-verified for active, saved-draft and buffer-only draft deletion.

[Phase 2.4B runtime evidence](abap-rap/docs/phase-2-4b-runtime-evidence.md), 2026-09-13: the learner verified 2 × 750 = 1500 before commit, 3 × 750 = 2250 after Quantity change, and 3 × 800 = 2400 after NetPrice change. Each value persisted after commit and the console ended `PASS: item totals 1500/2250/2400; status, CRUD and cleanup.`

1. Preserve the Phase 2.1–2.7B runtime-verified baseline: the `removeItem` deletion boundary, the active-only `submit` transition, and the precheck-based post-submission immutability rules.
2. Do not extend Phase 2.7 to approve, reject, sendToSupplier or cancel until explicitly requested.
3. Leave `PurchaseOrderNumber` unallocated until a released number-range facility is confirmed on the target.
4. Treat root `DELETE` of a submitted order as an open lifecycle question for the cancel subphase, not as a defect.
5. Preserve the supplied version baseline: SAPK-75801INSAPBASIS, SAPK-10801INS4CORE, ADT Core 3.60.3, BO Tools 1.209.0, Eclipse 4.40.0.

## Architecture decisions

The full register is in [ARCHITECTURE.md](ARCHITECTURE.md#architecture-decision-register). Key decisions: custom BO instead of standard MM posting; managed RAP and UUID composition; draft separated from business status; post-commit dispatch with synchronous HTTP first; RAP commercial ownership and CAP supplier-response ownership; standard CI mapping; explicit mock labels and evidence-based portfolio claims.

Phase 1 refinements: ZJP_ naming replaces the provisional names; explicit DEC monetary storage carries CDS currency semantics; optional persistence values use ABAP initial values with later API conversion. The root/child buyer projection redirects both relationships and omits four bookkeeping fields. The subsequent EML run verifies managed writes and root audit maintenance. Concurrent locking and stale-ETag checks remain untested. Phase 2.6 technical draft and active/draft `removeItem` behavior have learner-supplied SAP runtime evidence. The Phase 2.7A active-only `submit` transition and the Phase 2.7B precheck immutability rules are also runtime-verified.

Compatibility baseline: remove the rejected standalone currency-code marker from ZJP_I_PurchaseOrder while preserving the amount reference. Omit the explicit transactional_query provider contract from ZJP_C_PurchaseOrderItem because of its redirected-parent association; retain the root contract. Preserve these working declarations rather than forcing identical root/child syntax.

Current BDEF design: managed implementation in class ZBP_I_PURCHASEORDER unique, strict(2), full persistence mappings, root CRUD, child update/internal-delete with create-by-association, root lock master and child lock dependent, managed UUID keys and one local-instance ETag per entity. Root authorization master (instance) and child authorization dependent by _PurchaseOrder explicitly establish the required hierarchy. The behavior pool is required for instance authorization; standard managed CRUD still needs no handwritten persistence methods. Computed/status/audit/result fields are readonly; managed UUIDs and audit values have framework-driven population, while custom determinations derive status and totals. Phase 2.6 runtime-verifies root `removeItem` with authorization delegated to update, preserving the existing study-only authorization policy. Phase 2.7A adds the parameterless root action `submit` under the same update-authorization delegation; the target accepted it under strict(2) in a with-draft BO and runtime-verified its transition and rejections. Phase 2.7B adds `update ( precheck )` on root and item and `create ( precheck )` on the `_Items` association, with ADT-generated `FOR PRECHECK` handlers scoped by `%control`.

Compiler-driven lessons: (1) authorization master (none) was rejected in this target release; (2) strict(2) requires every entity to participate in the authorization hierarchy; (3) root now uses authorization master (instance); (4) child uses authorization dependent by _PurchaseOrder; (5) the current BO requires an implementation class declaration; (6) the real SAP compiler is authoritative over generic examples. The earlier expectation of activating this BDEF without a custom class is withdrawn. Exact diagnostics are recorded in the [BDEF guide](abap-rap/docs/phase-2-base-managed-bdef.md#compiler-feedback-and-correction).

Additional compatibility lesson: the target-generated authorization request/result structures omit `%assoc-_Items`. Both references were removed from the handler; only `%update` and `%delete` are handled. Available `%...` components depend on the target release and BDEF, so ADT compiler/autocomplete are authoritative. The composition create declaration is retained; runtime behavior is tested through EML rather than inferred from an absent result field.

## Open issues

| ID | Issue | Resolve by |
| --- | --- | --- |
| OI-01 | Exact target recorded: SAP_BASIS 758 SP0001 / S4CORE 108 SP0001; separate ATC evidence not recorded | Target compiler/runtime remains authoritative |
| OI-02 | Number-range availability, default/number assignment and actual draft/ETag behavior | Phase 2 |
| OI-03 | Actual OData metadata, active integration projection, action signatures and concurrency headers | Phase 3, finalized before phase 5 clients |
| OI-04 | CAP REST structured ingestion and bound-action wire behavior | Phase 4 |
| OI-05 | Bidirectional network reachability, HTTP client and outbox persistence/dispatch API | Phase 5 |
| OI-06 | Integration Suite availability, adapter capabilities and conversion/XSD details | Phase 6 |
| OI-07 | Identity provider, XSUAA, technical-client trust and supplier attributes | Phase 8; host-required authentication earlier |
| OI-08 | Exact Event Mesh offering, RAP channel support and dead-letter configuration | Phase 9 |
| OI-09 | API Management access and proxy endpoints | Phase 10 |
| OI-10 | ABAP export/import tooling and package-to-folder serialization | Phase 1 setup, verified with first real export |
| OI-11 | Closed: Phase 1 activation plus Phase 2 EML root/item reads and table snapshots are evidenced | No additional model verification required for this checkpoint |
| OI-12 | Closed: corrected BDEF/pool and EML consumer executed successfully in SAP | See Phase 2.3 evidence |

## Technical debt

The base BDEF, behavior pool, EML consumer, initializeStatus, item/header calculations and Supplier presence validation have successful SAP runtime evidence reported by the learner. Quantity greater-than-zero and nonnegative NetPrice validations are SAP runtime-verified by learner-supplied 2026-09-14 output. The old header aggregation is verified for committed active-item deletion only. Its runtime-verified replacement removes the active-table dependency and supports active, saved-draft and buffer-only draft items. Display number, supplier name and integration fields remain initial. The update/delete authorization stub remains permissive; negative permission cases and standalone root-create/CDS read authorization are not implemented. No other business validation, DCL, display-number allocation, state-dependent editing restrictions or uniqueness enforcement exists yet.

The Phase 2.7A `submit` action and the Phase 2.7B immutability rules are both SAP runtime-verified. Post-submission commercial content is now closed: root and item commercial updates, create-by-association and `removeItem` are all rejected once `Status` is `SUBMITTED`, on active and technical draft instances. Two deliberate gaps remain and must not be reported as solved. `PurchaseOrderNumber` is still not allocated at submission, so submitted orders have no human-readable identity. Root `DELETE` of a submitted order is still permitted; physical deletion rules belong with `cancel` in a later subphase. `SUBMITTED` is terminal for now because approve, reject, sendToSupplier and cancel do not exist. `Activate` over a submitted instance is untested, instance feature control is not implemented, and multi-user concurrency behavior is unexplored.

Intentional scope limits remain EUR-only precision, synthetic master data, single-tenant supplier isolation, manual approval, no order revisions after submission, and no cancellation after delivery request. These are documented constraints, not hidden production capabilities.

Pending engineering work includes machine-readable API schemas, runtime version pinning, real service contract tests, dispatch/reconciliation implementation, operational retention settings, HANA verification, and deployment evidence. They belong to future phases rather than being reported as completed or bypassed.

## Evidence policy

Phase 0 historical verification passed: 16 Markdown documents, 35 relative links/anchors and five JSON examples checked, with matching example identities and amounts. No implementation files existed at that milestone. The Phase 0 ZIP is an unchanged historical snapshot.

Phase 1 SAP evidence: the learner reports manually creating and activating all six objects in ADT/Eclipse, with two documented compatibility fixes. No independent SAP run, data-preview row count, CRUD, draft or EML result is claimed here.

The [GitHub repository](https://github.com/joaopedromribeiro/procurement-integration-hub) is published. Phase 2.6 is committed and pushed to main (ef5883d); local HEAD matched origin/main at that point. The Phase 2.7A `submit` sources and documentation are runtime-verified but not yet committed.

The learner-supplied EML output supersedes the earlier activation assumption: all three commits returned sy-subrc = 0, create/read/update/delete succeeded and final header/item row counts were zero. FAILED/REPORTED were inspected on the successful path; deliberate error, warning, authorization-denial and concurrency cases are not covered.

Historical correction checkpoint: 20 Markdown files, 68 relative file-link targets, 39 BDEF mappings and Git whitespace checks passed. No behavior pool existed at that historical point; it has since been added.

| Evidence level | Meaning | Current project |
| --- | --- | --- |
| Designed | Reviewed architecture, contracts or model | Phase 0 documents and Phase 1 refinements |
| Source prepared | Authored source with local structural review | Six table/CDS definitions, base BDEF, corrected behavior pool, ZJP_CL_PO_EML_TEST and ADT guides |
| Validated on SAP | Activated artifacts and actual runtime outcomes, provenance stated | Six Phase 1 objects; managed BO through Phase 2.7B, including active/draft `removeItem`, the active-only `submit` transition and precheck-based post-submission immutability for root, item, create-by-association and `removeItem`, verified by learner-supplied SAP output |
| Historical activation assumption | Superseded by execution evidence | The corrected BDEF/pool were exercised by the successful EML run |
| Published | Repository available on GitHub | GitHub publication reported; origin and main tracking verified locally; no deployed app claimed |

Historical minimal-class checks: 21 Markdown files, 75 relative file-link targets, 39 BDEF mappings and Git whitespace checks passed. These were local structural checks, not SAP execution.

Historical EML preparation checks passed: 22 Markdown files, 81 relative file-link targets, synchronized guide/source listing, 39 preserved BDEF mappings, absence of the unsupported component from handler source, no direct table writes or local-mode bypass in the console consumer, and Git whitespace checks. All six Phase 1 source hashes match the prior checkpoint. Those local checks are now supplemented by the successful learner-supplied SAP run.

Update this file after each phase with completed work, current phase, next steps, decisions, issues and debt. Record failed checks honestly and keep mocks separate from SAP execution evidence.

Historical runtime-evidence documentation update: 24 Markdown files and 96 relative file-link targets checked; the EML guide still matches the working source. The supplied output contains three successful commit results and the final PASS marker. All ten ABAP/CDS source hashes are unchanged, including all six Phase 1 objects. At that checkpoint the determination artifact was a plan only; implementation now follows.
