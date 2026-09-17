# Learning journal

This journal distinguishes design, source preparation and successful SAP execution. Phase 1, managed CRUD/composition, Status initialization, item/header totals and Supplier validation are evidenced by the learner's SAP reports. Header deletion aggregation remains limited to previously committed items.

## Phase 0 — architecture foundation

| Concept studied | Explanation in this project | Exercise / interview prompt |
| --- | --- | --- |
| Managed RAP | Framework-managed persistence for a new custom procurement BO | Why use unmanaged RAP for some legacy applications instead? |
| Root and composition | Order owns items and their lifecycle | Why is a supplier association different from an item composition? |
| Draft | Technical editing state separate from a saved but unsubmitted business order | Can an active order still have business Status DRAFT? Yes |
| CDS projections | Consumer-specific interfaces over one underlying BO | Why separate integration from the draft-enabled buyer UI? |
| EML | Typed ABAP interaction with BO behavior and transactional state | Why would a database SELECT miss unsaved item changes? |
| Clean Core | Custom namespace and released dependencies; no modification of standard purchasing internals | Does a custom BO automatically create an SAP MM purchase order? No |
| CAP CDS | CAP's own modeling language, not ABAP CDS syntax | What is shared conceptually, and what cannot be copied directly? |
| Bounded ownership | RAP owns commercial facts; CAP owns supplier decisions | Which application may change net price? RAP before submission |
| REST and OData | REST-facing portal DTOs differ from metadata-driven RAP OData interfaces | Why is the source delivery DTO not raw OData JSON? |
| Integration mapping | Nested target structures, controlled unit conversion and deliberate field omission | How does EA become PCE without silently guessing unknown units? |
| Transaction boundaries | Local commits cannot roll back remote HTTP side effects | What if CAP commits but SAP loses the acknowledgement? |
| Outbox / delivery intent | Save pending work with local business state, send after commit | Why does sendToSupplier not immediately mean SENT? |
| Idempotency | Same logical delivery produces one business effect across retries | How are deliveryId, order UUID and correlation ID different? |
| Error versus business result | Supplier rejection is successful processing of a negative decision | Why is REJECTED different from ERROR? |
| Eventual consistency | Different systems may temporarily show different stages | When is synchronous request/reply still useful? |
| Security boundaries | Authentication identifies callers; authorization restricts actions and supplier data | Why is filtering a list insufficient if direct item URLs are exposed? |
| Evidence-based CV claims | Designs and mocks do not establish service implementation experience | Which claims can be made today? Architecture and contract design |

## Recommended alternatives understood

Managed RAP fits greenfield custom persistence; unmanaged behavior is useful when existing application logic owns saving. Synchronous REST is simpler for the first round trip; messaging improves outage tolerance while adding ordering and recovery concerns. TypeScript supports maintainability in CAP; JavaScript is viable for a smaller service. Graphical CI mapping makes the learning transformation visible; scripts should have a specific reason to exist.

These are project decisions to validate, not claims that one pattern is universally superior.

## Reflection exercise

Explain this scenario without looking at the architecture: an approved order is dispatched, CAP saves it, SAP times out, the supplier accepts, and the receipt is replayed later. Name each local transaction, each stable identity, the status changes and why only one CAP order exists. Compare your answer with [the review walkthrough](docs/phase-0-review.md).

## Future phase entry template

For each completed phase, add: what was built; why the chosen technology fits; important code concepts; test performed; expected and actual result; mistakes and corrections; alternatives considered; interview explanation; and evidence links. Explicitly mark tests run with mocks and tests run on SAP.

## Phase 1 — persistence and CDS implementation, completed

The learner manually created and successfully activated ZJP_PO_H, ZJP_PO_I, ZJP_I_PurchaseOrder, ZJP_I_PurchaseOrderItem, ZJP_C_PurchaseOrder and ZJP_C_PurchaseOrderItem in SAP S/4HANA using ADT/Eclipse. The [ADT lesson](abap-rap/docs/phase-1-domain-model.md) contains the reconciled sources and activation record. The exact release was subsequently recorded during Phase 2.6; the target SAP compiler remains authoritative.

| Concept | Learning point |
| --- | --- |
| Physical versus semantic model | Tables store data; base CDS entities name and relate it; projections tailor a consumer's surface |
| Client-dependent keys | Physical keys include CLIENT; CDS exposes UUID business-instance keys with implicit client handling |
| UUID versus display number | Stable identity differs from a human-readable identifier; a type declaration does not allocate either |
| Root and child | Root defines the top of one composition tree; items use ordinary view entities with a parent association |
| Composition cardinality | Zero-to-many supports preparatory orders; at-least-one on submission is later validation |
| Parent ON condition | Projected parent UUID equals root UUID; the composition derives its relationship from this association |
| Projection redirection | Both child and parent links must resolve within the projected tree |
| DEC and QUAN | Explicit decimal scales preserve price precision; currency and unit annotations supply meaning, not calculations |
| RAP administrative fields | Standard types plus annotations prepare managed audit/ETag behavior; table/CDS definitions alone do not execute it |
| Initial values and SQL NULL | NOT NULL still permits blank supplier and initial date/UUID; external optional values need intentional conversion |
| Access-control annotation | NOT_REQUIRED without DCL does not implement row-level authorization |
| Activation dependencies | Mutually referencing CDS pairs need coordinated activation; an intermediate missing target is not a reason to discard the model |

Actual SAP result reported: all six objects activated successfully after two compatibility corrections. Preview row counts and separate ATC results were not reported. No calculated totals, CRUD operations, draft behavior, EML or service tests have been demonstrated yet.

### Practical compatibility lessons

1. The root base view's standalone currency-code annotation was rejected: "Annotation Semantics.currencyCode is not allowed in view entities." The working source exposes `currency as Currency` and preserves `@Semantics.amount.currencyCode: 'Currency'` on TotalAmount. Semantic intent is preserved using syntax accepted by the target compiler.
2. The child projection's explicit transactional_query provider contract was rejected: "Provider contract not modifiable if view contains 'redirected to parent' associations." Removing that clause from the child allowed activation; the root projection keeps its explicit contract. Matching layers do not necessarily need identical declarations.
3. `_PurchaseOrder : redirected to parent ZJP_C_PurchaseOrder` establishes the child's parent relationship within the projection layer. Removing the relationship to force activation would damage the model; adapting the provider-contract declaration preserves it.
4. CDS annotation eligibility and supported declarations depend on the target entity type and ABAP release. General examples are starting points, not stronger evidence than the actual compiler. Record diagnostics and update both source and teaching material after a confirmed fix. Do not generalize this report into a claim about every SAP release.

Interview explanation to practice: “I manually implemented and activated purchase-order persistence and a composed CDS domain model in SAP S/4HANA using ADT. I corrected incompatible annotation and projection-contract declarations against the target compiler while preserving currency semantics and parent-child navigation.” This describes Phase 1 experience, not managed behavior or integration implementation.

## Phase 2, Step 1 — behavior architecture, explanation only

The [current lesson](abap-rap/docs/phase-2-step-1-behavior-architecture.md) distinguishes the data model (fields/relationships), base Behavior Definition (transactional contract), behavior pool (custom ABAP logic), and projection behavior (consumer-specific reused operations). Root and child belong to one BO with behavior sections under one root-based BDEF.

The exercise identifies which layer owns a field, an enabled operation, its custom validation and its projection exposure. No new ADT object, code activation or EML test belonged to that conceptual step. The learner has since authorized the base BDEF checkpoint below.

## Phase 2 — base managed BDEF, compiler corrections recorded

Prepared one Behavior Definition ZJP_I_PURCHASEORDER with both entities. The [BDEF guide](abap-rap/docs/phase-2-base-managed-bdef.md) explains the source and ADT checks. Key concepts: framework-managed standard persistence with a required behavior pool for instance authorization; explicit mappings from CDS aliases to table columns; root lock master and child dependency; child creation through the parent's composition; framework-generated readonly UUID keys; separate instance ETags even though locking is shared.

Readonly totals, status and display numbers remain initial until later logic supplies them; readonly does not mean calculated. Activation alone cannot prove CRUD persistence or stale-ETag behavior. The original BDEF failed SAP compilation; the corrected BDEF/pool and CRUD flow now have SAP execution evidence; concurrency tests remain pending.

### Practical compiler lessons

1. `authorization master ( none )` is not supported in the learner's target release: the compiler expected global or instance. The earlier recommendation is withdrawn.
2. With `strict ( 2 )`, every entity must explicitly participate in the authorization hierarchy. Removing authorization clauses failed too.
3. The root now declares `authorization master ( instance )`.
4. The child declares `authorization dependent by _PurchaseOrder`.
5. The current BO requires an implementation class declaration: `managed implementation in class ZBP_I_PURCHASEORDER unique;`. Declaring instance authorization introduces an implementation requirement; it does not make standard managed CRUD handwritten code.
6. The real SAP compiler is authoritative over generic RAP examples. Record the failed assumption and exact diagnostic, correct source and teaching material together, and do not claim successful activation before it is confirmed.

### Behavior implementation architecture — understanding confirmed

The [architecture lesson](abap-rap/docs/phase-2-behavior-implementation-architecture.md) explains the BDEF contract versus behavior-pool implementation. ZBP_I_PURCHASEORDER contains the root local handler and get_instance_authorizations. Its keys identify orders; requested permission flags select the decisions to return. Dependent item modifications use the parent's authorization rather than a separate child policy. For standard dependent item update/delete, the root's update authorization applies.

RAP keeps the transaction buffer, standard saving, managed UUID numbering and declared locking; the custom handler supplies permission decisions. No INSERT/UPDATE/DELETE implementation or custom saver is needed. Instance authorization does not cover standalone root CREATE or CDS read access. An empty method is scaffolding, and an explicitly permissive study implementation would be a temporary learning stub, not a secured business service.

Exercise: explain why deleting an item can require the root's update permission, while RAP still deletes the item through managed persistence. The learner confirmed understanding, authorized the minimal implementation and subsequently accepted its corrected activation baseline. The EML runtime checkpoint has passed; status-initialization planning is current.

### Minimal behavior pool — activation baseline accepted

The [current ADT lesson](abap-rap/docs/phase-2-minimal-behavior-pool.md) provides one global behavior-pool class and one root local handler as two source files for the same repository class. The empty global implementation is intentional; the local authorization method has an explicit implementation. No child callback or custom saver is needed.

The handler uses a small READ ENTITIES in local mode to resolve existing keys from the BO's transactional view and forwards read failures/messages. It deduplicates successful identities, then returns the requested update and delete permissions as allowed under the agreed study policy. The local read avoids relying only on database state and is part of this callback, not a separate EML CRUD exercise.

Concepts to explain: `%tky` correlates permission results with instances; `mk-on` is a request flag; `auth-allowed` is a permission decision; requested operations determine which response components are filled. Each existing identity gets one result, while missing identities must be reported as not found. A permissive stub supplies explicit results but checks no actual user roles or authorization objects.

The minimal-class activation checkpoint is now accepted under the learner’s explicit assumption following the correction below. No independent SAP execution is claimed. The subsequent EML runtime checkpoint has passed, with Phase 1 unchanged.

## Phase 2 — authorization component compatibility and EML runtime lesson

The compiler rejected both REQUESTED_AUTHORIZATIONS-%ASSOC-_ITEMS and AUTHORIZATION_RESULT-%ASSOC-_ITEMS because the generated structures contain no such component in the target system. The working root handler now returns only supported %update and %delete decisions. Keep lhc_PurchaseOrder local in the behavior pool. Do not add a field simply because a generic RAP example has it: generated structures depend on release and behavior definition; the ADT compiler and autocomplete are authoritative.

The earlier learner-directed activation assumption is now superseded by successful SAP EML runtime evidence.

The [EML lesson](abap-rap/docs/phase-2-eml-runtime-test.md) now provides a normal console class ZJP_CL_PO_EML_TEST. Its requests use the base BO, with no service and no IN LOCAL MODE bypass in the consumer. Root CREATE plus CREATE BY association connects the new item with %cid_ref and %target; managed UUID assignment is retrieved from MAPPED. READ ENTITIES sees unsaved buffer state, while UUID-filtered SELECT verifies actual persistence.

Learning points: %cid is request correlation, %tky is instance identity, FAILED identifies failures, and REPORTED carries messages of different severities. Check both modify responses and the separate save responses. The console consumer calls COMMIT ENTITIES after each mutation stage. ROLLBACK ENTITIES discards current uncommitted work and cannot undo prior commits.

The run creates one header/item, reads them, commits, changes Supplier from SUP001 to SUP002, commits, deletes that generated root through EML and commits again. Table checks should show 0/0, 1/1, 1/1, then 0/0 header/item rows. Composition child cleanup is verified rather than assumed successful. Totals, business status and display number remain initial until their later logic.

Actual EML result: successful on SAP, with supplied console output ending in PASS. Deep create alone does not validate every authorization path; concurrent locking, stale ETags and negative authorization cases remain untested.

## Phase 2.3 — successful SAP runtime verification

The [evidence record](abap-rap/docs/phase-2-3-eml-runtime-evidence.md) confirms header/item deep creation, generated UUIDs, buffered reads, committed persistence, Supplier SUP001 → SUP002 and root deletion with item cleanup. Three commits returned sy-subrc = 0. %cid, %cid_ref, %target, MAPPED and %tky were exercised, while FAILED/REPORTED remained empty on this successful path. This is SAP execution evidence, not only structural review.

Root audit values were initial in the pre-save read and populated on save; the local last-change timestamp advanced on update. Status, PurchaseOrderNumber, SupplierName and totals were initial/zero by design. Do not classify absent business derivation as a failure or infer complete concurrency/security coverage from this run.

## Phase 2.4A — initializeStatus runtime-verified

Practical compiler lesson: the EML read/update REPORTED tables were not directly append-compatible with the determination's REPORTED table in the target system. Similar component names do not guarantee identical generated RAP response types. The corrected handler declares a temporary table LIKE reported-purchaseorder, uses CORRESPONDING #( DEEP ... ) to map matching components into that target type, then appends it. The second assignment refreshes only the temporary table, so already forwarded read messages remain in the final response. Missing source-only components are not fabricated. The learner subsequently activated and runtime-verified this correction.

The [implementation notes](abap-rap/docs/phase-2-4a-status-initialization-plan.md) describe initializeStatus on root creation during modify processing. A determination derives values; a validation checks acceptability. Internal EML reads the transaction buffer, then updates only blank Status values to DRAFT. The consumer commits. The method belongs in lhc_PurchaseOrder within the existing pool, and ADT generates its target-compatible signature.

Business Status DRAFT is distinct from technical RAP draft. NOT_REQUESTED is the proposed IntegrationStatus default because no delivery is queued, but it is deferred from this first change. Item and header totals follow only after status initialization passes a runtime test. Header aggregation must not rely on determination order, must include unsaved changes, and needs an explicit plan for identifying the parent after an item deletion. Only initializeStatus is implemented. It filters out roots with a noninitial Status and updates the remaining roots through EML in local mode; it does not commit.

The root BDEF declares initializeStatus on modify with a create trigger while keeping Status readonly. The local method reads Status from the transactional buffer, skips populated statuses and updates only Status to DRAFT. The learner reports the extended EML test passed in SAP, verifying DRAFT before and after commit. Phase 2.4A is complete.

## Phase 2.4B — item TotalAmount runtime-verified

The item BDEF declares `calculateTotalAmount on modify { create; field Quantity, NetPrice; }`. A dedicated local item handler reads both inputs from the transactional buffer and updates only readonly TotalAmount through local-mode EML. Updating TotalAmount does not retrigger the determination because TotalAmount is not a trigger field.

The learner verified 2 × 750 = 1500 in the RAP buffer before commit, 3 × 750 = 2250 after a Quantity change, and 3 × 800 = 2400 after a NetPrice change. Every value persisted after its commit. The console ended `PASS: item totals 1500/2250/2400; status, CRUD and cleanup.` This closes Phase 2.4B on [learner-supplied SAP runtime evidence](abap-rap/docs/phase-2-4b-runtime-evidence.md).

## Phase 2.4C — header TotalAmount runtime-verified

The business invariant is header TotalAmount = sum of current item TotalAmount values. Item create/input changes and item delete are child-level triggers because those operations change the aggregate. The implementation identifies affected roots through the composition associations and reads sibling inputs through EML in local mode, so uncommitted transactional values participate.

RAP does not guarantee ordering among determinations. The create/update method therefore derives each rounded item total from Quantity × NetPrice and builds the root sum from those same derived values; it does not wait for another determination's TotalAmount update. Changed item totals and affected root totals are then written in one local-mode EML request. This makes the calculation repeatable and independent of determination order.

The debugger established a second deletion lesson: RAP used different handler ME instances for precheck and determination. A populated instance attribute therefore did not survive, and READ TABLE returned sy-subrc 4. Handler instance lifetime is not transaction lifetime; replacing it with CLASS-DATA would introduce unmanaged shared state. The correction uses local variables and a read-only lookup of the committed item's immutable parent UUID, then EML for current sibling inputs and the root update. This respects the save boundary for previously committed active items, but cannot identify a newly created/uncommitted deleted item. That limitation is explicit; a broader solution needs parent identity in the key or verified target-supported change/before-image access. Error messages from determinations alone do not enforce a save veto.

The extended console test creates totals 1500 and 400 with header 1900, then expects headers 2650 after Quantity change, 2800 after NetPrice change, 2400 after deleting one item and 0 after deleting the last item. It checks the RAP buffer before each commit and database persistence afterward. The learner reports Phase 2.4C runtime-verified complete: header totals 1900 → 2650 → 2800 → 2400 → 0, successful relevant COMMIT ENTITIES calls (sy-subrc 0), and `PASS: header totals 1900/2650/2800/2400/0; cleanup complete.` The persisted-parent lookup still does not support uncommitted-item deletion. No independent SAP execution by the assistant is claimed.

## Phase 2.5A — Supplier required on save, runtime-verified

`validateSupplier on save { create; field Supplier; }` checks new roots and roots whose Supplier changes. A validation reads current data and reports failures; it does not derive a replacement value or commit. The root handler uses local-mode EML, returns the invalid key in FAILED and an error message tied to `%element-Supplier` in REPORTED. FAILED blocks saving; an error message by itself is not a substitute.

This first rule checks presence only, not supplier master-data existence. It applies to active orders with business Status DRAFT too. Technical draft is still absent. A simple text message is used for this checkpoint; translation/message-class work is deferred.

The EML test attempts a blank-Supplier create and a blank-Supplier update of the committed SUP001 order. MODIFY reaches the save validation; COMMIT fails with nonzero sy-subrc and `Supplier is required.` The test rolls back immediately and confirms no invalid create persisted and SUP001 survived the rejected update. The normal create/update/totals/deletion regression flow also passes.

Learner-reported SAP evidence ends with `PASS: Supplier validation rejects blank create/update; valid flow and cleanup pass.` Phase 2.5A is runtime-verified complete.

## Phase 2.5B — Quantity greater than zero on save, runtime-verified

`validateQuantity on save { create; field Quantity; }` checks new items and existing items whose Quantity changes. The item handler reads current transactional values through local-mode EML. For Quantity less than or equal to 0 it adds the item key to FAILED and reports `Quantity must be greater than 0.` against `%element-Quantity`. The FAILED entry vetoes persistence; the validation does not replace the value or commit.

The EML test uses Quantity 0 on deep create and -1 on update. Each MODIFY is expected to reach the save validation, each COMMIT is expected to fail, and an explicit rollback is followed by direct persistence checks. The invalid create must leave no root or item, while the rejected update must preserve Quantity 2, item total 1500 and header total 1900. The existing successful Quantity 3 update, totals, Supplier validation and committed-item cleanup remain in the positive regression flow.

The [Phase 2.5B guide](abap-rap/docs/phase-2-5b-quantity-validation.md) records the learner's successful SAP run on 2026-09-14. Both Quantity negative commits returned 4 with the exact message, unchanged persistence checks passed, and the valid regression/cleanup passed. Phase 2.5C had not started at that checkpoint; its source preparation is recorded below.

The same attachment begins with a failed run: the zero-Quantity create committed with sy-subrc 0 and persisted rows remained after rollback. The change between runs was not supplied, so no activation or implementation cause is inferred. Rollback cannot undo a successful commit; cleanup of that earlier UUID is separate from the later run's successful cleanup.

The negative update test also compares full, primary-key-ordered persistence snapshots before and after the failed save and rollback. This checks sibling and audit fields as well as the expected amounts. Read-only SELECT is justified here to verify database state independently of the RAP buffer; EML remains the only mutation interface.

## Phase 2.5C — Nonnegative NetPrice, runtime-verified

The item save validation validateNetPrice follows the runtime-verified Quantity pattern: local-mode EML read, invalid key in FAILED, exact error text in REPORTED with the NetPrice field marker. The condition is NetPrice < 0; zero and an initial numeric price remain valid. This protects the second input to Quantity × NetPrice without modifying the existing determinations.

The EML extension tests negative-price create/update with full persistence comparisons and a separate zero-price fixture. Committed price transitions 0 → 750 → 0 prove both zero creation and a real update to zero. Buffer and database totals are checked at each positive stage; the fixture is committed before EML cleanup. The original Supplier, Quantity and header-total regression flow is preserved.

The [Phase 2.5C guide](abap-rap/docs/phase-2-5c-net-price-validation.md) records the successful learner-supplied SAP run. Negative NetPrice create/update returned commit sy-subrc 4 with the exact message and unchanged persistence. Zero-price creation and committed prices 0 → 750 → 0 passed buffer/database checks. Supplier/Quantity regression, header totals 1900/2650/2800/2400/0, and both fixture cleanups passed. No Phase 2.6 or later behavior is implemented.

Compiler lesson: the target rejected integer literal 750 in the elementary PRICES table constructor as incompatible with the NetPrice row type. The correction explicitly converts both 750 and 0 using CONV zjp_po_i-net_price before constructing the table. Do not assume an elementary table constructor accepts the same implicit conversions as an assignment to a structured field. The subsequent successful SAP console run verifies the corrected test; no validation logic changed.

## Phase 2.6 — Technical draft investigation history

Business Status DRAFT is not technical draft identity. A technical draft can exist without any active persistence row. The current delete determination therefore cannot derive every draft item's parent from ZJP_PO_I, and a parent UUID alone does not carry the technical draft discriminator.

Draft enablement needs review of aggregate identity/grouping, delete parent lookup, total ETag, draft preparation/activation validations, and generated EML types. Creating draft tables alone does not solve these issues. The target is SAP_BASIS 758 SP0001 / S4CORE 108 SP0001, ADT Core 3.60.3 / BO Tools 1.209.0, Eclipse 4.40.0. The learner now reports zero syntax errors for the draft-enabled BDEF, including total ETag, lifecycle operations, child validations in Prepare and draft associations. At that historical checkpoint, the [Phase 2.6 guide](abap-rap/docs/phase-2-6-technical-draft.md) specified the remaining delete runtime probe. Subsequent evidence and the runtime-verified solution are recorded below.

The generated draft model preserves the current key: ZJP_PO_ID has PurchaseOrderItemUUID as its entity key and PurchaseOrderUUID as a non-key field. Both draft tables include generated %admin data. The previous proposal to add the parent UUID to the child key is withdrawn. Draft support does not itself require that model change, and changing identity is not a substitute for investigating deletion semantics.

The target authorization request exposes %update, %delete and %action-Edit. Prepare is a draft determine action and is not exposed under requested_authorizations-%action in this system. Do not reintroduce %action-Prepare or %assoc-_Items from generic examples. The future draft implementation must handle the supported Edit permission and check its generated result component in ADT.

Target runtime disproved the deleted-child candidate: both child READ and child BY _PurchaseOrder return no rows after delete, with one failed PurchaseOrderItem entry and no reported message. The old navigation fails with NOT_FOUND even for the active BO. Do not implement post-delete child navigation.

The active consumer-side probe establishes the useful direction: capture the complete root %tky before deleting a child, then navigate root BY _Items after DELETE and before COMMIT. For one deletion it returned only item 00010; for the last deletion it returned an empty item collection while the root remained readable. FAILED and REPORTED were empty, %is_draft was off, and the header totals remained 2400 then 0 under the existing active implementation.

ZJP_CL_PO_DRAFT_PROBE first applied that pattern diagnostically to a saved two-item draft and to a draft-only item created and deleted before its first COMMIT. It preserved the generated single child key and used %tky/%is_draft rather than rebuilding technical identity. That probe established navigation behavior; the subsequent `removeItem` implementation and runtime evidence below establish corrected aggregation.

## Phase 2.6 — Known-root technical removal, runtime-verified

The learner verified the same post-delete root navigation for active, saved-draft and buffer-only draft data. Full root %tky remains usable after its child has disappeared; root BY _Items returns surviving items or an empty collection. This supplies the missing parent context without changing the child key. The old handler still reported the committed-parent diagnostic and left draft totals stale at 1500 / 1900; navigation success alone was not aggregate correctness.

The technical root action removeItem now owns both managed deletion and recalculation. Its abstract CDS parameter carries only the item UUID; the action's implicit root %tky supplies the parent and draft identity. The handler checks membership in the root's buffered composition before deletion, uses the returned child %tky for internal DELETE, navigates from the preserved root after deletion, sums surviving item totals and updates readonly root TotalAmount via local-mode EML. Zero surviving items explicitly means zero total.

Declaring child DELETE internal prevents external consumers from bypassing the aggregate-maintaining operation. This is a Phase 2.6 technical operation, not a Submit/Approve/Send business action. The action delegates authorization to root update; the existing study-only permission stub is unchanged. RAP still performs locks and persistence. No direct SQL lookup, draft-table access, handler-instance bridge or CLASS-DATA is needed.

The existing create/input-change calculation now groups by full %tky and separates siblings by %is_draft as well as parent UUID. Arithmetic and determination triggers are unchanged; Supplier, Quantity, NetPrice, initializeStatus and authorization method bodies are preserved. An active UUID and its draft UUID represent different transactional instances.

Nested EML failure does not imply automatic rollback of earlier successful changes inside an action. All stages check FAILED and forward REPORTED; any failed action requires caller rollback before commit. A foreign item is rejected before any mutation. The active regression checks this boundary, while the draft test checks totals before and after saving each removal.

Target lessons retained: draft root CREATE and CBA are separate calls; CBA uses the mapped full draft parent key and explicit draft targets. Discard uses the target-generated %key signature with implicit draft selection, and separately declared FAILED/REPORTED responses. Do not mechanically exchange %key and %tky.

These are implementation decisions and locally reviewed sources. Only the earlier navigation probes and Phase 2.5 baseline have SAP evidence. The learner's SAP run verifies the `removeItem` action, internal DELETE boundary, draft-aware grouping and active/draft runtime assertions. Active removal reaches totals 2400 then 0; buffer-only draft removal reaches 1500 then 0; saved-draft removal reaches 1900, 1500 and 0 with persistence checks and cleanup. Phase 2.6 is complete. Phase 2.7A followed and is recorded below.

The ownership-negative test also establishes that rejection is side-effect-free: FAILED identifies `removeItem` on the requested active root, REPORTED contains `Item does not belong to this Purchase Order.`, and both roots, all three items and totals remain unchanged. The earlier 53-character text was truncated to 50 characters by `new_message_with_text` on this path. That is empirical, target- and path-specific behavior rather than a documented universal limit; keeping business messages short and verifying the returned text preserves exact testable wording.

Technical RAP draft remains separate from business `Status = 'DRAFT'`. `%is_draft` and draft persistence describe an editing instance; the business status describes the procurement lifecycle. The runtime tests preserve and check both concepts rather than treating one as the other.

## Phase 2.7A — Root business action `submit`, runtime-verified

A business action is not a technical operation. `removeItem` maintains an aggregate; `submit` changes what the order *is* in the procurement lifecycle. Both are instance-bound root actions delegating authorization to root update, but their preconditions differ in kind: `removeItem` asks whether an item belongs to this instance, while `submit` asks whether this instance is in a state that may advance.

Active-only is a deliberate boundary, not a limitation of the framework. A technical draft is an editing session, so submitting one would persist a lifecycle decision over data that has not necessarily passed any `on save` validation. The supported path is framework `Activate`, which runs `Prepare` and therefore all three validations, followed by `submit` on the resulting active instance. The handler enforces this by rejecting `%tky-%is_draft = mk-on` before it reads anything, rather than by a BDEF clause whose syntax is unconfirmed on this target. Handler-side enforcement also survives any future projection that exposes the action.

Preconditions must not restate business rules that already have owners. Every committed active root has passed `validateSupplier`; every committed active item has passed `validateQuantity` and `validateNetPrice`; a value cannot change without re-triggering its own validation. Re-reading Supplier, Quantity and NetPrice inside `submit` would create a second copy of each rule that could silently drift from the first. The action therefore checks only what no validation covers: draft flag, business `Status`, and the existence of at least one item. The at-least-one-item check reads the live composition through `BY \_Items`, so an order emptied by `removeItem` is rejected at submission time rather than at creation time.

Requiring `Status = 'DRAFT'` rather than merely "not already SUBMITTED" makes the transition explicit and closed. A second `submit` is rejected with a specific message instead of quietly succeeding, and every future status added by 2.7B onward is excluded by default rather than by omission.

Deferring is a design decision worth recording. Submission is the natural allocation point for `PurchaseOrderNumber`, but no number-range facility is confirmed on this target, and inventing a placeholder identity would create migration debt. Likewise, making commercial fields read-only after `SUBMITTED` requires instance feature control whose generated components vary by release, and it would change the runtime-verified `removeItem` path. Both are separated into their own subphases with their own evidence. The honest consequence, recorded rather than hidden, was that a submitted order remained editable at this checkpoint; Phase 2.7B closed that, and `PurchaseOrderNumber` is still deferred.

Action rejections carry `%op-%action-submit` and a message, never an `%element` marker; element markers belong to validations, which point at a field. An action is not a nested database transaction, so every rejection leaves the buffer untouched and the caller must roll back. The console tests assert the FAILED table and the buffer contents directly instead of inferring a veto from REPORTED.

The learner's SAP run confirms all of this. The active transition reached `SUBMITTED` with the buffered total unchanged at 1500, committed with `sy-subrc` 0 and persisted, while `PurchaseOrderNumber` stayed initial. Each rejection returned its exact text and changed nothing: `Only orders in status DRAFT can be submitted.` on re-submit, `Submit requires at least one item.` on an order with no items, and `Submit is not allowed on a draft instance.` on both a buffer-only and a saved technical draft, whose totals stayed 1500 and 1900. The Phase 2.5 validations and the Phase 2.6 active and draft removal tests still pass, so the new action did not disturb the earlier baseline.

The run settles four declaration questions for this target: a parameterless `action ( authorization : update ) submit;` activates under `strict ( 2 )` in a `with draft` behavior definition; the generated handler receives the complete root `%tky` including `%is_draft`; `%op-%action-submit` exists in the generated root FAILED and REPORTED structures; and `EXECUTE submit FROM VALUE #( ( %tky = ... ) )` is accepted for an action with no parameter. Each action contributes its own `%op` component, so this is now evidence for `submit` specifically, not an inference from `removeItem`.

The identical message on both draft cases is the useful detail. A buffer-only draft and a saved draft differ in persistence but not in `%is_draft`, and the guard reads the flag rather than the storage, so both are rejected the same way and neither is mutated. Rejecting before the first read also means a draft call performs no EML at all.

Shortening the three asserted texts to 46 characters or fewer before the run was the right call: they were returned in full. The Phase 2.6 limit still stands as a constraint to design within, since a 53-character text was truncated to 50 on this target and the console tests compare returned text exactly.

Runtime verification covers the transition and its rejections, and nothing more. `PurchaseOrderNumber` was still unallocated, and post-submission editing was still open at this checkpoint. Verifying an action does not verify the restrictions that ought to surround it; Phase 2.7B supplies those separately, with its own evidence.

## Phase 2.7B — Post-submission immutability through prechecks, runtime-verified

The probe round mattered more than the implementation. Four questions were answered with target evidence before a line of enforcement was written, and two of the answers collapsed whole branches of the design.

**Precheck is an operation option, not a derived type.** Autocomplete for `STRUCTURE FOR` and `TABLE FOR` proposes no type named "precheck" on this target. The enforcement is declared as `update ( precheck )` on root and item and `create ( precheck )` inside the `_Items` association, and ADT generates `METHODS precheck_update FOR PRECHECK IMPORTING entities FOR UPDATE purchaseorder`, its item twin, and `METHODS precheck_cba_items FOR PRECHECK IMPORTING entities FOR CREATE purchaseorder\_items`. Every signature was generated by ADT and used verbatim. Guessing any of them would have failed, exactly as guessing `%tky` for the framework draft actions failed earlier.

**`%control` is what makes the rule safe.** The `FOR UPDATE` line type exposes `%cid_ref`, `%control`, `%data`, `%is_draft`, `%key`, `%pky`, `%tky` and the entity fields, with an individual `%control` flag per field. Scoping the check to the five user-writable root fields and the seven user-writable item fields means the rule cannot fire on `submit`'s own `Status` write or on the `TotalAmount` writes of the determinations. A blanket "no update when SUBMITTED" rule would have broken Phase 2.7A on its own transition. The field list, not the operation, is the safety mechanism.

**An unresolved question stopped mattering once the design was scoped correctly.** Whether a precheck executes for an `IN LOCAL MODE` request was never determined. It did not need to be: under either answer the outcome is the same, because the only local-mode writes this behavior pool performs touch readonly fields that no guarded list contains. Designing so that an open question becomes irrelevant is cheaper than answering it, and the full regression passing unchanged confirmed it empirically.

**Two probe results decided the draft design.** `Edit` on a `SUBMITTED` active order succeeds and the resulting technical draft carries `Status = SUBMITTED`, so the ordinary rules guard it through `%tky` with no extra logic. And `submit` on an active instance is refused by the framework with `%FAIL = LOCKED` while a saved draft of it exists. Together these mean a draft coexisting with a submitted active instance can only have been created after submission, so no active-counterpart lookup and no `Edit` gate are needed. Both were earlier assumed to be necessary; both were dropped on evidence.

**The limits of that evidence are part of it.** The `LOCKED` result is single-user, from one console flow — a concurrency outcome, not a business rule, and no rule was weakened because of it. `Activate` over a `SUBMITTED` instance was never reached and is not claimed. Neither observation generalizes beyond SAP_BASIS 758 SP01 / S4CORE 108 SP01.

**Mechanisms rejected, and why.** Instance feature control is advisory for UI rendering and `IN LOCAL MODE` bypasses it, so it could never be the enforcement layer; it stays available as optional UX. A validation-on-save backstop would have added no coverage, fired late, and risked interfering with the root-delete cascade through a delete-triggered validation. Authorization was the wrong tool entirely: `SUBMITTED` is instance state, not a permission.

**Root `DELETE` stays allowed, and the reason is concrete.** Removing a submitted order belongs to `cancel` in the documented lifecycle, and the Phase 2.7A regression deletes its own submitted fixture during cleanup. Blocking deletion here would have broken runtime-verified coverage in the same change that added enforcement. A half-rule that costs regression coverage is worse than a stated gap. Phase 2.7D-1 has since added `cancel` without touching `DELETE`, and the deletion policy became Phase 2.7D-2 for exactly the reason stated here: the teardown cost is real and deserves its own round.

The learner's SAP run verifies all six active rejections with persistence unchanged, root `DELETE` still working on a submitted order, a `DRAFT` control that still recalculates correctly, and a submitted-order draft that rejects both root and item changes. Every Phase 2.3–2.7A marker still printed, and no `STOP` marker appeared. `PurchaseOrderNumber` remains unallocated.

## Phase 2.7C — Approver decisions and the lifecycle invariant, runtime-verified

The transitions were the easy part. `approve` and `reject` reuse the `submit` shape exactly: draft-instance guard, local-mode status read, transition check, one local-mode update of readonly fields. `reject` adds a parameter through a new abstract entity, following the `ZJP_A_RemoveItem` pattern proven in Phase 2.6. Nothing about either action needed new target evidence, which is what a stable pattern is for.

**The real work was correcting the rule Phase 2.7B had written.** That subphase rejected changes when `Status = 'SUBMITTED'`, which was right while `SUBMITTED` was the only state after `DRAFT`. The moment `APPROVED` and `REJECTED` became reachable, an enumerated rule would have needed extending for every future state, and would have silently permitted edits to any state someone forgot to list. Inverting it — *editable only while `DRAFT`* — closes every state after `DRAFT` at once, including states not yet invented. A rule stated as an invariant survives the lifecycle growing; a rule stated as a list of forbidden states does not.

**Inverting a rule can break the cases the original accidentally allowed.** The naive inversion would reject instances whose `Status` is still `INITIAL`, because `initializeStatus` is a determination on modify and a newly created root can be readable before `DRAFT` is established. The old rule passed that case by accident; the new one had to pass it on purpose. The carve-out is written into the code as a transient framework accommodation, not folded into the business rule, and the comment says so — `INITIAL` is not an editable business state, it is the gap between creation and the determination that sets `DRAFT`. Documenting the distinction matters more than the two lines of code: a future reader must not read `INITIAL` as a lifecycle value.

**Eligibility outranks parameter validation.** The first version of `reject` checked the missing reason before reading the order, so a technical draft with an empty reason failed for the wrong reason and an already-approved order reported a missing parameter rather than an ineligible state. Reordered, the precedence is draft → unreadable → wrong status → missing parameter. A caller should learn the most fundamental reason their request is invalid, not the first one the code happened to test.

**Changing a rule means changing its messages, and messages are test contracts.** The four Phase 2.7B texts named `SUBMITTED` and became wrong the moment the rule generalized. Rewording them invalidated four exact-text assertions in a runtime-verified test class — and because only the production objects were activated at first, the stale SAP test classes reported `STOP: a submitted-order mutation was not rejected.` while every rejection in the log had actually fired correctly. The console output showed the right behavior and the wrong verdict. Test assertions that compare exact message text are precise but brittle; when a message changes, the class must be re-activated in the same round as the handler, or the evidence lies.

**On message length, a correction to earlier wording.** The target truncated one 53-character text to 50 characters on the Phase 2.6 path. That is empirical, target- and path-specific behavior. Earlier notes called it a 50-character limit, which overstates it: no documented universal limit was ever established. The durable practice is to keep messages short and verify the returned text in the console, not to trust a number.

The learner's SAP run verifies both transitions with persistence, `RejectionOrigin = APPROVER`, the reason stored verbatim, every re-decision and every commercial mutation on `APPROVED` and `REJECTED` rejected, a reason-less reject that wrote nothing, and a technical draft of a submitted order refusing updates and both decisions. `PurchaseOrderNumber` stayed initial throughout. Authorization remains the permissive study stub, so "approve" names a transition and not an access control — a distinction worth repeating wherever the word appears.

## Phase 2.7D-1 — The cancel action, runtime-verified

**The best measure of Phase 2.7C's invariant is how much code `CANCELLED` needed: none.** A fourth business state became reachable and not one precheck, not `removeItem`, not a single message text had to change. Commercial immutability, the four rejections and their exact texts all applied on the first run. Under the enumerated Phase 2.7B rule that named `SUBMITTED`, this subphase would have meant editing four handlers and re-verifying four assertions. A rule stated as an invariant pays out later, silently, in the work it does not create.

**An allow-list and a deny-list need different treatment of the same value.** The prechecks are deny-rules, so they need an explicit `INITIAL` carve-out or creation breaks. `cancel` is a positive allow-list of `DRAFT`, `SUBMITTED` and `APPROVED`, so `INITIAL` is excluded by construction — no carve-out, no comment, no risk of a reader mistaking it for a business state. Same value, same system, opposite handling, and both correct. The shape of a rule decides which cases need saying out loud.

**Not implementing a guard can be the more honest engineering choice.** The domain model says `APPROVED` may be cancelled only before delivery was requested. `IntegrationStatus` and `DeliveryId` exist in the model but are readonly and no Phase 2 handler writes them, so the condition is not merely false — it is unrepresentable as true. A guard would have been a tautology that could never fire, could never be tested negatively without forbidden direct SQL, and would read as enforcement in review while carrying no evidence. Writing it down as a Phase 5 obligation attached to `DeliveryIntent` is worth more than writing the branch. A defensive check you cannot exercise is not defense, it is decoration.

**Splitting a subphase is cheaper than an unattributable failure.** Phase 2.7D was planned as `cancel` plus the root `DELETE` narrowing. Narrowing deletion breaks the teardown of five fixtures that are deliberately terminal at cleanup — and there is no lawful managed replacement, because direct SQL is forbidden and `CANCELLED` would not be deletable either. Bundling a new transition with a teardown rewrite in two runtime-verified classes would have produced one activation round where a red console could mean either. The transition shipped alone, touching no existing test line: 609 insertions, zero deletions.

The learner's SAP run verifies all three cancellable sources with persistence and totals unchanged at 1500, `PurchaseOrderNumber` still initial, `REJECTED` refusing cancel while keeping `RejectionOrigin = APPROVER`, a `CANCELLED` order refusing re-cancel, `submit`, `approve`, `reject` and every commercial change, and a `SUBMITTED` technical draft refusing cancel. Root `DELETE` remains open at any status, which is a stated gap and not an oversight. Authorization is still the permissive study stub, so `cancel` names a transition and not an access control: any user may cancel any order.

## Phase 2.7E — PurchaseOrderNumber allocation on submit, runtime-verified

**Three documents said three different things, and nobody noticed until someone tried to implement.** The domain model said allocate on first active creation/save. The architecture register said determinations allocate display numbers. The Phase 2.7A guide and these notes said submission is the natural point. Each was written at a different time, each was reasonable alone, and the contradiction was invisible because the field was never implemented. A deferred decision does not stay neutral — it quietly accumulates inconsistent statements in every document that has to mention it. The investigation step that preceded this subphase existed precisely to surface that, and it was worth more than the code that followed.

**Submission beats save as the allocation point, for a reason that is about people rather than code.** A number drawn at creation is consumed by every abandoned draft. Submission is the first moment the order becomes a document other people cite in an email or a phone call, so that is when it earns an identity. The cost is that an order cancelled straight from `DRAFT` never receives a number — which is correct under the rule and had to be asserted deliberately, because it looks like a bug to anyone who assumes every persisted row has a display number.

**The target's own return type contradicts its own configuration.** `CL_NUMBERRANGE_RUNTIME` returns `NRLEVEL` as twenty digits while the configured `ZJP_PO` interval is eight. Taking the last eight characters is correct here and would be a silent corruption on a wider interval, so the handler checks that the leading twelve digits are zeros and fails the action otherwise. Under the configured interval that branch is unreachable, which is exactly why it costs nothing to keep: the guard is not there to fire, it is there so the truncation is a stated assumption rather than a hidden one.

**Deciding not to read a return code is also a decision.** The isolated probe returned a blank code, and SAP's documented non-blank values include a near-exhaustion warning where the number is still valid. Requesting `returncode` and treating any non-blank value as failure would refuse valid numbers as the interval fills; treating it as success would make the parameter decoration. With no runtime evidence for the non-blank paths, the honest choice was to request only `number`, rely on `CX_NUMBER_RANGES` for hard failures, and write the omission down as a reviewable decision rather than bury it.

**A number is drawn before the buffer update, so a failed save consumes it.** That gap is accepted by design — gaps are valid, numbers are never reset or reused — but it is worth naming, because the alternative people reach for is reusing the number, and that is how duplicate business identities get created.

**Optional parameters can carry a rule instead of a flag.** `expected_number` was added to two verification helpers with the semantics *initial means the row must still carry no number*. Every `DRAFT`-stage call site kept working untouched, and only the submitted-and-later sites had to pass anything. Choosing the default so that the common case needs no argument turned a twenty-call-site change into a seven-call-site change.

**The run confirms it, and the summary line nobody planned is the most useful output.** The final lifecycle table shows `SUP012 CANCELLED <initial>` beside five numbered orders. That blank is the rule working — a draft cancelled before submission never becomes a document anyone cites — but it is exactly the kind of thing that reads as a bug to the next person, which is why the regression asserts it on purpose and the documentation says so twice. The gap between `PO00000002` and `PO00000004` is the second such artifact: numbers are drawn before the buffer update, so a rolled-back request consumes one. Both were predicted before the run and both appeared; predicting an oddity beforehand is what turns it from a defect report into evidence.

**What the draft probe added was not planned at all.** A technical draft created from a `SUBMITTED` active order carried `PurchaseOrderNumber = PO00000009` along with `Status = SUBMITTED` and total 1500. Phase 2.7B had established that a draft inherits the business status; this extends it to the business identity. Nothing depends on that yet, but it is the kind of fact a Phase 3 OData client will meet on its first day.

**Paths that were never executed are still paths.** The two number-range exception branches and the wider-than-eight-digits guard did not fire in this run, and cannot be made to fire without breaking the configuration. They are compiler-accepted and reasoned, not runtime-exercised, and the documentation says so rather than letting a green console imply otherwise.

With this subphase Phase 2 is complete: the number range object, interval and 20-digit return behavior are learner-supplied target evidence, and the allocation, the formatting guard and the full regression all ran green on SAP.

## Phase 3.1 — OData V4 exposure, runtime-verified

**The best evidence that Phase 2 was layered correctly is how little Phase 3.1 had to do.** One ADT-generated projection behavior definition, one service definition, one binding. No handler changed, no rule moved, no test was touched, and the whole Phase 2 regression stayed valid without being re-run. A service layer that has to restate business rules is a sign the rules were in the wrong place to begin with; this one declares `use` and nothing else.

**The proof of that arrives as a string.** Approving an already-approved order over HTTP returns 400 with `Only submitted orders can be decided.` — byte-identical to the text the Phase 2.7C handler emits and the console test asserts. Two transports, one enforcement point. The same holds for `Only draft orders can be changed.` on a PATCH to a submitted order's draft.

**A compatibility adjustment that looked like debt turned out to be correct.** The child projection has no `provider contract transactional_query`, because the target compiler rejected that clause alongside `redirected to parent` back in Phase 1. Going into Phase 3 that was the highest-risk unknown — the one thing that might block a transactional service. It did not. Root contract plus redirected-to-parent child works here. The lesson is not that the worry was wasted; it is that naming the risk in advance made the answer cheap to obtain and impossible to miss.

**`Activate` and `submit` are different events, and OData shows it plainly.** A created order activates into business `DRAFT` with a blank number, and only `submit` returns `PO00000010`. Anyone watching the HTTP traffic can see that leaving the editing session is not the same as becoming a business document. The Phase 2.7E rule was argued on paper; here it is observable from outside the system.

**`Edit` succeeding on a submitted order still reads like a hole, and still is not one.** The draft is created, inherits `Status = SUBMITTED` and `PurchaseOrderNumber = PO00000010`, and refuses the first content change. Phase 2.7B established the mechanism; Phase 3.1 adds that the number is inherited too. It is worth saying out loud in every document that touches it, because the first reaction to "Edit returned 201" is always that something is wrong.

**The environment had the last word on publishing.** Client 100 is a Customizing client, so ADT refused to publish locally and the service group went through `/IWFND/V4_ADMIN`. No amount of correct modelling avoids that, and it is the kind of detail that costs an afternoon if it is not written down.

**Metadata can advertise more than the rules permit.** `__OperationControl` reports bound actions as available on orders whose lifecycle would reject them. That is a UX gap, not a rule defect — the handlers still return 400 — and the remedy, dynamic feature control, is deliberately not being reached for. Phase 2.7B already settled that feature control is advisory and bypassed by `IN LOCAL MODE`, so it can improve what a UI offers but can never be the thing that enforces. Implementing it unscoped would blur exactly the line this project has been careful to keep sharp.

`OptimisticConcurrency` now appears in the metadata, which makes a stale-ETag conflict reachable for the first time in the project. Nothing exercised one, so nothing is claimed; it stays open as OI-13.

## Phase 3.2 — UI annotations, runtime-verified

**An annotation placed three phases ago did the work.** `TotalAmount` renders as EUR in the Fiori List Report with no currency annotation anywhere in the metadata extension. `@Semantics.amount.currencyCode: 'Currency'` was put on the base view in Phase 1 for correctness reasons that had nothing to do with a UI, and it propagates through the projection, into OData, and out to Fiori on its own. Semantic annotations are not decoration on the data layer; they are the thing that lets every layer above stop re-stating what a field means.

**The ADT skeleton was placeholders all the way down, exactly as suspected.** `@Metadata.layer: layer` and `element_name` are literal placeholder tokens, not values. Autocomplete supplied the real set — `#CORE`, `#CUSTOMER`, `#INDUSTRY`, `#LOCALIZATION`, `#PARTNER` — and `#CUSTOMER` activated. Refusing to guess cost one lookup; guessing would have cost an activation failure and a wrong line in the repository.

**Activating a metadata extension refreshes `$metadata` without republishing the binding.** On this target that is worth more than it sounds: publishing needed `/IWFND/V4_ADMIN` because client 100 is a Customizing client, so a per-change republish would have made annotation work slow enough to discourage iteration. Establishing this early is what makes it reasonable to switch from one-annotation-at-a-time to activating the extension as a coherent unit.

**The Object Page title is the identity split made visible.** Before `@UI.headerInfo` existed, Fiori titled the page with `PurchaseOrderUUID`. Afterwards it shows `PO00000002`. Phase 2.7E argued on paper that the UUID is the technical key a client addresses while the number is what a person recognises; a UI with no annotations shows what happens when nothing tells the presentation layer which of the two a human should see.

**Restraint is a design decision that has to be made deliberately, because the default is clutter.** The root projection exposes twenty-four elements. Nine of them — `SupplierName`, `SupplierResponse`, `EstimatedDeliveryDate`, `IntegrationStatus`, `OrderRevision` and the four `LastError*` fields — are never written by any Phase 2 code and would render as permanently empty boxes. Annotating everything available would have produced a form that teaches a user nothing and quietly implies capabilities that do not exist. They get annotated in Phase 5, when they start carrying values.

**Keeping the unverified surface small is worth an aesthetic compromise.** `RejectionOrigin` and `RejectionReason` deserve their own titled section, which means `@UI.fieldGroup`, a qualifier and a `#FIELDGROUP_REFERENCE` facet — three more constructs that have never been activated here, in a round that already carries two. Putting them at the end of `@UI.identification` reads slightly worse and fails in exactly one fewer way. Promote them once identification and facets are proven, not before.

**Keeping the repository honest paid off as a diagnostic, not just as bookkeeping.** The Object Page stayed empty, and the obvious reading was that `@UI.facet` or `@UI.identification` had been dropped somewhere between CDS and OData. The real answer was that the root extension active in ADT was still the baseline: those annotations had never been activated at all. That took one comparison to establish, because the repository `.ddlx` holds the active state and nothing else — the annotations in `$metadata` were exactly the ones the repository showed as activated. Had the candidate source been committed as though it were live, the same symptom would have pointed at a framework bug that does not exist. A repository that tracks what is really deployed answers "is this a defect or was it never switched on?" for free; one that tracks intentions cannot answer it at all.

All of it is now verified: `#CUSTOMER`, `@UI.headerInfo`, `@UI.lineItem` on both entities, `@UI.selectionField`, `@UI.identification`, and `@UI.facet` with `#IDENTIFICATION_REFERENCE`, `#LINEITEM_REFERENCE` and `targetElement: '_Items'`.

**Two entity-level annotations, two different placement rules.** `@UI.headerInfo` activates at the top of a metadata extension, above `annotate entity`. `@UI.facet` in that same position is rejected outright — ADT returned 11 errors of the form `Annotation 'UI.facet.id' used at wrong position (wrong scope)` — and belongs inside the `annotate entity … with { }` body instead. Both annotations describe the entity rather than a single element, so assuming they shared a scope was the natural guess and it was wrong. The compiler was the only thing that could have said so. Moving the block and changing nothing else activated cleanly and rendered both Object Page facets on the first try, which is the useful shape of a placement error: once the diagnostic is read literally, the fix is mechanical and complete.

**The Phase 1 semantic annotations finished the job nobody asked them to do.** The item table renders `2 EA`, `750.00 EUR` and `1,500.00 EUR` with no unit or currency annotation anywhere in either metadata extension. `@Semantics.quantity.unitOfMeasure`, `@Semantics.unitOfMeasure`, `@Semantics.amount.currencyCode` and `@Semantics.currencyCode` were put on the base views in Phase 1 for modelling correctness, years of project-time before a UI existed, and they propagate through the projections into OData where Fiori reads them. The provisional decision to leave `UnitOfMeasure` and `Currency` out of the item columns is now evidenced rather than assumed: adding them would duplicate what the framework already renders. Annotating meaning at the lowest layer that owns it means every layer above gets it for free.

**A negative result kept its place in the record.** The invalid top-level `@UI.facet` placement stays documented alongside the working one. Deleting it once the correct form was found would have saved a paragraph and cost the next reader the same afternoon, since the wrong form is the one that looks right by analogy with `@UI.headerInfo` sitting directly above it.

## Phase 4.1 — CAP foundation, locally runtime-verified

**The evidence changes kind here, and that is worth saying out loud.** Everything from Phase 1 to Phase 3.2 rests on SAP runtime output supplied by the learner; this project's rule has been that no feature is verified without it. Phase 4 runs on a laptop, so its commands can be executed directly and their output pasted in full. That is genuinely stronger in one sense — nothing is relayed — and weaker in another, because a local Node.js process proves nothing about an SAP system. Recording it as "locally runtime-verified" rather than folding it into the same words used for the ABAP phases keeps the two claims distinguishable later, when a reader is deciding how much a status line is worth.

**A foundation that cannot start cannot be verified.** The instinct for a "foundation only" subphase is to write the manifest and stop. CAP refuses to serve an empty model, so that version of the foundation has no completion gate beyond "the files exist", which is exactly the kind of claim this project has been avoiding. One function, no entity, no persistence access, served over the adapter the later phases will use, converts the subphase from an assertion into a test. It also has to be small enough that it never becomes the thing being designed: the health service can be deleted in Phase 4.4 and nothing will notice.

**The error message pointed at the wrong layer, twice.** A correct TypeScript handler that CAP never loads reports `501 - Service "HealthService" has no handler for "ping"` — which reads as a missing handler, not as a runtime that was never told to look for `.ts` files. CAP chooses its implementation extensions from the `CDS_TYPESCRIPT` environment variable, which its own CLI sets and `node --test` does not. Separately, `cds.test(...)` failed with `Cannot find module '@cap-js/cds-test'` thrown from inside `@sap/cds`, which looks like a broken framework rather than a devDependency that moved out of the main package in version 10. Both diagnostics were accurate and both named the wrong suspect, and in both cases the fix was one line. Reading the framework source — `lib/srv/factory.js` and `lib/test/cds-test.js` are each a few lines — settled both faster than any amount of reasoning about what should have worked.

**Typechecking caught the API errors before any of them ran.** The first draft of the foundation test called `cds.shutdown()` and `cds.test.GET(...)`. Neither exists. `tsc --noEmit` rejected both with the real type shapes, which is the entire argument for ADR-008 arriving on the first file written rather than on the first bug hunted. The `Test` class turned out to extend `Axios` and expose `then`, and reading that off the type definition was quicker than reading the docs.

**Deferring `@cap-js/cds-typer` was the same restraint as Phase 3.2's annotation set.** It belongs to a TypeScript CAP project and it would have installed cleanly, and with no entities it would have generated an empty directory — a tool in the manifest that demonstrably does nothing. The `#cds-models/*` path mapping is in `tsconfig.json` because the cost of adding it now is nothing and the cost of forgetting it in Phase 4.2 is a confusing import error. Wiring a path is not the same as installing a generator with no input.

## Phase 4.2 — CAP domain model, locally runtime-verified

**The model was already written; the work was finding it.** The instinct on reaching "build the CAP entities" is to design them from the business problem, and a prompt listing plausible field names makes that feel confirmed. But `docs/architecture/domain-model.md` has carried a CAP persistence table since Phase 0 — every field, size and scale, plus the three uniqueness rules — and `API_CONTRACTS.md` carries the mapping that explains why each portal name differs from its SAP counterpart. Implementing a specification that already exists is less satisfying than designing one and is worth strictly more: the ingestion contract in 4.3 will land on fields that were defined together with it, rather than on fields invented two phases later that happen to look similar.

**The field list is where the ownership boundary is actually enforced.** ADR-004 has said "RAP owns commercial facts, CAP owns the supplier response" since Phase 0, and it is easy to agree with in prose while quietly violating it in a schema. The portal has no `CompanyCode`, `PurchasingOrganization` or `PurchasingGroup`, and no `supplierName` on the order — not because they would be hard to store, but because a portal that holds SAP's organizational context has started becoming a copy of SAP's order. `EA` becomes `PCE` at the boundary for the same reason. An architecture decision that never changes a field list is decoration.

**Association versus Composition is a lifecycle claim, and the reverse direction is the one that catches you.** `Orders.items` as a Composition and `Orders.supplier` as an Association are both obvious. `Suppliers.orders` is the interesting one: it is the same pair of entities as `Orders.supplier`, so the temptation is to mirror the relationship kind, and a Composition there would make `Suppliers` a document root whose deletion cascades into orders the portal is contractually obliged to keep. Writing a test that deletes an order and then asserts *both* that the line is gone and that the supplier survives turned the decision into something the suite defends.

**`managed` is the aspect you are supposed to add, and adding it would have been wrong.** Every CAP example applies `cuid, managed` together. `cuid` fits exactly — it contributes the UUID key the contract already specifies. `managed` would have renamed `receivedAt` to `createdAt`, which is not a cosmetic difference: in this domain the recorded fact is when the *portal received a snapshot*, not when a row was created. It would also have added `createdBy` and `modifiedBy`, two columns with nothing to populate them until Phase 4.4 has supplier identity and Phase 8 has a platform one. Phase 3.2 refused to annotate fields no code writes; the same argument applies to creating them. Keeping `@cds.on.insert: $now` — the mechanism `managed` is built from — while declining the aspect itself is the version of the convention that actually fits.

**`@assert.unique` turned out to be a database constraint, which is a stronger fact than expected.** The documented ingestion rule requires parallel duplicates to be caught "through database uniqueness and rereading the committed receipt", not by a read-before-insert check, and `@assert.unique` reads like an input-validation annotation. `cds compile db --to sql` settled it: the generated DDL contains real `CONSTRAINT … UNIQUE` clauses. Printing the DDL took one command and replaced an assumption that would otherwise have gone unexamined until 4.3 depended on it.

**One tsconfig entry cannot serve two resolvers.** cds-typer emits `index.js` for the runtime and `index.d.ts` for the compiler, and a `paths` mapping in `tsconfig.json` is honoured by `tsc` *and* by `tsx`. Every single-target choice failed, each in a different and initially misleading way: pointing at `index.ts` crashed `tsc` outright with `Error: Debug Failure`; pointing at `index.d.ts` made `tsx` execute a declaration file; regenerating as `.ts` made `tsx` load compiler input as a module and fail with `Class extends value undefined`. The fix is not a better target but a different mechanism — `moduleResolution: node16` reads the `imports` field in `package.json`, so TypeScript and Node each resolve `#cds-models/*` correctly on their own and `paths` disappears. The general shape is familiar from the Phase 3.2 `@UI.facet` placement error: three plausible variations all failed, and the resolution was to stop varying the value and question the construct.

**A boundary is worth verifying, not just declaring.** Phase 4.2 claims to add persistence and no API. Curling `/rest/supplier/v1/Orders` and `/odata/v4/Orders` and getting 404 from a server that has just deployed three tables and loaded three fixture files costs nothing and converts that claim into evidence. The startup log saying `serving HealthService` and nothing else does the same job.

## Phase 4.3 — CAP ingestion boundary, locally runtime-verified

**The framework's defaults were quietly editing the contract.** Two CAP behaviours, each sensible in isolation, each wrong here. Structured elements are flattened, so the documented nested body came back as `400 Property "source" does not exist` — the contract's shape simply was not the shape CAP intended to serve. And a `UUID`-typed key is auto-generated when the caller omits it, so a delivery with **no `deliveryId` at all** was accepted with 201 and a server-invented identity. The second one is the more alarming: it does not fail, it succeeds wrongly, converting "the body identity remains mandatory" into "optional" and destroying idempotency for that request. A test caught it because the test asserted the *refusal*, not the success. Convenience defaults are worth knowing precisely when you have an external contract to honour, because they will honour their own instead.

**Idempotency written as a check is not idempotency.** The obvious implementation is "select by deliveryId; if absent, insert". It passes every sequential test and it is wrong, because two concurrent requests can both pass the select. The contract said so already — "parallel duplicates must be resolved through database uniqueness and rereading the committed receipt" — which only became legible after writing the naive version in my head and asking what two callers would do. The constraint is the mechanism; the pre-check is an optimisation that makes the common case cheap.

**And then the branch that constraint protects was never executed.** Instrumenting the catch-and-reread path and running the concurrent test three times gave zero hits: a single local SQLite connection serializes the two requests far enough apart that the second always finds the committed receipt and takes the ordinary replay path. The invariant holds — exactly one order, one line, one receipt, both callers answered — but the code that would hold it under real write concurrency is reasoned, not exercised. Reporting "concurrency verified" would have been true of the outcome and false of the mechanism. This is the same discipline the ABAP phases needed for OI-13, arriving from the opposite direction: there the case was unreachable, here it is reachable but not reached.

**A hash is what turns "the same message" into something a computer can decide.** `{"a":1,"b":2}` and `{"b":2,"a":1}` are the same delivery; so are `1500.00` and `1500.0`. Byte comparison says no to both. The contract's instruction to "normalize known fields, decimal representation and object member ordering before hashing" is one sentence that does all the work, and the test that replays a delivery with every member reordered and every decimal rewritten is the one that proves the boundary understands business identity rather than transport accidents.

**Money is integers.** `750.0000` and `120.5000` have no exact binary representation, so `3.000 × 120.5000 === 361.50` is a coin flip in floating point. Parsing decimal strings into scaled `BigInt` makes every comparison exact and every rounding deliberate, and it costs about forty lines. The contract already said decimals travel as strings; treating that as a transport detail and converting to `Number` at the door would have thrown away the exactness the string was protecting.

**Two uniqueness rules that look like one.** `DeliveryReceipts(sourceSystem, deliveryId)` and `Orders(sourceSystem, sourceOrderId, sourceRevision)` both stop duplicates, and collapsing them would have been easy. They answer different questions: a repeated delivery is a harmless retry after a timeout, and the same order arriving under a *new* delivery id means somebody believes it was never delivered. Answering the second with a cheerful replay 200 would hide a genuine discrepancy behind a success. Keeping them separate is why the 409 can name the original portal order and the delivery that carried it, which is what a person reconciling actually needs.

**Pulling `DeliveryReceipts` forward was a documented deviation, not a silent one.** The domain model marks it phase 5. The Phase 4.3 replay and conflict rules cannot be implemented without a stored hash and a stored receipt, so it came forward — and the rest of the Phase 5 machinery, `DeliveryIntent` and `SupplierResponseDelivery` and attempt history, deliberately did not. A plan written in Phase 0 that meets an implementation in Phase 4.3 will sometimes be wrong about boundaries; the useful response is to move the boundary and say so in the schema comment, not to implement a weaker rule that fits the label.

## Phase 4.4 — CAP supplier service, locally runtime-verified

**A writable status field is a status with no rules.** The shortest path to "the supplier can accept an order" is a `PATCH` that sets `status`. It would have worked, and everything that makes the operation correct would have been optional: nothing would enforce `RECEIVED → ACCEPTED`, require a reason with a rejection, allocate the next version, or write the outbound response. Making the transition a bound action means the rule and the write cannot be separated, which is the same conclusion Phase 2.7C reached in RAP with "no unrestricted status PATCH exists". Two different frameworks, two years of project time apart, same answer — the reason is about the domain, not the technology.

**Filter the query, not the result.** Row-level isolation could be done by reading and then discarding rows the caller may not see. Adding the condition to `req.query` inside a `before READ` hook instead means the database never returns them, and — more importantly — one rule covers the collection, a key read, an `$expand` and a navigation path in one place. Every bypass I could think of to test was already closed, not because each was handled, but because there was only ever one place to handle.

**404 discloses less than 403.** For another supplier's order the instinct is 403: the row exists, the caller may not have it. But 403 *confirms it exists* and that someone else owns it, which is exactly what a probing client wants. A scoped 404 makes "not yours" and "not there" indistinguishable. The design acceptance cases anticipated this — "access denied or scoped not-found response; no fields disclosed" — and only one of those two options actually discloses nothing.

**Order the checks by what the contract promises, not by what is cheapest.** The natural order is version precondition first, since it is one comparison. The contract requires replay detection first, because "replay detection must recognize an already successful identical command even if its original version is now stale" — a retried command *must* succeed after its version has moved on. The same sentence appears again for dates: "deduplication runs before current-date validation", so a replayed command whose delivery date is now in the past is still valid. Both are cases where the cheap ordering silently breaks a retry, and retries are the normal case in an integration.

**The Phase 4.3 trap was avoided by remembering it.** Declaring `reason : String(255) not null` in the action signature reads well and made `MISSING_REJECTION_REASON` dead code: CAP's own ASSERT_MANDATORY answers first, in the framework's envelope, with no contract code and no correlation id. This is precisely what `INVALID_PAYLOAD` turned out to be one subphase earlier. Finding it took one deliberate curl of a blank reason, because the previous subphase had taught me to check reachability rather than assume it. The fix was to drop `not null` and validate in the handler, so every supplier-facing 400 speaks one envelope.

**An atomicity test has to make something actually fail.** "CAP wraps each request in a transaction" is true and proves nothing about this code. The test plants a response row occupying the `(order, version)` slot the next decision will need, so the handler's order update succeeds and its response insert then violates a real constraint from the documented model. Watching the order come back `RECEIVED` at version 0 is evidence; quoting the framework's documentation is not. The uniqueness rule that made this possible was added for a different reason entirely, which is a recurring return on modelling constraints properly.

**Pulling an entity forward twice is a pattern, not an accident.** `DeliveryReceipts` in 4.3 and `SupplierResponseDeliveries` in 4.4 are both marked phase 5 in a domain model written in Phase 0, and both are unavoidable the moment their subphase has to answer a replay. The useful response each time was to move the boundary, take only the fields the subphase needs, and say so in the schema comment — rather than implement a weaker rule that fits the original label. A plan drawn before implementation will be wrong about some boundaries; the discipline is in the record, not in the plan being right.

## Phase 4.5 — minimal supplier UI, locally runtime-verified

**Extracting the logic is what made a UI testable without a browser framework.** The instinct on reaching "test the frontend" is to reach for Playwright. Almost nothing here needed a browser: which controls a status permits, what a command payload contains, how an error becomes a sentence — all of it is a pure function of data. Putting those in `app/lib/order-view.mjs` with no DOM and no fetch, and importing *that same file* in the tests, covered the parts that can be wrong. What was left needing a real browser was rendering, and rendering is exactly what a test would have asserted badly anyway.

**And then the browser found the one bug the tests could not.** The first render showed the sign-in panel and the signed-in bar simultaneously, because `#session { display: flex }` is an author rule and beats the user agent's `[hidden] { display: none }`. Every panel toggled by `hidden` was permanently visible. No unit test would have caught it, no HTTP test could have, and it took about four seconds of looking at a screenshot. The lesson is not "write browser tests" — it is that a class of defect exists only in the rendered result, and the cheap way to find it is to look.

**A UI that mirrors backend rules has to mirror them and nothing more.** `actionsFor(status)` decides which buttons to draw and is, unavoidably, a copy of the lifecycle. The discipline is in what it is *allowed to be*: it decides visibility, never permission. A wrongly drawn Accept button on a rejected order produces a 409 from the service, not a wrong write. Stating that boundary explicitly is what keeps a convenience mirror from quietly becoming a second rulebook — the same reason the reject box checks for a blank reason and the service still enforces it.

**Idempotency has a frontend half.** The backend's `responseId` replay detection is worthless if the browser generates a fresh id on every retry. Minting one id per *user command* rather than per HTTP attempt is the part that makes a double-click harmless, and it is invisible in the backend code. The same is true of `expectedResponseVersion`: taking it from the loaded order, never from an input field, is what makes it an observation rather than a wish.

**Refusing to retry is a feature.** The obvious response to 409 `STALE_RESPONSE_VERSION` is to reload and resend. That would be wrong: the order changed, so the decision made a moment ago may not be the one the supplier would make now. Reload, show what happened, stop. There is no retry logic anywhere in this UI, and that absence is deliberate.

**Deciding not to add a field was the pagination design.** The contract asked for "query parameters and result envelope". Parameters were easy. The envelope was the real choice: wrapping the array in `{ items, count }` is conventional, and it would have changed a read contract Phase 4.4 had already verified and tested, in exchange for a count nothing in this portal displays. Keeping the bare array and paging until a short page arrives costs one helper function and keeps the count available as a later additive change. Not paging the item list at all was the same kind of decision from the opposite direction — a bound where ingestion already guarantees one would only risk truncating a detail view.
