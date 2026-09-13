# Learning journal

This journal distinguishes design, source preparation and successful SAP execution. Phase 1, managed CRUD/composition, Status initialization and item TotalAmount are evidenced by the learner's SAP reports. Header TotalAmount is runtime-verified for committed-item deletion. Supplier validation is the current source-prepared checkpoint.

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

The learner manually created and successfully activated ZJP_PO_H, ZJP_PO_I, ZJP_I_PurchaseOrder, ZJP_I_PurchaseOrderItem, ZJP_C_PurchaseOrder and ZJP_C_PurchaseOrderItem in SAP S/4HANA using ADT/Eclipse. The [ADT lesson](abap-rap/docs/phase-1-domain-model.md) contains the reconciled sources and activation record. Exact release is still unrecorded; the target SAP compiler is authoritative.

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

## Phase 2.5A — Supplier required on save

`validateSupplier on save { create; field Supplier; }` checks new roots and roots whose Supplier changes. A validation reads current data and reports failures; it does not derive a replacement value or commit. The root handler uses local-mode EML, returns the invalid key in FAILED and an error message tied to `%element-Supplier` in REPORTED. FAILED blocks saving; an error message by itself is not a substitute.

This first rule checks presence only, not supplier master-data existence. It applies to active orders with business Status DRAFT too. Technical draft is still absent. A simple text message is used for this checkpoint; translation/message-class work is deferred.

The EML test attempts a blank-Supplier create and a blank-Supplier update of the committed SUP001 order. MODIFY should succeed; COMMIT should fail with `Supplier is required.` The test rolls back immediately and checks no invalid create persisted and SUP001 survived the rejected update. Normal create/update/totals/deletion then prove the positive path still works. SAP activation and runtime verification of this new validation are pending.
