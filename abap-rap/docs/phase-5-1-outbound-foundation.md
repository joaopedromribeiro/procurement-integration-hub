# Phase 5.1 — SAP ↔ CAP direct integration prerequisites and outbound foundation

**Nothing in this subphase is runtime-verified, and nothing was activated in ADT.** No ABAP object was created, no table was added, no behavior definition changed, no HTTP request was made and no CAP behavior changed. This document is design, evidence review and a probe list. Every statement about the target system's released API set is marked as a **candidate** until the learner returns ADT or compiler output, because per repository policy the SAP ADT compiler and SAP runtime evidence are authoritative and this repository is not.

Read with [API_CONTRACTS.md](../../API_CONTRACTS.md) — which is the source of truth for the wire shapes below and was not modified here — and the [Phase 4.6 closure](../../cap-supplier-portal/docs/phase-4-6-closure.md), which records the CAP half of the handoff.

## Baseline

| Item | Value | Provenance |
| --- | --- | --- |
| Repository state | clean at `62dc04d Complete Phase 4 closure` | `git status`, `git log -1 --oneline` |
| RAP phases | 1, 2 (through 2.7E), 3.1, 3.2 complete, SAP runtime-verified | [PROJECT_STATUS.md](../../PROJECT_STATUS.md) |
| CAP phases | 4.1–4.6 complete, **local Node.js execution only** | [Phase 4.6 closure](../../cap-supplier-portal/docs/phase-4-6-closure.md) |
| ABAP target | SAP_BASIS 758 SP0001 / S4CORE 108 SP0001, ABAP Cloud; ADT Core 3.60.3, BO Tools 1.209.0 | [ARCHITECTURE.md](../../ARCHITECTURE.md) |
| Traffic between the systems so far | none, in either direction | Phase 4 never contacted SAP |
| Verified CAP ingestion route | `POST /rest/integration/v1/Orders` | Phase 4.3, local |

Phase 5 uses **direct SAP ↔ CAP HTTP**. Integration Suite is Phase 6 and is not designed here.

## Scope of 5.1

**In scope:** the connectivity question, an inventory of what RAP already has, the `DeliveryIntent` persistence design, the outbound DTO and mapping trace, a transport abstraction, the transaction-boundary analysis, an object inventory for 5.2 and the exact probes the learner must run.

**Out of scope and not implemented:** `sendToSupplier`, any real `POST` to CAP, `retryDelivery`, `applySupplierResponse`, the CAP → SAP callback, the response sender, Integration Suite, CPI/iFlows, Event Mesh, API Management, OAuth/XSUAA, production credentials, and any scheduler or background retry worker.

---

## 1. Environment and connectivity review

### 1.1 What must be confirmed before a single request

[docs/environments.md](../../docs/environments.md) already states the requirement for this row: *"Released ABAP outbound HTTP APIs, supported communication setup, reachable CAP URL; reverse access to RAP Web API."* Broken out, and restricted to the outbound direction that 5.1 prepares:

| Prerequisite | Current repository state | Who can settle it |
| --- | --- | --- |
| Released outbound HTTP client API for ABAP for Cloud Development on this target | **Unknown.** The repository contains no reference to any HTTP client class or interface — a repository-wide search for `if_web_http`, `cl_web_http`, `cl_http_destination`, `create_by_destination` and `IF_HTTP` returns no ABAP hit at all | learner, in ADT (probe P1) |
| A supported way to declare the outbound target (communication scenario / arrangement, or a URL destination) | **Unknown.** The environment record lists communication-administration permissions as unknown; only development access is demonstrated | learner, in ADT and the system's communication apps (probes P2, P3) |
| Server certificate trust for an HTTPS call out of the ABAP system | **Unknown.** Never exercised | learner / system administrator (probe P4) |
| A CAP URL the SAP system can actually resolve and reach | **Does not exist.** CAP runs on `http://localhost:4004` on the developer laptop | learner's decision, see 1.3 |
| Request timeout configurability on the client | **Unknown** | learner, in ADT (probe P1) |

Reverse access to the RAP Web API — the inbound `applySupplierResponse` direction — is **not** part of 5.1. It is listed in the deferred section.

### 1.2 SAP cannot call the developer laptop, and this is not a solvable-by-code problem

`docs/environments.md` records it already: *"A cloud ABAP system or CI tenant cannot call the laptop's `localhost`."* Stated concretely for this project:

- CAP listens on `http://localhost:4004` — loopback on one machine, plain HTTP, no certificate, no hostname that resolves anywhere else.
- `localhost` inside the SAP system means the SAP application server itself. A request from ABAP to `http://localhost:4004/rest/integration/v1/Orders` would either be refused or, worse, reach something else entirely on that host. It will never reach the laptop.
- The laptop has no public DNS name and, on an ordinary home or corporate network, no inbound route through NAT.

**The direction matters and the two directions must be tested separately.** `docs/environments.md`: *"Local CAP may be able to call a reachable SAP endpoint even when SAP cannot call back to local CAP."* So the *inbound* leg (CAP → the RAP OData service, Phase 5.3+) may work from the laptop against the recorded service root with no new infrastructure, while the *outbound* leg designed here cannot work at all until CAP is reachable. Do not infer one from the other.

**No network solution is invented here.** The two options below are the ones the project already permits; nothing else is proposed, and nothing is deployed in this subphase.

### 1.3 The two permitted development options, compared

| | **A. Deliberately configured HTTPS development tunnel** | **B. CAP deployed to a reachable hosted runtime (BTP Cloud Foundry)** |
| --- | --- | --- |
| What it is | A tunnel service publishes a public HTTPS hostname that forwards to `localhost:4004` | `cf push` of the CAP application; BTP terminates TLS on a platform route |
| Environment-record basis | *"A deliberately configured development tunnel or supported private-connectivity route is a temporary alternative and must be recorded explicitly"* | *"Prefer deploying CAP to the selected BTP runtime when available"* |
| Setup cost | Minutes; no entitlement needed | BTP account type, region and Cloud Foundry quota are all recorded as **Unknown**; also drags in HANA Cloud or a chosen alternative for persistence |
| Certificate trust on the SAP side | The tunnel provider's CA must be trusted by the ABAP system (probe P4) | The platform route's CA must be trusted by the ABAP system (probe P4) |
| Stability of the URL | Usually changes on every restart, so it cannot be baked into anything | Stable per deployment |
| What it does **not** prove | BTP deployment and operations; nothing about HANA; the endpoint is still unauthenticated | Nothing about the tunnel path; still not production authentication |
| Security caveat | It **publishes an unauthenticated ingestion endpoint to the internet** for as long as it runs. Phase 4.6 debt item 2 is exactly this: *"No authentication on the integration endpoint, which Phase 5 will be the first real caller of"* | Also unauthenticated unless something is added; at least the route is not a hole into the laptop |

**Recommendation, for the learner to accept or reject:** option A for the first successful round trip, because it is the cheapest way to prove the ABAP HTTP client, the mapping and the receipt handling, and because the URL instability does not matter when the URL is a configuration value read at dispatch time rather than a constant. Then option B once the round trip is understood, since the portfolio claim worth making is a deployed application and not a tunnel.

Two conditions on option A, both of which follow from the project's own rules rather than from caution: the tunnel must be **recorded explicitly** in `docs/environments.md` when it is used, per the Network reality paragraph; and it must be **shut down when not actively testing**, because the endpoint it exposes has no authentication at all and Phase 4 verified that it accepts any well-formed delivery. Neither of these is a code change.

**Nothing is deployed and no tunnel is configured in this subphase.** The choice is the learner's and it is a blocker, recorded in section 8.

### 1.4 HTTPS

API_CONTRACTS common rules: *"HTTPS outside loopback development."* Both options above are HTTPS on the public leg, so the requirement is met by either. What is unresolved is the ABAP side of it: an outbound TLS call from ABAP needs the server's certificate chain in the system's trust store, and neither the mechanism on this target nor the permission to change it is recorded. That is probe P4 and it may require an administrator rather than the learner.

---

## 2. RAP integration state review

### 2.1 The nine fields exist, are mapped, and are written by nothing

Inspected: [zjp_po_h.ddl](../persistence/zjp_po_h.ddl), [zjp_i_purchaseorder.ddls](../cds/zjp_i_purchaseorder.ddls), [zjp_i_purchaseorder.bdef](../behavior/zjp_i_purchaseorder.bdef), [zjp_c_purchaseorder.bdef](../behavior/zjp_c_purchaseorder.bdef) and the behavior pool [locals](../classes/zbp_i_purchaseorder.clas.locals_imp.abap).

| Element | Table column | DDIC type | BDEF | In buyer projection | Written by any handler | Phase 5 need |
| --- | --- | --- | --- | --- | --- | --- |
| `OrderRevision` | `order_revision` | `abap.int4` | `readonly` | yes | **no** | **5.2** — becomes `source.revision` |
| `IntegrationStatus` | `integration_status` | `abap.char(16)` | `readonly` | yes | **no** | **5.2** — dispatch lifecycle on the order |
| `DeliveryId` | `delivery_id` | `sysuuid_x16` | `readonly` | yes | **no** | **5.2** — current delivery identity |
| `LastErrorCode` | `last_error_code` | `abap.char(60)` | `readonly` | yes | **no** | 5.2 — on FAILED/UNKNOWN |
| `LastErrorMessage` | `last_error_message` | `abap.char(255)` | `readonly` | yes | **no** | 5.2 — on FAILED/UNKNOWN |
| `LastErrorAt` | `last_error_at` | `abp_lastchange_tstmpl` | `readonly` | yes | **no** | 5.2 — on FAILED/UNKNOWN |
| `LastCorrelationId` | `last_correlation_id` | `sysuuid_x16` | `readonly` | yes | **no** | 5.2 — one per transport attempt |
| `LastResponseId` | `last_response_id` | `sysuuid_x16` | `readonly` | yes | **no** | **5.3+** — inbound only |
| `LastResponseVersion` | `last_response_version` | `abap.int4` | `readonly` | yes | **no** | **5.3+** — inbound only |

Three neighbouring fields are in the same situation and belong to the inbound leg: `SupplierResponse` `char(8)`, `EstimatedDeliveryDate` `dats` and `RejectionOrigin` `char(10)` — the last is written by `reject` for the `APPROVER` case only.

Evidence that nothing writes them: the behavior pool contains exactly eight `UPDATE FIELDS` clauses, over `TotalAmount`, `Status`, `PurchaseOrderNumber`, `RejectionOrigin` and `RejectionReason`. The only occurrence of any integration field name in the whole pool is a comment at line 659 explaining why the `APPROVED` → `CANCELLED` delivery guard could not be implemented in Phase 2. This matches the recorded debt — *"Display number, supplier name and integration fields remain initial"* — and `readonly` in the BDEF means no external caller can write them either, while a handler still can through `MODIFY ... IN LOCAL MODE`, exactly as `submit` writes `Status` and `PurchaseOrderNumber`.

### 2.2 No header field is missing — and two carry wrong values

**Nothing needs to be added to `ZJP_PO_H`.** All nine integration fields specified by the domain model are present, typed, mapped and exposed. `IntegrationStatus` `char(16)` holds the longest documented value (`NOT_REQUESTED`, 13 characters) with room to spare. Per the instruction not to add fields without contract evidence, no column is proposed for the header.

Two **value** gaps are real, verified, and turn into hard failures the moment a delivery is built:

**Gap 1 — `OrderRevision` is `0` and CAP requires `≥ 1`.** The domain model says *"Positive integer; Starts at 1; frozen at submission"*. No handler writes it, so every row in `ZJP_PO_H` carries the `abap.int4` initial value `0`. On the CAP side this is not a soft preference: [`srv/lib/ingestion.ts`](../../cap-supplier-portal/srv/lib/ingestion.ts) rejects it —

```ts
if (!Number.isInteger(sourceRevision) || sourceRevision < 1) {
  return fail('INVALID_SOURCE_IDENTITY', 'source.revision is required and must be a positive integer.')
}
```

so a delivery built from today's persistence would be refused with **400 `INVALID_SOURCE_IDENTITY`** before any interesting behavior was reached. `sourceRevision` also participates in `Orders(sourceSystem, sourceOrderId, sourceRevision)`, the uniqueness rule that decides whether a re-sent order is a duplicate or a new revision, so it cannot be quietly defaulted at the boundary. This is documented debt becoming a blocker, not a newly introduced defect — nothing regressed — and it is blocker B1 in section 8.

**Gap 2 — `IntegrationStatus` is blank, not `NOT_REQUESTED`.** No determination initializes it, so existing rows hold `''` while the domain model enumerates `NOT_REQUESTED, PENDING, IN_FLIGHT, DELIVERED, FAILED, UNKNOWN`. Any 5.2 read must treat blank as "never requested" or a determination must establish the initial value. Both are defensible; neither is decided here, and neither is implemented here.

### 2.3 One Phase 2 obligation becomes reachable

ADR-022 deliberately did not implement the domain model's rule that `APPROVED` may be cancelled only before delivery was requested, on the grounds that *"`IntegrationStatus` and `DeliveryId` are readonly and no Phase 2 handler can write them, so the condition is unrepresentable as true"*. Once `DeliveryIntent` exists and `sendToSupplier` writes it, the condition becomes representable and the guard becomes testable. **That guard is a Phase 5.2 obligation and is not implemented here.** It is recorded so it is not silently dropped.

---

## 3. Direct SAP → CAP architecture

```mermaid
sequenceDiagram
    actor Approver
    participant RAP as RAP BO (ZJP_I_PurchaseOrder)
    participant Intent as DeliveryIntent (RAP, durable)
    participant Coord as ABAP coordinator (console, phase 5.3)
    participant CAP as CAP IntegrationService
    Approver->>RAP: sendToSupplier (phase 5.2)
    Note over RAP,Intent: one LUW: validate APPROVED, create intent,<br/>set IntegrationStatus PENDING
    RAP-->>Approver: action returns; no HTTP has happened
    Coord->>Intent: claim a PENDING intent under a lease
    Coord->>CAP: POST /rest/integration/v1/Orders
    CAP-->>Coord: 201 receipt / 200 replay / 409 / timeout
    Coord->>Intent: record outcome + portalOrderId
    Coord->>RAP: EML: IntegrationStatus DELIVERED / FAILED / UNKNOWN
```

The shape is ADR-006 unchanged — *"Post-commit dispatcher with synchronous HTTP; avoids remote side effects inside RAP save"* — with Cloud Integration removed from the middle. ARCHITECTURE.md already anticipates the first coordinator being *"an explicitly run ABAP console application outside BO handlers"*, which is why no scheduler appears above and none is proposed.

The one difference from the Phase 6 picture is the mapping step: in Phase 6 the coordinator posts the *source order delivery* to CI and CI maps it, so in Phase 5 the mapping has to live in ABAP. Section 5 keeps it in a separate component for exactly that reason.

---

## 4. DeliveryIntent design

### 4.1 Why it is a second RAP business object and not a plain table

The repository rule is unambiguous: *"Do not use direct SQL `INSERT`, `UPDATE`, or `DELETE` on RAP persistence tables"* and *"Use managed RAP and EML for business-object operations."* Three shapes were considered.

- **A child composition of `PurchaseOrder`** — rejected. A composition dies with its order and is commercially owned, so the Phase 2.7C invariant ("editable only while `Status` is `DRAFT`") would block every write the dispatcher needs. A delivery record also has to be claimable by a coordinator outside the order's transaction, which a composition child is a poor fit for.
- **A plain DDIC table written with `INSERT`/`UPDATE`** — rejected. It violates the repository rule, and the rule exists because the transactional buffer is the only place that sees uncommitted state.
- **A separate managed RAP root BO** — selected. `ZJP_I_DeliveryIntent`, managed, **no draft**, no projection and no OData binding in 5.2. Every write goes through EML, from the `sendToSupplier` handler and later from the coordinator. It is an operational record, so the domain model's guidance applies: *"These operational records are not editable commercial items and should be exposed read-only where needed."*

No draft, because a delivery intent is never edited by a person in an editing session; it is created by an action and advanced by a machine.

### 4.2 The minimum field set

Proposed table `ZJP_PO_DLV`, following the `ZJP_PO_H` / `ZJP_PO_I` naming family. **Proposed source, not activated, not placed in `abap-rap/persistence/` — it has never been through the compiler.**

```
@EndUserText.label : 'Procurement Hub: Purchase Order Delivery Intent'
@AbapCatalog.enhancement.category : #NOT_EXTENSIBLE
@AbapCatalog.tableCategory : #TRANSPARENT
@AbapCatalog.deliveryClass : #A
@AbapCatalog.dataMaintenance : #RESTRICTED
define table zjp_po_dlv {
  key client              : abap.clnt not null;
  key delivery_uuid       : sysuuid_x16 not null;
  purchase_order_uuid     : sysuuid_x16 not null;
  order_revision          : abap.int4 not null;
  payload_snapshot        : abap.string;
  payload_hash            : abap.char(64) not null;
  dispatch_state          : abap.char(16) not null;
  last_correlation_id     : sysuuid_x16 not null;
  portal_order_uuid       : sysuuid_x16 not null;
  approved_by             : abp_lastchange_user not null;
  approved_at             : abp_lastchange_tstmpl not null;
  lease_owner             : sysuuid_x16 not null;
  lease_expires_at        : abp_lastchange_tstmpl not null;
  created_at              : abp_creation_tstmpl not null;
  last_changed_at         : abp_lastchange_tstmpl not null;
  local_last_changed_at   : abp_locinst_lastchange_tstmpl not null;
}
```

Each field against the requirement it exists for:

| Requirement | Field | Note |
| --- | --- | --- |
| One immutable delivery identity | `delivery_uuid` (key) | This *is* the wire `deliveryId`. It is the key, so it cannot be changed by an update; a second delivery means a second row |
| `PurchaseOrderUUID` | `purchase_order_uuid` | Correlation to the RAP root. **Not** a foreign key to anything in CAP |
| Order revision | `order_revision` | Copied at creation, so the intent records the revision that was dispatched even if the order later changes |
| Immutable snapshot | `payload_snapshot` | See 4.3 for which of the two DTOs is stored and why |
| Canonical hash | `payload_hash` | sha256 hex, 64 characters. Cheap equality and tamper detection without re-reading a large string |
| Dispatch state | `dispatch_state` | `PENDING` / `IN_FLIGHT` / `DELIVERED` / `FAILED` / `UNKNOWN` — the same vocabulary as `IntegrationStatus`, deliberately, so the two never need translating |
| Correlation | `last_correlation_id` | API_CONTRACTS: *"`X-Correlation-ID` identifies a transport attempt. A retry may get a new correlation ID while preserving the business delivery/response ID."* Hence *last*, and hence separate from `delivery_uuid` |
| Approval evidence | `approved_by`, `approved_at` | ARCHITECTURE requires *"original approval evidence"*; these say who approved and when, captured when the intent is created |
| Lease | `lease_owner`, `lease_expires_at` | ARCHITECTURE: *"Claiming the intent prevents concurrent sends and cancellation… A claim has a bounded lease so a crash can be recovered."* `lease_owner` is a per-run coordinator UUID rather than a user name, because the thing that holds a lease is an execution, not a person |
| The receipt | `portal_order_uuid` | See 4.4 — this is the field with the least obvious justification and the clearest contract evidence |

Optional persistence values follow ADR-015 — ABAP initial values in non-null columns, with the boundary adapter responsible for mapping initial to wire-level absence. So `portal_order_uuid` is initial until a receipt arrives, and `lease_expires_at` is initial while unclaimed.

### 4.3 The snapshot stores the source order delivery, not the mapped CAP order

API_CONTRACTS defines two DTOs, and only one of them should be frozen in the intent.

Storing the **source order delivery** was chosen, for three reasons.

1. **It survives Phase 6 unchanged.** Phase 6 switches the endpoint to Cloud Integration, which expects `POST /http/pih/v1/order-deliveries` carrying exactly this DTO, and CI then does the mapping. If the intent froze the mapped CAP order instead, every intent written in Phase 5 would be in the wrong shape the moment the endpoint moved. API_CONTRACTS is explicit that the switch must not change business identities: *"Phase 6 switches endpoints to CI without changing business identities or ownership."*
2. **Byte-identity is not what CAP checks.** Phase 4.3 verified that the replay hash is taken over a *normalized projection* — `srv/lib/ingestion.ts` joins canonical field values with `` inside a line and `` between lines, then sha256 — and a replay that reorders every JSON member and writes `1500.0` for `1500.00` is still recognised as the same delivery. So the mapped body does not need to be byte-stable across attempts; it needs to be **semantically** stable, which a deterministic mapper over a frozen source snapshot gives.
3. **It keeps the immutability where the approval was.** The snapshot is the approved commercial content. Re-reading the order at each attempt would be the actual mistake — it would let a later change leak into a replay of an earlier approval.

The consequence to accept deliberately: the mapper must be **pure and deterministic**, since it runs once per attempt rather than once per intent. That is a property worth testing directly, and it is why section 5 makes it a separate class with no HTTP dependency.

`payload_hash` is taken over the stored source snapshot, not over the mapped body, so it answers "has this intent been tampered with" rather than "will CAP consider this a replay" — two different questions, and only the first is SAP's to answer.

### 4.4 `portal_order_uuid`: the receipt had nowhere to live

The Phase 4.6 handoff lists `portalOrderId` as one of the seven identifiers Phase 5 must carry, with the role *"what SAP stores to refer to the portal's copy"*. The receipt returns it on both 201 and a 200 replay. **But `ZJP_PO_H` has no column for it, and the domain model's `PurchaseOrder` field list does not contain one either.** There is a named SAP-side obligation with no home.

It belongs on the intent rather than on the header, because the receipt is the result of *one delivery*, not a property of the order: an order that is delivered, fails, and is later re-delivered under a new revision would overwrite a header field and lose the earlier correlation, whereas one row per delivery keeps each receipt beside the payload that earned it. Adding it here also avoids a change to `ZJP_PO_H`, which is SAP runtime-verified through Phase 3.2 and should not be touched for a field a new table can carry.

The domain model's `DeliveryIntent` sentence has been extended with this identity as part of this subphase; see section 9.

### 4.5 Uniqueness, and an honest comparison with the CAP side

The rule to enforce is the domain model's: *"Never create a fresh delivery ID merely because a network call timed out."* In table terms, **one non-terminal delivery per `(purchase_order_uuid, order_revision)`**.

Phase 4.3's lesson was that this class of rule belongs in a database constraint rather than a read-before-insert check, because two concurrent requests can both pass a check. That lesson does not transfer cleanly here, and pretending it does would be the mistake:

- Whether a `DEFINE TABLE` artifact under ABAP Cloud can carry a **unique secondary index**, and what the ADT syntax or object type for that is, is **not established by this repository**. It is probe P8. On a client-dependent table such an index would include `client`.
- If it can, declare it, and the rule is enforced the way CAP's is.
- If it cannot, the fallback is a read inside the `sendToSupplier` handler plus the observation that RAP takes a **root lock** on the order, which serializes two `sendToSupplier` calls on the same order in a way two concurrent HTTP POSTs to CAP were not serialized. That is a genuinely different and stronger starting position than the CAP case — but it is **reasoning, not evidence**, and OI-13 records that no concurrency case has ever been exercised on this system. It must be written down as reasoned.

`ZJP_PO_H` deliberately has no unique index on `purchase_order_number` because the number range object is the uniqueness authority. Here there is no equivalent external authority, which is why the question has to be asked rather than inherited.

### 4.6 Fields deliberately left out of the minimum

| Left out | Why, and when it arrives |
| --- | --- |
| `attempt_count` | API_CONTRACTS proposes a bounded budget of three retries, so a counter is needed — by `retryDelivery`, which is not 5.1. Phase 4.4 made the same call in the other direction: `SupplierResponseDeliveries` was pulled forward *without* attempt count, precisely because nothing in that phase attempted a delivery |
| `last_http_status`, `last_error_code`, `last_error_message` | The header already has `LastErrorCode` / `LastErrorMessage` / `LastErrorAt` and nothing writes them yet. Duplicating them on the intent before either is populated would be two unpopulated copies of one idea |
| DeliveryAttempt history | The domain model assigns it to **Phase 7**: *"Phase 7 extends this with DeliveryAttempt history."* Not pulled forward, and the intent is not a substitute for it |
| Any association to CAP | *"There are no cross-database foreign keys."* `portal_order_uuid` is a stored identifier, not a reference |

This follows the pattern Phase 4.3 and 4.4 established twice: move a boundary when a subphase genuinely cannot answer its question without it, take only the fields that subphase needs, and record the deviation.

---

## 5. Outbound DTO and mapping

### 5.1 The trace, and why there are two hops rather than one

```
ZJP_I_PurchaseOrder + _Items      (RAP transactional buffer, read by EML)
        │  ZJP_CL_ORDER_DELIVERY_BUILDER
        ▼
Source order delivery DTO          (API_CONTRACTS "Source order delivery")  ← frozen in the intent
        │  ZJP_CL_CAP_ORDER_MAPPER   (pure, deterministic)
        ▼
Mapped CAP order JSON              (API_CONTRACTS "Mapped CAP order")
        │  ZJP_IF_OUTBOUND_TRANSPORT
        ▼
POST /rest/integration/v1/Orders
```

Collapsing the two hops into one builder that emits the mapped order directly would be shorter and is the wrong shape: Phase 6 deletes the second hop and keeps the first, so a single combined component would have to be split exactly when the endpoint moves. Keeping `EA → PCE` and the nesting inside the mapper is what makes the Phase 6 change an endpoint change.

### 5.2 Field mapping

The rules column is API_CONTRACTS' own mapping table, not a new design. Nothing in this section changes the contract.

| RAP element | Source order delivery | Mapped CAP order | Rule and risk |
| --- | --- | --- | --- |
| — | `schemaVersion` `"1.0"` | `schemaVersion` `"1.0"` | Constant. CAP accepts major version `1` only; anything else is `SCHEMA_VERSION_UNSUPPORTED` |
| `DeliveryIntent.delivery_uuid` | `deliveryId` | `deliveryId` | Canonical hyphenated text. `MISSING_DELIVERY_ID` if absent or non-canonical — note CAP declares this key as `String(36)`, not `UUID`, so a malformed value is refused rather than replaced |
| configured constant | `sourceSystem` | `source.system` | `PIH_ABAP_DEV` in the contract examples. A configured value, not derived from `sy-sysid`; blocker B4 |
| `PurchaseOrderUUID` | `purchaseOrderId` | `source.orderId` | Canonical hyphenated text; `INVALID_SOURCE_IDENTITY` otherwise |
| `PurchaseOrderNumber` | `purchaseOrder` | `source.orderNumber` | Always populated in practice, because 2.7E allocates it at `submit` and dispatch requires `APPROVED`, which is downstream of `submit`. Never send `""` as a number |
| `OrderRevision` | `revision` | `source.revision` | **Integer ≥ 1. Currently `0` in persistence — blocker B1** |
| `Supplier` | `supplier` | `supplierCode` | CAP resolves it against `Suppliers`; unknown is `UNKNOWN_SUPPLIER` |
| `SupplierName` | `supplierName` | *not transmitted* | *"CAP uses its supplier reference, not an untrusted overwrite."* Also unpopulated in RAP |
| `CompanyCode`, `PurchasingOrganization`, `PurchasingGroup` | `companyCode`, `purchasingOrganization`, `purchasingGroup` | *not transmitted* | *"Internal SAP context not required by portal."* They stay in the source DTO because CI's source schema has them |
| `Currency` | `currency` | `amount.currency` | `EUR` only; `UNSUPPORTED_CURRENCY` otherwise |
| `TotalAmount` `DEC(19,2)` | `totalAmount` | `amount.value` | Decimal string, scale 2. CAP re-checks it against the sum of the lines — `TOTAL_AMOUNT_MISMATCH` |
| `_Items[].PurchaseOrderItemUUID` | `items[].itemId` | `lines[].sourceItemId` | Canonical text; unique per delivery — `DUPLICATE_SOURCE_ITEM_ID` |
| `_Items[].ItemNumber` `NUMC(5)` | `items[].item` `"10"` | `lines[].lineNumber` `10` | **Type change: `NUMC` `00010` becomes the integer `10`.** *"Parse decimal digits; reject invalid/duplicate line number."* `INVALID_LINE_NUMBER` / `DUPLICATE_LINE_NUMBER` |
| `_Items[].Material` | `material` | `product.code` | `MISSING_PRODUCT_CODE` if blank |
| `_Items[].MaterialDescription` | `description` | `product.description` | Optional |
| `_Items[].Quantity` `QUAN(13,3)` | `quantity` | `orderedQuantity.value` | Decimal string, scale 3; must be `> 0` — `INVALID_QUANTITY` |
| `_Items[].UnitOfMeasure` `EA` | `unitOfMeasure` `"EA"` | `orderedQuantity.unit` `"PCE"` | **`EA` → `PCE`, the one controlled value mapping.** CAP accepts `PCE` only; `UNSUPPORTED_UNIT`. *"Unknown units fail validation; they are not guessed"* — so the mapper must table-map and reject, never pass through |
| `_Items[].NetPrice` `DEC(19,4)` | `netPrice` | `unitPrice.value` | Decimal string, scale 4; `≥ 0` with **zero explicitly valid** — `INVALID_PRICE` |
| header `Currency` | — | `unitPrice.currency` | Propagated onto every line. `LINE_CURRENCY_MISMATCH` if it disagrees with the header |
| `_Items[].TotalAmount` `DEC(19,2)` | `items[].totalAmount` | `lines[].lineAmount` | Decimal string, scale 2. CAP recomputes `round(quantity × unitPrice, 2)` half-up with exact arithmetic — `LINE_AMOUNT_MISMATCH`. *"Verify arithmetic; do not invent totals during mapping"* |

Bounds from the common rules: at most **100 lines** (`TOO_MANY_LINES`) and 256 KiB per request, enforced before the call rather than discovered as a 413.

### 5.3 Serialization rules the mapper must obey

These are the details that break a first integration, and most of them are unverifiable from this repository.

- **Decimals are strings with a fixed scale, a `.` separator, no grouping and no sign for positive values.** The trap is that ABAP's default numeric formatting in a string template follows the user's decimal notation, so a user configured for `1.500,00` would emit a body CAP refuses with `INVALID_DECIMAL`. The candidate is a raw, locale-independent format with an explicit scale; the exact syntax is probe P6. **Scale must be preserved, not trimmed:** `750.0000` and `1500.00` are the contract's forms, and although CAP's hash normalizes `1500.0` to the same delivery, the validator's scale check is what decides acceptance.
- **UUIDs are canonical hyphenated text.** `sysuuid_x16` is `RAW(16)`; the conversion to the 36-character form, and which released class provides it, is probe P5.
- **Timestamps are UTC RFC 3339.** Not needed in the outbound body — it carries no timestamp — but needed for `X-Correlation-ID` diagnostics and for the inbound leg. Probe P7.
- **Never serialize an initial date as a calendar date.** API_CONTRACTS is explicit: *"Do not serialize date `00000000` as a valid external calendar date."* The outbound order body has no date field at all, so this applies to the inbound leg; it is recorded here because `EstimatedDeliveryDate` is initial on every row today.
- **No draft field and no SAP-internal organizational field reaches CAP.** `IsActiveEntity`, `HasActiveEntity`, draft administrative data, `CreatedBy`/`CreatedAt`/`LastChangedBy`/`LastChangedAt`, `LocalLastChangedAt`, `Status`, `TotalAmount` on the header beyond `amount.value`, and the `LastError*` group are all absent from both DTOs. API_CONTRACTS: *"OData read wrappers and draft fields do not leak across the boundary"* and *"The UI service's draft-specific keys must not be copied into the integration contract."* The builder reads the **active** instance through EML, never a draft.
- **Supplier status is not sendable.** *"Supplier status is server-owned and defaults to RECEIVED; callers cannot choose ACCEPTED."* CAP enforces this structurally — the service entity has no `status` element — so there is nothing to omit, but the builder must not invent one.

### 5.4 Headers

| Header | Value | Basis |
| --- | --- | --- |
| `Content-Type` | `application/json` | common rules |
| `Idempotency-Key` | the `deliveryId` | *"`Idempotency-Key` equals `deliveryId` for ingestion… The corresponding body identity remains mandatory"* |
| `X-Correlation-ID` | a fresh UUID per attempt | *"identifies a transport attempt. A retry may get a new correlation ID while preserving the business delivery/response ID"* |

Phase 4 ignores both custom headers and reads identity from the body, which is why the body identity is the one that matters and the headers are diagnostics. Sending them anyway costs nothing and is what CI will forward in Phase 6.

---

## 6. Transport abstraction

### 6.1 Shape

```
ZJP_CL_ORDER_DELIVERY_BUILDER        RAP → source delivery DTO      (no HTTP, no JSON)
ZJP_CL_CAP_ORDER_MAPPER              source delivery → CAP JSON     (no HTTP)
ZJP_IF_OUTBOUND_TRANSPORT            the seam
  ├── ZJP_CL_OUTBOUND_TRANSPORT      real HTTP                      (needs probes P1–P4)
  └── ZJP_CL_TRANSPORT_FAKE          scripted responses for tests   (no network)
```

Business logic depends on the interface only. That is what lets a test drive a 201, a 200 replay, a 409 and a timeout without a network, and it is also what keeps the one unverified thing in this design — the released HTTP API — behind a single class.

### 6.2 Proposed interface

**Proposed source. Not activated, never compiled.** It deliberately uses nothing but `abap_bool` and built-in types, so it carries no dependency on an unverified released API and should compile under ABAP for Cloud Development as written — which the learner should confirm, since even that is a claim about a compiler this repository has not run.

```abap
INTERFACE zjp_if_outbound_transport
  PUBLIC.

  TYPES:
    BEGIN OF ty_header,
      name  TYPE string,
      value TYPE string,
    END OF ty_header,
    ty_headers TYPE STANDARD TABLE OF ty_header WITH EMPTY KEY.

  TYPES:
    BEGIN OF ty_request,
      " Path only. The base URL and its credentials belong to the destination
      " configuration, never to business code.
      path    TYPE string,
      headers TYPE ty_headers,
      body    TYPE string,
    END OF ty_request.

  TYPES:
    BEGIN OF ty_response,
      " abap_false means the receiver never answered: a timeout, a dropped
      " connection, an unresolvable host. It does NOT mean the delivery failed.
      answered     TYPE abap_bool,
      status       TYPE i,
      body         TYPE string,
      " Safe diagnostic text for the unanswered case. Never a stack or a URL.
      failure_text TYPE string,
    END OF ty_response.

  METHODS post
    IMPORTING request         TYPE ty_request
    RETURNING VALUE(response) TYPE ty_response.

ENDINTERFACE.
```

### 6.3 Why `post` returns an outcome instead of raising an exception

This is the one design decision in section 6 worth defending, because the obvious ABAP idiom is the wrong one here.

API_CONTRACTS states the rule the whole outbox exists to honour: **"A timeout never proves non-delivery."** An interface that raises an exception on a timeout hands the caller a single "it went wrong" and destroys the distinction between *definitely not delivered* and *possibly delivered*. Those two lead to opposite actions: one is `FAILED` and a genuine retry, the other is `UNKNOWN`, a replay of the **same** `deliveryId`, and a reconciliation path. Collapsing them is how a system ends up creating a second delivery for an order CAP already committed, which is exactly the failure mode `DeliveryReceipts` was pulled forward in Phase 4.3 to make survivable.

So `answered = abap_false` maps to `dispatch_state = UNKNOWN`, and a 4xx or 5xx maps to `FAILED` or a bounded retry according to the error-policy table. The mapping is deliberately **conservative**: a connection refused probably does prove non-delivery, but distinguishing it reliably from a timeout is not worth being wrong about, and over-classifying as `UNKNOWN` costs one replay — which Phase 4.3 verified is safe, returning the stored original receipt with 200. Recognising definite non-delivery is an optional 5.2+ refinement, not a requirement.

### 6.4 Receipt interpretation, for 5.2 to implement

| Outcome | `dispatch_state` | `IntegrationStatus` | Next action |
| --- | --- | --- | --- |
| 201 + receipt | `DELIVERED` | `DELIVERED` | store `portalOrderId`; business status → `SENT` |
| 200 + receipt (replay) | `DELIVERED` | `DELIVERED` | identical handling — this is what makes a replay safe |
| 400 | `FAILED` | `FAILED` | no retry; the payload or the mapping is wrong |
| 409 | `FAILED` | `FAILED` | **never** a blind retry. Either content changed under one `deliveryId`, or the source order was already ingested under a different one; both are reconciliation |
| 401 / 403 | `FAILED` | `FAILED` | configuration, not payload |
| 413 | `FAILED` | `FAILED` | reduce the request; no unchanged replay |
| 429 / 502 / 503 | `PENDING` | `PENDING` | bounded retry, same `deliveryId`, honour `Retry-After` |
| 500 | `UNKNOWN` | `UNKNOWN` | ambiguous; query the receipt or replay the same id |
| not answered | `UNKNOWN` | `UNKNOWN` | replay the same `deliveryId`; never mint a new one |

This is API_CONTRACTS' error-policy table applied to this endpoint. It is written down here so 5.2 implements a decided mapping rather than inventing one per status code.

---

## 7. Transaction boundary

### 7.1 The sequence, reviewed and not implemented

1. **Validate `APPROVED`.** Active instance only; refuse a technical draft before reading anything, the shape all four Phase 2 actions use. Also refuse if a non-terminal intent already exists for this order and revision, so `sendToSupplier` is not a way to mint a second delivery.
2. **Establish the durable intent and the `deliveryId`.** Created through EML inside the action's own LUW, together with `IntegrationStatus = PENDING` and `DeliveryId` on the header. The framework commits both or neither. This is the outbox: *"the pending record survives a process crash."*
3. **Preserve the immutable payload.** The source delivery snapshot is built from the buffer at this moment and written with the intent. It is never rebuilt from the order afterwards.
4. **Dispatch outside the business mutation boundary.** The coordinator claims a `PENDING` intent under a lease, then calls HTTP. **No HTTP in a determination, validation, save handler or action** — ARCHITECTURE: *"No HTTP side effects inside a determination or save handler"* — and **no `COMMIT WORK` in handler code**, per the RAP implementation contract: manual commits belong to the external consumer.
5. **Interpret the receipt** per the table in 6.4.
6. **Update RAP integration state** through EML in the coordinator's own LUW, then commit.

`sendToSupplier` requests delivery; it does not report it. ARCHITECTURE: *"Initially it leaves business status `APPROVED` and sets integration state `PENDING`."* `SENT` means the portal acknowledged persistence, which only step 6 can know.

### 7.2 Why the boundary is drawn there

A direct `POST` inside the action would be shorter and is rejected by ADR-006 for two concrete reasons rather than on principle. A remote change can survive a failed local transaction — CAP commits, the RAP LUW then rolls back, and SAP has no record of a delivery the portal has already accepted. And an HTTP call inside an action holds the BO lock for the duration of a network round trip, so a slow or hanging receiver becomes a lock held for the length of the timeout.

The split also makes the commit boundaries observable, which is why the first coordinator is a console application: two commits, in two separately runnable steps, with a durable row in between that can be inspected between them.

### 7.3 What remains reasoned rather than verified

The lease bounds concurrent dispatch, and no concurrency case has ever been exercised on this system (OI-13). Phase 4 closed with the same admission on the CAP side: *"no concurrent race was ever exercised on either service."* Two crash-recovery paths — an intent left `IN_FLIGHT` by a coordinator that died, and an expired lease reclaimed by a later run — are designed and untestable until 5.2 exists. None of this is claimed as working.

---

## 8. Blockers and questions needing learner SAP evidence

| ID | Blocker | Why it blocks | Recommendation |
| --- | --- | --- | --- |
| **B1** | `OrderRevision` is `0` on every row; CAP requires `source.revision ≥ 1` | A delivery built today is refused with 400 `INVALID_SOURCE_IDENTITY` before anything interesting runs | Write `OrderRevision = 1` in `submit`, beside `Status` and `PurchaseOrderNumber`, in its own 5.2 step. This is a **RAP behavior change**, so it needs its own activation round and an update to `ZJP_CL_PO_EML_TEST`. Rejected alternative: defaulting `0` → `1` in the builder, which hides a missing business fact inside a mapper and makes the revision a transport artifact |
| **B2** | `IntegrationStatus` is blank, not `NOT_REQUESTED` | Any state check in 5.2 has to know whether blank is a valid starting state | Either treat blank as `NOT_REQUESTED` on read, or add a determination. Decide in 5.2; do not leave it implicit |
| **B3** | No CAP URL is reachable from SAP | The outbound leg cannot exist | Learner picks tunnel or BTP deployment per 1.3, and records the choice in `docs/environments.md` |
| **B4** | `sourceSystem` has no decided value | It scopes every deduplication key in CAP and cannot be guessed at runtime | Adopt `PIH_ABAP_DEV` from the contract examples as a configured constant, and seed nothing else until a second system exists |
| **B5** | The released outbound HTTP API set is unknown | The transport implementation cannot be written | Probes P1–P4 |
| **B6** | The CAP ingestion endpoint has no authentication | Phase 5 is its first real caller, and a tunnel publishes it | Accept for the study and label it, or add a minimal credential; real authentication is Phase 8. Do **not** let a tunnel run unattended |
| **B7** | Whether a unique secondary index is available on this table artifact | Decides whether the one-delivery-per-revision rule is a constraint or reasoned code | Probe P8 |

Open items carried forward untouched: **OI-05** (this subphase is its first real work, still open), **OI-13** RAP stale-ETag and concurrency, the RAP `__OperationControl` UX gap, the permissive RAP authorization stub, the OI-03 remainder (the separate integration projection), and all eight items of CAP debt from the Phase 4.6 closure. Nothing here closes any of them.

---

## 9. Required ADT / runtime probes

Each probe is small, and each answers a question this repository cannot. **Report the exact compiler or runtime text, including failures** — the Phase 3.2 `@UI.facet` result is in the repository because a negative compiler answer was recorded rather than worked around, and that is worth more here than a guess.

| ID | Probe | What to report |
| --- | --- | --- |
| **P1** | In a throwaway class with language version **ABAP for Cloud Development**, check availability and release state of the outbound HTTP candidates: interface `if_web_http_client`, class `cl_web_http_client_manager`, class `cl_http_destination_provider` and its factory methods `create_by_url`, `create_by_comm_arrangement`, `create_by_cloud_destination`. Use ADT's Released APIs view / F2 element info rather than trusting a syntax check alone | For each name: exists or not, released for ABAP Cloud or not, and the exact method signature ADT shows. Also whether a request timeout can be set |
| **P2** | Can the learner create an ADT **Communication Scenario** with an **outbound** HTTP service, and is a Communication Arrangement reachable in this system? | Whether the object type is offered; the exact error if not; whether the communication-management apps exist on this client |
| **P3** | If P2 is unavailable, is a **URL-based** destination permitted under ABAP Cloud on this target? | Whether `create_by_url` is released, and any allowlist or proxy requirement |
| **P4** | Where does an outbound server certificate go on this system, and does the learner have permission to put one there? | The mechanism (`STRUST` or its replacement), the PSE used for outbound client calls, and whether an administrator is required |
| **P5** | `sysuuid_x16` → canonical 36-character hyphenated text. Candidates: `cl_system_uuid`, `xco_cp_uuid` | Which is released, the exact method, and one converted sample value so the case and hyphenation can be checked against the contract |
| **P6** | Decimal → contract string. Does a raw, locale-independent format with an explicit scale exist and compile — candidate `\|{ value NUMBER = RAW DECIMALS = 2 }\|`? | Whether it compiles, and the literal output for `1500.00` (scale 2) and `750.0000` (scale 4) **under a user whose decimal notation is `1.234,56`**, which is the case that matters |
| **P7** | `timestampl` → UTC RFC 3339 `2026-09-12T15:00:00Z`. Candidates: `cl_abap_tstmp`, `xco_cp_time`, `xco_cp=>sy->moment( )` | Which is released and one formatted sample |
| **P8** | Can a `DEFINE TABLE` artifact under ABAP Cloud carry a **unique secondary index**? | Whether it can, the ADT object type or syntax, and whether the client field must be included |
| **P9** | Is `abap.string` allowed as a non-key column in such a table, and are there restrictions (count per table, position, indexability)? | Yes/no plus any restriction, since `payload_snapshot` depends on it. If not, the fallback is a long `abap.char` and a documented maximum payload size |
| **P10** | JSON serialization. Candidates: `xco_cp_json`, `cl_sxml_string_writer` with `CALL TRANSFORMATION`, and `/ui2/cl_json` (expected **not** released for ABAP Cloud) | Which is released, and whether nested objects and exact camelCase member names can be controlled — the contract's names are case-sensitive |
| **P11** | Read the current integration-field values: `SELECT purchase_order_uuid, order_revision, integration_status, delivery_id FROM zjp_po_h` (read-only, permitted and documented) | Confirms `order_revision = 0` and `integration_status` blank on real rows, which section 2.2 asserts from source rather than from data |
| **P12** | Can the SAP system reach **any** external HTTPS endpoint? | The simplest available evidence, once P1 gives a usable client. If it cannot, B3 is not solvable by choosing a tunnel |

P1 and P2/P3 are the critical path: nothing in the transport implementation can be written before they are answered, and **no ABAP HTTP call will be authored from memory in this project.**

---

## 10. Proposed ABAP object inventory for Phase 5.2

None of these exist. Activation order matters — persistence before views, views before behavior.

| # | Object | Type | Purpose |
| --- | --- | --- | --- |
| 1 | `ZJP_PO_DLV` | Database table | Delivery intent persistence, section 4.2 |
| 2 | `ZJP_I_DeliveryIntent` | Root view entity | Exposes the table to RAP; no composition |
| 3 | `ZJP_I_DELIVERYINTENT` | Behavior definition | Managed, `strict ( 2 )`, **no draft**; every integration field `readonly`; no projection and no binding |
| 4 | `ZBP_I_DELIVERYINTENT` | Behavior pool | Claim-under-lease and state-transition handlers; instance authorization consistent with the existing study stub |
| 5 | `ZJP_IF_OUTBOUND_TRANSPORT` | Interface | The seam, section 6.2 |
| 6 | `ZJP_CL_TRANSPORT_FAKE` | Class | Scripted 201 / 200 / 409 / timeout for tests; no network |
| 7 | `ZJP_CL_OUTBOUND_TRANSPORT` | Class | Real HTTP. **Blocked on P1–P4** |
| 8 | `ZJP_CL_ORDER_DELIVERY_BUILDER` | Class | RAP buffer → source delivery DTO; no HTTP, no JSON |
| 9 | `ZJP_CL_CAP_ORDER_MAPPER` | Class | Source delivery → mapped CAP order JSON; pure and deterministic; owns `EA` → `PCE` |
| 10 | `sendToSupplier` | Action on `ZJP_I_PurchaseOrder` | Parameterless, active-instance only, `authorization : update`, following the verified `submit` / `approve` / `cancel` shape |
| 11 | `ZJP_CL_PO_DISPATCH_TEST` | Console class | The coordinator, run explicitly; claim, dispatch, record, commit |
| 12 | `ZJP_CL_PO_EML_TEST` | **Existing** console class | Must be extended whenever RAP behavior changes, per repository policy — so for both `sendToSupplier` and the B1 revision change |

Also for 5.2, and deliberately listed so they are not forgotten: the ADR-022 `APPROVED` → `CANCELLED` delivery-request guard, which `DeliveryIntent` finally makes representable; and the `IntegrationStatus` initial-value decision from B2.

`ZJP_PO_H`, `ZJP_PO_I`, both base views, both projections, both behavior definitions, the behavior pool, the service definition and the binding are **unchanged**. Nothing in Phase 5.2 as scoped here requires editing a Phase 1–3 artifact except adding one action line to the base BDEF and one write to `submit`.

---

## 11. Deferred to Phase 5.2 and later

| Item | Phase |
| --- | --- |
| `sendToSupplier` implementation and its intent creation | 5.2 |
| `OrderRevision = 1` at submit (B1) and the `IntegrationStatus` initial value (B2) | 5.2 |
| The real HTTP transport, after P1–P4 | 5.2 |
| The coordinator, the first real `POST`, and receipt handling | 5.3 |
| `retryDelivery`, the bounded retry budget and `attempt_count` | 5.x |
| `applySupplierResponse`, the restricted integration projection and Web API binding (OI-03 remainder) | 5.x |
| The CAP → SAP response sender, and CAP's transport state beyond `PENDING` | 5.x |
| `recordDeliveryResult` as a separate restricted operation | 5.x |
| Integration Suite, CPI/iFlows | 6 |
| DeliveryAttempt history | 7 |
| OAuth, XSUAA, IAS, destinations, production credentials | 8 |
| Event Mesh | 9 |
| API Management | 10 |
| Scheduler or background retry worker | later, release-dependent |

## 12. What Phase 5.1 did not do

No ABAP object was created or changed. No table, view, behavior definition, behavior pool, service definition or binding was touched. No HTTP request was made in either direction. No CAP file was modified, and no CAP behavior changed. Nothing was deployed, no tunnel was configured, and no credential was created. **Phase 5.1 is not runtime-verified, and Phase 5.2 is not started.**
