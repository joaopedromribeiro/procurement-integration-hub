# Learning journal

This file distinguishes concepts studied from hands-on implementation. Phase 0 contains architecture learning; no RAP or CAP runtime practice has occurred yet.

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

## Phase 1 — persistence and CDS source preparation

Source authored and explained: ZJP_PO_H, ZJP_PO_I, ZJP_I_PurchaseOrder, ZJP_I_PurchaseOrderItem, ZJP_C_PurchaseOrder and ZJP_C_PurchaseOrderItem. Target: SAP S/4HANA with ABAP Cloud. Learner activation and runtime practice are pending; [the ADT lesson](abap-rap/docs/phase-1-domain-model.md) contains the complete sources and expected tests.

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

Expected tests: activate each table and both CDS pairs; inspect keys, scales, references and projection fields; preview zero rows in a new installation. Actual SAP results: pending. No calculated totals, CRUD operations, draft behavior or service tests were performed.

Interview explanation to practice: “I modeled purchase orders as a client-dependent UUID root with composed items, then exposed a consumer projection with redirected relationships. I separated structural semantics from the managed behavior that will enforce business rules.” Use this as an explanation of the authored design; qualify SAP hands-on claims until activation is recorded.

Phases 2–11 remain unstarted.
