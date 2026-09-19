# Phase 5.1 — SAP ↔ CAP direct integration prerequisites and outbound foundation

**The connectivity half of this subphase is now runtime-verified; the design half is not.** An outbound probe from the S/4 sandbox has reached the deployed CAP application over HTTPS with OAuth2/XSUAA and completed a full ingestion, replay and conflict sequence — see **1.5** — which resolves blocker **B3** and answers probes **P1, P2/P3, P4 and P12**. That probe is a *technical* one: it proves the pipe, not the business flow.

**Two implementation slices have since been built from this design and are SAP runtime-verified.** **Phase 5.2a** resolved blockers **B1** and **B2** — `submit` writes `OrderRevision = 1` and `initializeStatus` writes `IntegrationStatus = 'NOT_REQUESTED'` — changing RAP behavior in two existing classes without adding any object. **Phase 5.2b** built the `DeliveryIntent` persistence and RAP business object: `ZJP_PO_DLV`, the unique Table Index `ZJP_PO_DLV~REV`, `ZJP_I_DeliveryIntent`, `ZJP_I_DELIVERYINTENT`, `ZBP_I_DELIVERYINTENT` and a `ZJP_CL_PO_EML_TEST` extension, resolving blocker **B7** and answering probes **P8** and **P9**.

**Phase 5.2g is SAP runtime-verified**, and with it the whole of Phase 5.2: the post-commit coordinator claims a persisted intent under a lease and commits, posts the immutable approved snapshot through the verified seam, and records the outcome in a second transaction — a real run returned HTTP 201 with the intent DELIVERED and the order moved APPROVED to SENT. See section 9.4. **Phase 5.2c is SAP runtime-verified.** The transport seam of section 6.2, its deterministic fake and a console harness for both — `ZJP_IF_OUTBOUND_TRANSPORT`, `ZJP_CL_TRANSPORT_FAKE` and `ZJP_CL_TRANSPORT_TEST`, objects 5, 6 and 13 — activated cleanly and the harness ran to `PASS: Phase 5.2c outbound transport abstraction verified.` with no `STOP` and no short dump. **Phase 5.2d is SAP runtime-verified.** P5, P6 and P10 are answered, and the builder, the mapper and their harness — `ZJP_CL_ORDER_DELIVERY_BUILDER`, `ZJP_CL_CAP_ORDER_MAPPER` and `ZJP_CL_BUILDER_TEST`, objects 8, 9 and 14 — activated and ran to `PASS: Phase 5.2d outbound builder and CAP mapper verified.` **Phase 5.2e is SAP runtime-verified**: P15 is answered, and `ZJP_CL_OUTBOUND_TRANSPORT` with its harness `ZJP_CL_HTTP_TRANSPORT_TEST`, objects 7 and 15, activated and ran a real OAuth-protected POST to the deployed portal for 201, 200, 409 and a classified technical failure. **Phase 5.2f is SAP runtime-verified** — `sendToSupplier` creates or reuses the durable delivery intent inside the order's own LUW, across all eight branches of the 7.4 contract, with no network call in the path. **Phase 5.2g is next and is NOT STARTED.** The real transport class, the coordinator and `sendToSupplier` remain design only — as do `DeliveryId` and the `IntegrationStatus` transitions beyond `NOT_REQUESTED`. There is no projection, no OData binding, no draft, no HTTP and no revision-increment behaviour anywhere in what has been built. Statements about the target system's released API set are marked as **candidates** until the learner returns ADT or compiler output, because per repository policy the SAP ADT compiler and SAP runtime evidence are authoritative and this repository is not — and P1 is a standing illustration of why, since the candidates it named were not the class that actually worked.

Read with [API_CONTRACTS.md](../../API_CONTRACTS.md) — which is the source of truth for the wire shapes below and was not modified here — and the [Phase 4.6 closure](../../cap-supplier-portal/docs/phase-4-6-closure.md), which records the CAP half of the handoff.

## Baseline

| Item | Value | Provenance |
| --- | --- | --- |
| Repository state | clean at `62dc04d Complete Phase 4 closure` | `git status`, `git log -1 --oneline` |
| RAP phases | 1, 2 (through 2.7E), 3.1, 3.2 complete, SAP runtime-verified | [PROJECT_STATUS.md](../../PROJECT_STATUS.md) |
| CAP phases | 4.1–4.6 complete, **local Node.js execution only** | [Phase 4.6 closure](../../cap-supplier-portal/docs/phase-4-6-closure.md) |
| ABAP target | SAP_BASIS 758 SP0001 / S4CORE 108 SP0001, ABAP Cloud; ADT Core 3.60.3, BO Tools 1.209.0 | [ARCHITECTURE.md](../../ARCHITECTURE.md) |
| Traffic between the systems so far | **SAP → CAP is proven**: destinations `ZJP_CAP` / `ZJP_CAP_INGEST`, OAuth2 client credentials, and a 201 / 200 replay / 409 conflict sequence from ABAP. CAP → SAP is still none | section 1.5 |
| Verified CAP ingestion route | `POST /rest/integration/v1/Orders` | Phase 4.3 locally; since verified against the deployed application on HANA, and now from SAP |

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
| Released outbound HTTP client API for ABAP for Cloud Development on this target | **ANSWERED by SAP runtime evidence.** The working chain is `CL_OUTBOUND_PROVIDER_HTTP=>CREATE_BY_DESTINATION` → `IF_HTTP_DESTINATION` → `CL_WEB_HTTP_CLIENT_MANAGER=>CREATE_BY_HTTP_DESTINATION` → `IF_WEB_HTTP_CLIENT`, executed against destination `ZJP_CAP` and returning HTTP 200 from `/health/ping`. **Note that `CL_OUTBOUND_PROVIDER_HTTP` was not among the candidates P1 listed** — the repository guessed at `cl_http_destination_provider` and its `create_by_url` / `create_by_comm_arrangement` / `create_by_cloud_destination` factories, and the real answer was a different class reached by destination name. The **ABAP language version** of the class that ran this is not yet recorded | settled by the learner's execution; language version still to be confirmed (P1-followup) |
| A supported way to declare the outbound target (communication scenario / arrangement, or a URL destination) | **ANSWERED.** Two HTTP destinations exist and work: **`ZJP_CAP`** for `/health/ping` and **`ZJP_CAP_INGEST`** for `/rest/integration/v1/Orders`, with OAuth2 attached through client profile **`ZJP_CAP_OAUTH`** and client configuration **`ZJP_CAP_XSUAA`** — grant type client credentials, client authentication HTTP Basic / standard HTTP, resource authentication via the `Authorization` header. So the mechanism on this system is a **destination**, not a communication arrangement | settled by the learner |
| Server certificate trust for an HTTPS call out of the ABAP system | **ANSWERED.** The outbound call uses SSL client PSE **ANONYM**. The first handshake failed with **`SSSLERR_PEER_CERT_UNTRUSTED`**, and importing **DigiCert TLS RSA4096 Root G5** into that PSE's trust list resolved it. This is the trust anchor *this* Cloud Foundry endpoint's chain required and must not be generalized to other environments | settled by the learner |
| A CAP URL the SAP system can actually resolve and reach | **RESOLVED — SAP has reached it.** CAP is deployed to Cloud Foundry at `https://0badc38dtrial-dev-cap-supplier-portal-srv.cfapps.us10-003.hana.ondemand.com`, replacing the original `http://localhost:4004` that SAP could never have reached. The S/4 sandbox now calls it: once certificate trust was fixed, the `ZJP_CAP` connection test returned **HTTP 401** — which was itself the decisive evidence, because a 401 can only come from CAP, so DNS, routing, TLS and the application were all proven in one negative answer — and after OAuth was configured the same test returned **HTTP 200 / OK**. ABAP code then read `/health/ping` and received **200** with `status UP`, `component cap-supplier-portal` | settled; see B3 |
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

| | **A. Deliberately configured HTTPS development tunnel** — *fallback / debug only* | **B. CAP deployed to a reachable hosted runtime (BTP Cloud Foundry)** — **preferred** |
| --- | --- | --- |
| What it is | A tunnel service publishes a public HTTPS hostname that forwards to `localhost:4004` | `cf push` of the CAP application; BTP terminates TLS on a platform route |
| Environment-record basis | *"A deliberately configured development tunnel or supported private-connectivity route is a temporary alternative and must be recorded explicitly"* | *"Prefer deploying CAP to the selected BTP runtime when available"* |
| Setup cost | Minutes; no entitlement needed | **No longer blocked by an unknown account.** Verified since this subphase was written: BTP **Trial** Cloud Foundry is available in region **`us10-003`**, space **`dev`** exists and is usable, and the persistence it needs already exists there — **`pih-hana`** (service `hana-cloud`, plan `hana-free`) and **`pih-hdi`** (service `hana`, plan `hdi-shared`). CAP is also already configured for HANA on its production profile. Trial accounts carry evaluation limits; see the trial-versus-free-tier caveat in [environments.md](../../docs/environments.md) |
| Certificate trust on the SAP side | The tunnel provider's CA must be trusted by the ABAP system (probe P4) | The platform route's CA must be trusted by the ABAP system (probe P4) |
| Stability of the URL | Usually changes on every restart, so it cannot be baked into anything | Stable per deployment |
| What it does **not** prove | BTP deployment and operations; nothing about HANA; the endpoint is still unauthenticated | Nothing about the tunnel path; still not production authentication |
| Security caveat | It **publishes an unauthenticated ingestion endpoint to the internet** for as long as it runs. Phase 4.6 debt item 2 is exactly this: *"No authentication on the integration endpoint, which Phase 5 will be the first real caller of"* | Also unauthenticated unless something is added; at least the route is not a hole into the laptop |

**Decision: option B. The preferred Phase 5 path is `S/4 sandbox → HTTPS → CAP deployed to BTP Cloud Foundry`.** A public tunnel is demoted to a fallback and debugging aid and is no longer the route to the first round trip.

This **revises the earlier recommendation in this document**, which put the tunnel first. That recommendation rested on two premises, and the first has since been falsified: it assumed BTP entitlement was an unknown that would be slow and possibly costly to resolve, and it assumed the tunnel was therefore the cheapest way to prove the ABAP HTTP client, the mapping and the receipt handling. What is now verified instead:

- BTP **Trial** Cloud Foundry is available, in region `us10-003`.
- Space **`dev`** exists and is usable.
- **`pih-hana`** (`hana-cloud` / `hana-free`) exists.
- **`pih-hdi`** (`hana` / `hdi-shared`) exists.
- The **CAP production profile is already prepared for HANA**, and `cds build --production` already generates an HDI deployer module.

So the work the tunnel was meant to defer is largely done, and the deferral now costs more than it saves. Three further reasons make option B the better path rather than merely an available one. Its **URL is stable per deployment**, where a tunnel hostname usually changes on every restart — and a stable URL is what a communication/destination configuration on the SAP side can actually be pinned to, which matters because setting that configuration up is itself one of the unanswered questions. It **does not publish an unauthenticated ingestion endpoint from the developer laptop to the internet**, which the security-caveat row above describes and which Phase 4.6 debt item 2 names directly. And it exercises the deployment path that Phase 5 needs anyway, so the round trip is proven against the thing that will run rather than against a temporary stand-in.

**The tunnel remains documented, as a fallback only.** It is still the right tool for debugging a request against a locally running CAP with breakpoints, and for the case where a deployment is blocked. Its two conditions are unchanged and follow from the project's own rules: it must be **recorded explicitly** in `docs/environments.md` whenever it is used, per the Network reality paragraph, and it must be **shut down when not actively testing**, because the endpoint it exposes has no authentication at all and Phase 4 verified that it accepts any well-formed delivery.

**The decision has since been carried out and walked.** CAP is deployed to Cloud Foundry, bound to `pih-hdi` and a real XSUAA instance, running 1/1 behind a stable HTTPS route, **and the S/4 sandbox has called it** — so **blocker B3 is resolved**. The SAP-side questions this paragraph listed as unsettled are answered: the outbound target is declared on this system as an **HTTP destination** rather than a communication arrangement or a URL destination (P2/P3), and certificate trust goes into the **ANONYM** SSL client PSE, where importing DigiCert TLS RSA4096 Root G5 fixed an initial `SSSLERR_PEER_CERT_UNTRUSTED` (P4). The stability argument above earned its keep: the destination was pinned to a fixed deployed hostname, which a tunnel could not have offered. What remains unsettled is *not* connectivity but the business outbound work — no RAP order is mapped, no `DeliveryIntent` exists and `sendToSupplier` is not implemented. Trial accounts also carry evaluation limits and lifecycle constraints that are environment-specific and must be read from the cockpit rather than from this document.

### 1.4 HTTPS

API_CONTRACTS common rules: *"HTTPS outside loopback development."* Both options above are HTTPS on the public leg, so the requirement is met by either. The ABAP side of it is now **settled by execution**: the outbound call uses the **ANONYM** SSL client PSE, the first handshake failed with **`SSSLERR_PEER_CERT_UNTRUSTED`**, and importing **DigiCert TLS RSA4096 Root G5** into that PSE's trust list made the call succeed. The learner had the permission; no administrator was required.

This is worth stating narrowly. It is evidence about **this** Cloud Foundry route's certificate chain at **this** moment, not a general rule: a different endpoint, a different landscape, or a rotated chain on this same route needs its own trust answer. Recording "DigiCert G5 was the missing anchor" is useful precisely because it names a specific chain rather than a policy.

### 1.5 Outbound runtime probe — SAP → CAP, runtime-verified

**This is a technical outbound runtime probe, not the `sendToSupplier` implementation.** It was executed by the learner against the real S/4HANA development sandbox and the deployed CAP application. What it proves is the *pipe*:

```
SAP ABAP → HTTP destination → TLS → OAuth2 / XSUAA → CAP IntegrationService → HANA ingestion
```

**Configuration.** Destinations `ZJP_CAP` (`/health/ping`) and `ZJP_CAP_INGEST` (`/rest/integration/v1/Orders`); SSL client PSE ANONYM with DigiCert TLS RSA4096 Root G5 imported; OAuth2 client profile `ZJP_CAP_OAUTH` with configuration `ZJP_CAP_XSUAA`, grant type **client credentials**, client authentication HTTP Basic / standard HTTP, resource authentication via the `Authorization` header. The XSUAA token endpoint is reachable from SAP, `OA2C_GENERIC_ACCESS` obtained a token, and the token carries `<xsappname>.IntegrationClient` and `uaa.resource`. No secret and no token is recorded here.

**Connectivity.** Before OAuth, the `ZJP_CAP` connection test returned **HTTP 401** — the single most informative result in the sequence, because a 401 can only be produced by CAP itself, so DNS, routing, TLS trust and the running application were all proven by a *failure*. After OAuth it returned **HTTP 200 / OK**. ABAP code using the chain in P1 then read `/health/ping` and received **200** with `status UP`, `component cap-supplier-portal`.

**Invalid ingestion.** A POST of `{}` through `ZJP_CAP_INGEST` returned **HTTP 400** with the portal's own `SCHEMA_VERSION_UNSUPPORTED`, which proves the request cleared OAuth/XSUAA and entered the `IntegrationService` handler rather than being stopped by the platform.

**Valid ingestion, replay and conflict.** A hand-built valid delivery — `source.system = PIH_ABAP_PROBE`, `supplierCode = RTTEST001`, EUR, PCE, one line, quantity `2.000`, unit price `25.0000`, amount `50.00`, fixed delivery/source/item UUIDs:

| Execution | Result |
| --- | --- |
| First | **201**, status `RECEIVED`, `portalOrderId` `e6f96663-ed98-478f-9692-036f78a92682`, `receivedAt` `2026-09-17T23:47:58.476Z` |
| Exact repeat, unchanged payload | **200**, same `portalOrderId`, same `receivedAt` — idempotent replay proven **from SAP** |
| Same `deliveryId`, changed but internally valid content (quantity `3.000`, lineAmount `75.00`, total `75.00`) | **409 `DELIVERY_PAYLOAD_CONFLICT`**; the stored order remained unchanged |

**What this does not prove.** The payload was hand-built, so none of the business outbound work is evidenced: the real RAP purchase order is **not** mapped into the DTO, `OrderRevision` is not populated, the `DeliveryId` and `IntegrationStatus` lifecycles do not exist, `sendToSupplier` does not exist, the HTTP outcome is not persisted back into RAP, the transaction boundary of section 7 is not implemented, and there is no retry or reconciliation. The probe closes **B3** and the transport unknowns; it starts none of section 10.

---

## 2. RAP integration state review

### 2.1 The nine fields exist, are mapped, and are written by nothing

Inspected: [zjp_po_h.ddl](../persistence/zjp_po_h.ddl), [zjp_i_purchaseorder.ddls](../cds/zjp_i_purchaseorder.ddls), [zjp_i_purchaseorder.bdef](../behavior/zjp_i_purchaseorder.bdef), [zjp_c_purchaseorder.bdef](../behavior/zjp_c_purchaseorder.bdef) and the behavior pool [locals](../classes/zbp_i_purchaseorder.clas.locals_imp.abap).

| Element | Table column | DDIC type | BDEF | In buyer projection | Written by any handler | Phase 5 need |
| --- | --- | --- | --- | --- | --- | --- |
| `OrderRevision` | `order_revision` | `abap.int4` | `readonly` | yes | **yes, since 5.2a** — `submit` writes `1` | becomes `source.revision`; **done** |
| `IntegrationStatus` | `integration_status` | `abap.char(16)` | `readonly` | yes | **yes, since 5.2a** — `initializeStatus` writes `NOT_REQUESTED` | dispatch lifecycle; **initial value done**, transitions are 5.2b+ |
| `DeliveryId` | `delivery_id` | `sysuuid_x16` | `readonly` | yes | **no** | **5.2** — current delivery identity |
| `LastErrorCode` | `last_error_code` | `abap.char(60)` | `readonly` | yes | **no** | 5.2 — on FAILED/UNKNOWN |
| `LastErrorMessage` | `last_error_message` | `abap.char(255)` | `readonly` | yes | **no** | 5.2 — on FAILED/UNKNOWN |
| `LastErrorAt` | `last_error_at` | `abp_lastchange_tstmpl` | `readonly` | yes | **no** | 5.2 — on FAILED/UNKNOWN |
| `LastCorrelationId` | `last_correlation_id` | `sysuuid_x16` | `readonly` | yes | **no** | 5.2 — one per transport attempt |
| `LastResponseId` | `last_response_id` | `sysuuid_x16` | `readonly` | yes | **no** | **5.3+** — inbound only |
| `LastResponseVersion` | `last_response_version` | `abap.int4` | `readonly` | yes | **no** | **5.3+** — inbound only |

Three neighbouring fields are in the same situation and belong to the inbound leg: `SupplierResponse` `char(8)`, `EstimatedDeliveryDate` `dats` and `RejectionOrigin` `char(10)` — the last is written by `reject` for the `APPROVER` case only.

The evidence when this section was written was that the behavior pool contained exactly eight `UPDATE FIELDS` clauses, over `TotalAmount`, `Status`, `PurchaseOrderNumber`, `RejectionOrigin` and `RejectionReason`, and that the only occurrence of any integration field name in the whole pool was a comment explaining why the `APPROVED` → `CANCELLED` delivery guard could not be implemented in Phase 2. That matched the recorded debt — *"Display number, supplier name and integration fields remain initial"*.

**Phase 5.2a changed exactly two of the nine, and no more.** `submit` now writes `OrderRevision` in the same clause that writes `Status` and `PurchaseOrderNumber`, and `initializeStatus` now writes `IntegrationStatus` in the same clause that writes `Status` — two fields added to two existing clauses, so the clause count is unchanged and no new handler was introduced. The remaining **seven** integration fields are still written by nothing. The mechanism is the one this paragraph already described: `readonly` in the BDEF stops external callers, while a handler writes through `MODIFY ... IN LOCAL MODE`, exactly as `submit` has always written `Status` and `PurchaseOrderNumber` — and the 5.2a activation confirms that reading is correct, since the compiler accepted both writes and the runtime performed them.

### 2.2 No header field is missing — and two carried wrong values, now fixed in 5.2a

**Nothing needs to be added to `ZJP_PO_H`.** All nine integration fields specified by the domain model are present, typed, mapped and exposed. `IntegrationStatus` `char(16)` holds the longest documented value (`NOT_REQUESTED`, 13 characters) with room to spare. Per the instruction not to add fields without contract evidence, no column is proposed for the header.

Two **value** gaps were real, verified, and would have turned into hard failures the moment a delivery was built. **Both are now resolved by Phase 5.2a and SAP runtime-verified.** The diagnosis below stands as written; the resolution is recorded under each gap.

**Gap 1 — `OrderRevision` is `0` and CAP requires `≥ 1`.** The domain model says *"Positive integer; Starts at 1; frozen at submission"*. No handler writes it, so every row in `ZJP_PO_H` carries the `abap.int4` initial value `0`. On the CAP side this is not a soft preference: [`srv/lib/ingestion.ts`](../../cap-supplier-portal/srv/lib/ingestion.ts) rejects it —

```ts
if (!Number.isInteger(sourceRevision) || sourceRevision < 1) {
  return fail('INVALID_SOURCE_IDENTITY', 'source.revision is required and must be a positive integer.')
}
```

so a delivery built from today's persistence would be refused with **400 `INVALID_SOURCE_IDENTITY`** before any interesting behavior was reached. `sourceRevision` also participates in `Orders(sourceSystem, sourceOrderId, sourceRevision)`, the uniqueness rule that decides whether a re-sent order is a duplicate or a new revision, so it cannot be quietly defaulted at the boundary. This is documented debt becoming a blocker, not a newly introduced defect — nothing regressed — and it is blocker B1 in section 8.

> **RESOLVED in Phase 5.2a, SAP runtime-verified.** `submit` now writes `OrderRevision = 1` in the same local-mode `UPDATE FIELDS` clause as `Status` and `PurchaseOrderNumber`, so the three facts a successful submit establishes commit or roll back together. The recommended fix was taken and the rejected alternative was not: the revision is **not** defaulted from `0` to `1` in a mapper or transport class, because that would hide a missing business fact and make the revision an artifact of the wire format. A `DRAFT` order keeps revision `0` and is therefore deliberately undeliverable, which is now a property of the data rather than a caveat in a document. Verified: `PASS: new order before submit - OrderRevision 0, IntegrationStatus NOT_REQUESTED.`, `PASS: submit set the buffered OrderRevision to 1; IntegrationStatus stayed NOT_REQUESTED.`, `PASS: after successful submit - OrderRevision 1, IntegrationStatus NOT_REQUESTED.` **There is no revision increment and no revision 2 behaviour**: 5.2a establishes only the initial frozen revision the current lifecycle needs.

**Gap 2 — `IntegrationStatus` is blank, not `NOT_REQUESTED`.** No determination initializes it, so existing rows hold `''` while the domain model enumerates `NOT_REQUESTED, PENDING, IN_FLIGHT, DELIVERED, FAILED, UNKNOWN`. Any 5.2 read must treat blank as "never requested" or a determination must establish the initial value. Both are defensible; neither is decided here, and neither is implemented here.

> **RESOLVED in Phase 5.2a for new orders, SAP runtime-verified.** The second option was chosen: the existing `initializeStatus` determination now writes `IntegrationStatus = 'NOT_REQUESTED'` in the same clause that writes `Status = 'DRAFT'`, so a newly created root can never exist with one initialized and the other not. It was extended rather than joined by a second determination, because both values answer the same question — what a newly created root starts as — and two handlers on the same `on modify { create; }` trigger would duplicate the read and carry no ordering guarantee between their writes. An explicit `NOT_REQUESTED` is what lets a later delivery check compare against a real value instead of treating blank as an implicit fourth state.
>
> **Legacy rows are intentionally not mass-updated.** Rows persisted before Phase 5.2a keep their blank `IntegrationStatus` and are documented as pre-Phase-5 data. Two mechanisms guarantee it: the determination is declared `on modify { create; }` so it never fires for existing rows, and its guard `DELETE purchase_orders WHERE Status IS NOT INITIAL` drops any instance that already has a status. That guard was deliberately **not** widened to `IntegrationStatus` — legacy rows have a filled `Status` and a blank integration value, so guarding on the blank one would have classified them as uninitialized and reset their `Status` to `DRAFT`. The narrow guard is load-bearing, not incidental. Verified across every fixture: `IntegrationStatus = NOT_REQUESTED` on all newly created orders, while the lifecycle summary prints `-` for older rows and asserts nothing about them.

### 2.3 One Phase 2 obligation becomes reachable

ADR-022 deliberately did not implement the domain model's rule that `APPROVED` may be cancelled only before delivery was requested, on the grounds that *"`IntegrationStatus` and `DeliveryId` are readonly and no Phase 2 handler can write them, so the condition is unrepresentable as true"*. Once `DeliveryIntent` exists and `sendToSupplier` writes it, the condition becomes representable and the guard becomes testable. **That guard is a Phase 5.2 obligation and is not implemented here.** It is recorded so it is not silently dropped.

**Phase 5.2a changed that premise without changing the conclusion**, and the distinction is worth being precise about. A handler *can* now write `IntegrationStatus`, so the original wording is no longer literally true. But the only value it writes is **`NOT_REQUESTED`**, which is exactly the state meaning no delivery has been requested; nothing advances it, and `DeliveryId` is still written by nothing. So the guard condition still cannot become true, the guard is still untestable, and it remains a 5.2b+ obligation. The comments in the behavior pool and the EML test that justified the missing guard were corrected to state this reason rather than the superseded one.

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

The rule to enforce is the domain model's: *"Never create a fresh delivery ID merely because a network call timed out."* In table terms, this section originally proposed **one non-terminal delivery per `(purchase_order_uuid, order_revision)`**.

> **Decision changed in Phase 5.2b, once P8 was answered.** The rule enforced is now **exactly one DeliveryIntent per `(CLIENT, PURCHASE_ORDER_UUID, ORDER_REVISION)`, ever** — deliberately stronger than the non-terminal wording, and it is stronger because a unique index cannot express "non-terminal" at all. Three reasons make the stronger rule the right one rather than a concession to the mechanism: a retry must reuse the **same** `deliveryId`, so a second intent at the same revision should never be minted; section 6.4 already forbids minting a new id for an unanswered attempt; and a corrected commercial snapshot should eventually require a **higher `OrderRevision`**, not a second intent at the same one. The consequence accepted knowingly is that a `FAILED` intent at a given revision can only be superseded by a higher revision — and **revision-increment behaviour does not exist yet and is not implemented in 5.2b**.

Phase 4.3's lesson was that this class of rule belongs in a database constraint rather than a read-before-insert check, because two concurrent requests can both pass a check. That lesson does not transfer cleanly here, and pretending it does would be the mistake:

- Whether a `DEFINE TABLE` artifact under ABAP Cloud can carry a **unique secondary index**, and what the ADT syntax or object type for that is, is **not established by this repository**. It is probe P8. On a client-dependent table such an index would include `client`.
- If it can, declare it, and the rule is enforced the way CAP's is.
- If it cannot, the fallback is a read inside the `sendToSupplier` handler plus the observation that RAP takes a **root lock** on the order, which serializes two `sendToSupplier` calls on the same order in a way two concurrent HTTP POSTs to CAP were not serialized. That is a genuinely different and stronger starting position than the CAP case — but it is **reasoning, not evidence**, and OI-13 records that no concurrency case has ever been exercised on this system. It must be written down as reasoned.

> **P8 answered: it can, so the first branch applies and the reasoned fallback is not needed.** The mechanism is a separate **Table Index** repository object rather than `DEFINE TABLE` syntax, `UNIQUE` is supported, and `CLIENT` must be listed explicitly — ADT rejected the index with `client field required for unique index` until it was added as the first field. The rule is therefore enforced by the database, the way CAP's is. The guess in the bullet above was right that `client` would participate and wrong that the index would live in the table artifact, which is why the question was asked rather than inherited.
>
> **The index is now physically present and runtime-proven to enforce the rule — with two findings that matter more than the yes/no answer.**
>
> **First, an active DDIC index is not a database index.** `ZJP_PO_DLV~REV` was created and activated, and a deliberate duplicate-revision test then **persisted two rows**. The definition was never wrong; the physical database index simply did not exist yet, and activating the dictionary object did not create it. **SE14** was needed to confirm and create it. SE11 now shows `REV` as **Unique** over `CLIENT`, `PURCHASE_ORDER_UUID`, `ORDER_REVISION`, and SE14 shows the index present in the database. Anything that reads an index's activation status as proof of enforcement is reading the dictionary, not the database.
>
> **Second, a violation dumps rather than failing gracefully.** With the index physically in place, a second intent for the same order and revision — carrying a **different** generated `DeliveryUUID`, which is what makes the evidence conclusive, since the collision can only have been on the secondary business index — terminated in `CX_SY_OPEN_SQL_DB` → `CX_CSP_ACT_INTERNAL` → `RAISE_SHORTDUMP` inside `CL_CSP_ACT_SAVE_TO_DB`, the database reason naming a duplicate primary or unique secondary key. So a managed RAP `COMMIT ENTITIES` that reaches a physical unique-index violation does **not** return `FAILED`/`REPORTED`: RAP's response machinery covers what the framework validates, not what the database refuses beneath it.
>
> **Consequence for testing, not for the constraint.** The index stays exactly as declared and remains the final persistence safety net. But a test whose proven outcome is a short dump cannot sit in a regression suite — a dump aborts the run and leaves every later assertion unexecuted, so provoking it on every pass tests *less*. Uniqueness is therefore recorded as **manual infrastructure evidence** (ADT activation, SE11 unique flag, SE14 physical presence, and the ST22 dump above), while the automated suite keeps the **positive** form of the invariant: after a successful create, exactly one intent exists for that order and revision. Neither escape was taken — no direct SQL write to force the duplicate, and no catching or suppressing of the dump.

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
  ├── ZJP_CL_OUTBOUND_TRANSPORT      real HTTP                      (P1–P4 now answered)
  └── ZJP_CL_TRANSPORT_FAKE          scripted responses for tests   (no network)
```

Business logic depends on the interface only. That is what lets a test drive a 201, a 200 replay, a 409 and a timeout without a network, and it is also what keeps the one unverified thing in this design — the released HTTP API — behind a single class.

### 6.2 Proposed interface

**Built and activated in Phase 5.2c.** The interface below is what `abap-rap/interfaces/zjp_if_outbound_transport.intf.abap` contains, unchanged from this proposal apart from comments: the type names, the field names, the field types and the `post` signature are exactly as specified here, because a seam that drifts between its design and its source is worse than no seam. It deliberately uses nothing but `abap_bool` and built-in types, so it carries no dependency on an unverified released API — and **that claim is now settled rather than reasoned**: it activated under this target's compiler as written, and a consumer holding `REF TO ZJP_IF_OUTBOUND_TRANSPORT` dispatched through it to a fake at runtime.

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

### 6.5 The fake, as built in Phase 5.2c

`ZJP_CL_TRANSPORT_FAKE` implements the interface above and nothing else. It is **pure in-process ABAP**: its executable code references no identifier other than itself and `ZJP_IF_OUTBOUND_TRANSPORT`, so it opens no connection, names no destination, and mentions no HTTP client, OAuth profile or CAP route. That is checkable rather than asserted — a scan of the file for every `cl_*`, `if_*`, `cx_*` and `z*` identifier outside comments returns exactly those two names.

**Configuration is constructor injection and nothing else.** One instance is one scripted outcome, fixed for its lifetime; a test that drives four scenarios creates four instances, so no call can be influenced by a previous one. There is no factory, no registry, no setter and no shared state. The scenarios are public constants, used as `zjp_cl_transport_fake=>scenario-created`.

| Scenario constant | `answered` | `status` | `body` | `failure_text` |
| --- | --- | --- | --- | --- |
| `scenario-created` | `abap_true` | `201` | the fixture receipt | empty |
| `scenario-replayed` | `abap_true` | `200` | **the same fixture receipt, byte for byte** | empty |
| `scenario-conflict` | `abap_true` | `409` | the `DELIVERY_PAYLOAD_CONFLICT` envelope | empty |
| `scenario-unanswered` | `abap_false` | `0` | empty | safe text, no stack and no URL |
| anything else | `abap_false` | `0` | empty | names the unknown scenario |

Three decisions in that table are deliberate and worth defending.

**201 and 200 return the identical body.** Phase 4.3 verified that an exact replay answers with the *stored original* receipt, same `portalOrderId` and same `receivedAt`, which is what makes a replay safe and is why 6.4 gives both rows identical handling. Encoding that as byte equality gives a test a sharp assertion: the two bodies must be equal, and only the status may differ.

**An unknown scenario is a loud deterministic failure, not a default success.** It is reported through the same outcome record rather than an exception, so the fake needs no exception class and keeps its promise of depending on no released API. A misconfigured test therefore fails as an unanswered call naming the bad scenario, instead of quietly resembling a 201.

**The receipt identifiers are fixtures and are not echoed from the request.** The request is accepted and ignored. Correlating a receipt with the delivery that was sent requires reading the request body as JSON, which belongs to the mapper in 5.2d and to `sendToSupplier` in 5.2f — doing it here would drag payload concerns across the seam this section exists to draw. The consequence is precise and must not be forgotten: **the fake proves outcome classification, not body correlation.** A future test may assert that a 409 was classified as a conflict; it may not assert that the receipt belongs to the delivery it sent.

**The harness, and what its run proved.** `ZJP_CL_TRANSPORT_TEST` (10.1) drives all four scenarios and prints one `PASS` line each. **It has been activated and executed, and all four passed**, ending with `PASS: Phase 5.2c outbound transport abstraction verified.` — no `STOP`, no short dump. CREATED returned `answered = X`, `201` and the fixture receipt; REPLAYED returned `answered = X`, `200` and a body **byte-identical** to the CREATED receipt; CONFLICT returned `answered = X`, `409` and a body carrying `DELIVERY_PAYLOAD_CONFLICT`; UNANSWERED returned `answered = false`, status `0`, an initial body and `Fake transport: the receiver did not answer.` Two properties of the harness matter more than the assertions themselves. Every scenario runs through a `REF TO ZJP_IF_OUTBOUND_TRANSPORT` and the concrete class is named only at construction, so what the run proves is that **the seam works**, not merely that a class with the right method names exists. And the replay scenario builds **its own** CREATED instance to compare against rather than reusing the previous test's result, which keeps the four scenarios independent and, for free, proves the determinism is a property of the class rather than of one instance's history — the run confirmed it, since two separately constructed fakes produced byte-identical receipts. A failed assertion prints a `STOP` line and returns — no exception, no dump, and nothing to commit or roll back, since the fake touches no database.

**One syntax finding came out of the run, and it is the kind this repository keeps.** The CONFLICT assertion uses the ABAP `CS` containment operator, which was the **first use of any string-containment operator in this project** — there was no precedent to copy, so it was written as core language rather than as a released API and flagged as unproven on this target. It **compiled and executed correctly**. That is a small answer, but it is the same shape as every other answer here: the repository now records `CS` as working on this system because it ran, not because it looked right. It also keeps the CONFLICT body check honest — a deterministic substring test, with no JSON reader dragged across the seam.

**One thing the fake deliberately does not do: it does not record the request it was given.** A capturing fake would let a later coordinator test assert the path, headers and body that were dispatched, which is a real need for 5.2g. It is left out because 5.2c has no test that requires it, and the seam should grow when a test demands it rather than in anticipation. This is a known, named gap rather than an oversight.

---

## 7. Transaction boundary

### 7.1 The sequence, reviewed and not implemented

1. **Validate `APPROVED`.** Active instance only; refuse a technical draft before reading anything, the shape all four Phase 2 actions use. Also refuse if a non-terminal intent already exists for this order and revision, so `sendToSupplier` is not a way to mint a second delivery.

   **Phase 5.2b raised this step from a nicety to a hard requirement.** The unique index is physically present and enforces one intent per `(CLIENT, PURCHASE_ORDER_UUID, ORDER_REVISION)`, but a violation reached during managed RAP save **terminates in a short dump** rather than returning `FAILED`/`REPORTED` (see 4.5). So the database constraint cannot be used as control flow: `sendToSupplier` **must not** rely on catching a duplicate, and must instead **check first and reuse** the intent that already exists for that order and revision, so a retry replays the delivery identity it already holds. The constraint stays as the final safety net; the application's job is to make sure it is never reached. **Not implemented in 5.2b** — this is a requirement recorded for the `sendToSupplier` slice. A corrected commercial snapshot must eventually use a **higher `OrderRevision`**, and revision-increment behaviour does not exist yet.
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

### 7.4 Phase 5.2f — the locked contracts

Every technical unknown is closed (9.3). What follows is the decided contract, separating what the repository already mandated from what was decided on top of it.

**Eligibility and the initial request — mandated.** Active instance only, technical draft refused first, `Status = 'APPROVED'` required. On success the business `Status` is **not touched**, `IntegrationStatus` becomes `PENDING`, `DeliveryId` becomes the intent's managed UUID, and `DispatchState` is `PENDING`. No HTTP.

**Same-revision repeats reuse the intent. Always.** This corrects an earlier reading of 4.5 that conflated two different things. The invariant is *"a retry must reuse the **same** `deliveryId`, so a second intent at the same revision should never be minted"*, and 6.4 says the same for an unanswered attempt: *"replay the same `deliveryId`; never mint a new one."* A **higher `OrderRevision` is required only when the commercial snapshot changes** — that is what 4.5's "superseded" means. A transport failure changes nothing commercial, so demanding a new revision for it would mint a second delivery identity for an unchanged order, which is the exact failure the unique index exists to prevent.

| Existing intent at this revision | `sendToSupplier` does |
| --- | --- |
| `PENDING` | Idempotent no-op. Reuse the intent and its `DeliveryUUID`. Snapshot and hash untouched |
| `IN_FLIGHT` | Idempotent no-op. A coordinator holds the lease; do not interfere |
| `DELIVERED` | Idempotent no-op with an **informational** message. Reuse the intent, create nothing, and do **not** fail the action — an already-delivered request is not an error. The business transition to `SENT` stays 5.2g's |
| `FAILED` | Explicit retry. Reuse the same intent and `DeliveryUUID`, **preserve** snapshot and hash, set `DispatchState` back to `PENDING` |
| `UNKNOWN` | Identical to `FAILED` |

Two consequences worth stating rather than discovering later. **The action cannot tell why an intent failed**: 4.6 deliberately left `last_http_status` / `last_error_code` off the intent, so a 400 that will fail identically on replay is indistinguishable here from a 503 that will not. That is acceptable precisely because a retry is an **explicit operator request** rather than an automatic one — 6.4's *"no blind retry"* is about the coordinator, not about a human who has fixed a destination. And **lease fields are not reset** when `FAILED` returns to `PENDING`: no repository rule assigns lease handling to `sendToSupplier`, 7.3 already records reclaiming an expired lease as a designed coordinator path, so it stays 5.2g's. This is flagged, not silently decided.

**Approval evidence — `LastChangedBy` / `LastChangedAt`, read before the action's own update.** Checked against the handler rather than assumed: `submit` requires `DRAFT`, `approve` and `reject` require `SUBMITTED`, and `cancel` is the only action accepting `APPROVED` — and it leaves `APPROVED` immediately. Combined with the ADR-021 invariant that everything after `DRAFT` is commercially immutable, **the only operation that can have touched an `APPROVED` header is `approve` itself**, so those two fields are the approver and the approval moment. `sy-uname` and a fresh timestamp would record the *sender*, which is a different fact. The ordering constraint is real: read before the local-mode update, or the action overwrites its own evidence. These are written **only at intent creation**, never on a retry, because the intent is immutable for its revision.

**`PayloadSnapshot` — the source order delivery, exactly the fourteen members of API_CONTRACTS' DTO**, including `deliveryId`, which is why the create-then-update the LUW probe proved is used. `PayloadHash` is SHA-256 over the exact persisted string. The serializer that produces it, **`ZJP_CL_DLV_SNAPSHOT_JSON`** (object 16), is **SAP runtime-verified**. Three of its details are contract rather than style, because the hash is taken over the exact string, and the run confirmed all three: member order follows API_CONTRACTS' own listing, `revision` is a JSON **number**, and the item number is the unpadded **string** `"10"` — which is where the source shape visibly diverges from the CAP order's numeric `lineNumber`, the divergence the two-hop design exists to allow. The same run also settled three small syntax questions that had been flagged rather than assumed: `SHIFT … LEFT DELETING LEADING '0'` behaves as required, `ADD_NUMBER` accepts an `abap.int4` field directly without `CONV`, and the XCO builder and reparse work unchanged outside the mapper. The decimal scales are **2 / 3 / 4** for `totalAmount`, `quantity` and `netPrice`, and `unitOfMeasure` stayed `EA` with no `PCE` anywhere in the output. Both are immutable for a revision and are never rewritten on retry.

**`sourceSystem` is part of that snapshot**, so `sendToSupplier` needs a value at creation time — and the action is specified **parameterless**. Blocker **B4** therefore has to be settled before implementation, not after: the recommendation is a single named constant supplying it, with the builder keeping its verified `source_system` parameter so tests inject their own. Where that constant eventually lives — customizing, a communication setting — stays open without blocking.

---

## 8. Blockers and questions needing learner SAP evidence

| ID | Blocker | Why it blocks | Recommendation |
| --- | --- | --- | --- |
| **B1** | `OrderRevision` is `0` on every row; CAP requires `source.revision ≥ 1`. **RESOLVED in Phase 5.2a, SAP runtime-verified.** `submit` writes `OrderRevision = 1` in the same local-mode `UPDATE FIELDS` clause as `Status` and `PurchaseOrderNumber`. A `DRAFT` order keeps `0` and is deliberately undeliverable; a refused submit exits before the update, so failure never assigns `1`; and nothing later in the lifecycle changes it — approve, reject and cancel leave it alone, and a refused re-submit preserved `1` | Closed | The recommendation was followed exactly, including its own activation round and the `ZJP_CL_PO_EML_TEST` update required by repository policy. The rejected alternative stayed rejected: the revision is **not** defaulted in a builder or mapper. **No increment and no revision-2 behaviour exists** — 5.2a establishes only the initial frozen revision |
| **B2** | `IntegrationStatus` is blank, not `NOT_REQUESTED`. **RESOLVED for new orders in Phase 5.2a, SAP runtime-verified.** The existing `initializeStatus` determination writes `IntegrationStatus = 'NOT_REQUESTED'` alongside `Status = 'DRAFT'`, so blank is no longer a valid starting state for anything created from now on | Closed for new orders | The second of the two options was taken — an explicit initial value rather than treating blank as `NOT_REQUESTED` on read — because it lets a later state check compare a real value instead of special-casing blank. **Legacy pre-Phase-5 rows keep their blank value and are intentionally not mass-updated**; the determination is `on modify { create; }` and its `Status IS NOT INITIAL` guard was deliberately not widened, since guarding on the blank integration value would have reset those rows to `DRAFT`. `IntegrationStatus` does **not** advance beyond `NOT_REQUESTED` yet |
| **B3** | No CAP URL is reachable from SAP. **RESOLVED.** The closure condition this blocker set for itself — *"B3 closes only when an outbound call from S/4 actually reaches the deployed CAP endpoint"* — has been met by SAP runtime evidence. CAP is deployed to Cloud Foundry at `https://0badc38dtrial-dev-cap-supplier-portal-srv.cfapps.us10-003.hana.ondemand.com`, and the S/4 sandbox has called it over HTTPS through destinations `ZJP_CAP` and `ZJP_CAP_INGEST`, authenticating with an OAuth2 client-credentials token carrying `IntegrationClient`. Every leg the blocker named is now evidenced: DNS and network path, TLS trust after importing DigiCert TLS RSA4096 Root G5 into the ANONYM PSE, the destination declaration, the token, and the application itself — ABAP read `/health/ping` with **200**, posted `{}` and received the portal's own **400 `SCHEMA_VERSION_UNSUPPORTED`**, and posted a valid delivery for **201 / 200 replay / 409 conflict**. Probes **P1, P2/P3, P4 and P12 are answered**; P5–P11 remain open. | Closed by the outbound runtime probe | **Resolved by execution, not by argument.** The chosen path — `S/4 sandbox → HTTPS → CAP deployed to BTP Cloud Foundry`, per the decision in 1.3 — has been walked end to end. The deployment is recorded in `docs/environments.md`. What B3 never covered and what therefore remains open is the *business* outbound work: no RAP order is mapped, no `DeliveryIntent` exists and `sendToSupplier` is not implemented — see section 10 and the Phase 5.2 slice |
| **B4** | ~~`sourceSystem` has no decided value~~ — **RESOLVED FOR DEV / MULTI-ENVIRONMENT CONFIG DEFERRED.** `PIH_ABAP_DEV` is the DEV identity, declared once as a private constant in `lhc_PurchaseOrder`, so `sendToSupplier` has a single controlled producer and the builder keeps its verified `source_system` parameter for tests. It is deliberately **not** beside the builder's `schema_version`: that is a contract constant identical everywhere, while this one differs per environment. **A real configuration mechanism must replace it before any QAS or PRD rollout** — a transport of this source would otherwise carry the DEV identity and silently scope CAP's deduplication keys to the wrong system | Original recommendation: adopt `PIH_ABAP_DEV` as a configured constant and seed nothing else until a second system exists |
| **B5** | The released outbound HTTP API set is unknown | The transport implementation cannot be written | Probes P1–P4 |
| **B6** | The CAP ingestion endpoint has no authentication | Phase 5 is its first real caller, and a tunnel publishes it | Accept for the study and label it, or add a minimal credential; real authentication is Phase 8. Do **not** let a tunnel run unattended |
| **B7** | Whether a unique secondary index is available on this table artifact. **RESOLVED — it is a constraint, not reasoned code.** `ZJP_PO_DLV~REV` is a unique Table Index over `CLIENT`, `PURCHASE_ORDER_UUID`, `ORDER_REVISION`, active in DDIC and **physically present in the database** (confirmed and created through SE14 after an active-but-absent index let two rows persist), and runtime-proven to enforce the rule by an ST22 dump on a deliberate violation | Closed | The one-delivery-per-revision rule is enforced by the database, so the reasoned root-lock fallback in 4.5 is not needed and is not relied on. Two consequences carried forward: a DDIC-active index is not necessarily a database index, and a violation surfaces as `CX_SY_OPEN_SQL_DB` → `CX_CSP_ACT_INTERNAL` → `RAISE_SHORTDUMP` rather than `FAILED`/`REPORTED`, so uniqueness is verified manually and never provoked by the automated suite |

Open items carried forward untouched: **OI-05** (this subphase is its first real work, still open), **OI-13** RAP stale-ETag and concurrency, the RAP `__OperationControl` UX gap, the permissive RAP authorization stub, the OI-03 remainder (the separate integration projection), and all eight items of CAP debt from the Phase 4.6 closure. Nothing here closes any of them.

---

## 9. Required ADT / runtime probes

Each probe is small, and each answers a question this repository cannot. **Report the exact compiler or runtime text, including failures** — the Phase 3.2 `@UI.facet` result is in the repository because a negative compiler answer was recorded rather than worked around, and that is worth more here than a guess.

| ID | Probe | What to report |
| --- | --- | --- |
| **P1** | ~~Check availability and release state of the outbound HTTP candidates~~ — **ANSWERED by execution.** The working chain is `CL_OUTBOUND_PROVIDER_HTTP=>CREATE_BY_DESTINATION` → `IF_HTTP_DESTINATION` → `CL_WEB_HTTP_CLIENT_MANAGER=>CREATE_BY_HTTP_DESTINATION` → `IF_WEB_HTTP_CLIENT`. **The candidates this probe named were wrong**: it guessed `cl_http_destination_provider` with `create_by_url` / `create_by_comm_arrangement` / `create_by_cloud_destination`, and the real entry point is a different class taking a destination name. Recording that is the point of the probe discipline — the guess was plausible and it was not the answer | **Still to report:** the ABAP **language version** of the class that ran it (Standard ABAP or ABAP for Cloud Development), what ADT's Released APIs view says about `CL_OUTBOUND_PROVIDER_HTTP` for ABAP Cloud, and whether a request **timeout** can be set on `IF_WEB_HTTP_CLIENT` |
| **P2** | ~~Communication Scenario / Arrangement~~ — **ANSWERED, and not needed.** The outbound target is declared as an **HTTP destination** (`ZJP_CAP`, `ZJP_CAP_INGEST`) with an OAuth2 client profile `ZJP_CAP_OAUTH` and configuration `ZJP_CAP_XSUAA`, not as a communication arrangement | Settled. If the transport later has to run under ABAP Cloud, whether a *cloud* destination can front the same target becomes a new question |
| **P3** | ~~URL-based destination under ABAP Cloud~~ — **superseded by P2's answer.** A destination-based target works on this system | Settled for the current language version |
| **P4** | ~~Where an outbound server certificate goes~~ — **ANSWERED.** The outbound call uses SSL client PSE **ANONYM**. The first handshake failed with **`SSSLERR_PEER_CERT_UNTRUSTED`**; importing **DigiCert TLS RSA4096 Root G5** into that PSE's trust list resolved it, and the learner had the permission to do so | Settled. **Do not generalize this certificate to other environments** — it is the anchor this Cloud Foundry route's chain happened to need, and a different endpoint or a rotated chain needs its own answer |
| **P5** | ~~`sysuuid_x16` → canonical 36-character hyphenated text~~ — **ANSWERED / SAP runtime-verified.** Both `CL_SYSTEM_UUID` and `XCO_CP_UUID` exist and are released on this target; the **smaller** one was chosen, because two released options is not a reason to take the larger | **`CL_SYSTEM_UUID=>CONVERT_UUID_X16_STATIC`**, `sysuuid_x16` → `sysuuid_c36`. Input `00000000000000000000000000000001` produced `00000000-0000-0000-0000-000000000001` — lowercase, hyphenated, 36 characters, exactly the contract's form |
| **P6** | ~~Decimal → contract string~~ — **ANSWERED / SAP runtime-verified.** The candidate was right: `\|{ value NUMBER = RAW DECIMALS = n }\|` compiles and is fixed-scale and locale-independent | Produced `1500.00`, `2.000` and `750.0000` — a `.` separator, no grouping, scale **preserved rather than trimmed**. The four scales the contract needs: **2** for `amount.value` and `lineAmount`, **3** for `orderedQuantity.value`, **4** for `unitPrice.value`. The values travel as JSON **strings**, not numbers, which is why the snapshot keeps them numeric and the mapper formats them |
| **P7** | `timestampl` → UTC RFC 3339 `2026-09-12T15:00:00Z`. Candidates: `cl_abap_tstmp`, `xco_cp_time`, `xco_cp=>sy->moment( )` | Which is released and one formatted sample |
| **P8** | ~~Can a `DEFINE TABLE` artifact carry a **unique secondary index**?~~ — **ANSWERED by ADT evidence on this target.** Yes, and **not** through `DEFINE TABLE` syntax: it is a separate **Table Index** repository object. `New → Other ABAP Repository Object → "index"` offers **Extension Index** and **Table Index**; the Table Index editor exposes **Unique Index**, *Index on Table Buffer only* and *Fuzzy Search Index* | A unique index over `PURCHASE_ORDER_UUID` + `ORDER_REVISION` was **rejected** with `client field required for unique index`. Adding **`CLIENT` explicitly as the first field** made it save and activate. So: Table Index objects are supported, `UNIQUE` is supported, **`CLIENT` must be listed explicitly** on a client-dependent table, and the intended business columns are valid index fields. **Two further facts came from using it rather than declaring it**, and both are in section 4.5: activating the DDIC object did **not** create the database index — SE14 was needed, and until then a duplicate persisted — and a violation of the physical index during a managed RAP save produces `RAISE_SHORTDUMP`, not `FAILED`/`REPORTED` |
| **P9** | ~~Is `abap.string` allowed as a non-key column, and with what restrictions?~~ — **ANSWERED by activation.** Probe table `ZJP_TMP_P9_STR` activated with `payload_snapshot : abap.string`, then activated again after a second `payload_snapshot_2 : abap.string` was added | `abap.string` is supported as a non-key persistence column; **more than one is allowed**; and it **does not have to be the final column**. The `abap.char` fallback is therefore **not** used — `ZJP_PO_DLV` keeps `payload_snapshot : abap.string` as designed |
| **P10** | ~~JSON serialization~~ — **ANSWERED / SAP runtime-verified.** `XCO_CP_JSON` exists and is released. The verified path is `XCO_CP_JSON=>DATA->BUILDER( )` → `IF_XCO_CP_JSON_DATA_BUILDER` → `GET_DATA( )` → `IF_XCO_CP_JSON_DATA->TO_STRING( )`, supporting `BEGIN_OBJECT`/`END_OBJECT`, `BEGIN_ARRAY`/`END_ARRAY`, `ADD_MEMBER`, `ADD_STRING`, `ADD_NUMBER`, `ADD_BOOLEAN`, `ADD_NULL` | A runtime probe produced the exact CAP contract shape, and the result reparsed through `XCO_CP_JSON=>DATA->FROM_STRING( )`. **Design decision: member names are passed explicitly to `ADD_MEMBER`**, never left to automatic underscore-to-camelCase transformation. The external wire contract is then visible in the source and cannot drift when an ABAP field is renamed — and the contract's names are case-sensitive, so an implicit rule is a silent failure waiting for the first field that does not round-trip |
| **P11** | ~~Read the current integration-field values from `zjp_po_h`~~ — **ANSWERED by Phase 5.2a runtime evidence.** Its purpose was to confirm the `OrderRevision` / `IntegrationStatus` state from actually persisted data rather than from source-code inspection alone, and the `ZJP_CL_PO_EML_TEST` lifecycle summary reads persisted `ZJP_PO_H` rows and prints exactly those columns | Observed on real rows: `OrderRevision = 0` before submit and `1` after a successful submit, and `IntegrationStatus = NOT_REQUESTED` for rows created under 5.2a. Rows persisted earlier keep their previous values and print a blank integration status — **they were not migrated, and no back-fill was performed**; the pre-existing behaviour is intentionally untouched |
| **P12** | ~~Can the SAP system reach **any** external HTTPS endpoint?~~ — **ANSWERED.** It reached this one: `/health/ping` returned 200 with `status UP`, `component cap-supplier-portal` | Settled |
| **P13** | ~~SHA-256 / payload hash API~~ — **ANSWERED / SAP runtime-verified.** The released API is **`CL_ABAP_MESSAGE_DIGEST=>CALCULATE_HASH_FOR_CHAR`** with `IF_ALGORITHM = 'SHA256'` and `IF_DATA` taking a `STRING`, returning the hex digest in `EF_HASHSTRING`. A throwaway probe `ZJP_CL_HASH_PROBE`, compiled under **ABAP for Cloud Development** — the project's own language version, which is the half of the question a syntax check would have missed — hashed `'abc'` to `BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD`, length **64**. That is the published SHA-256 test vector for `abc` reproduced exactly, so the algorithm, the character-to-UTF-8 path and the representation are all confirmed at once rather than assumed. The representation is **uppercase hexadecimal** on this system and needs **no Base64 conversion**, so it drops straight into `ZJP_PO_DLV-PayloadHash CHAR(64)`. **The hash is stored exactly as returned — no case normalisation**, because a deterministic API's own output is the stable value and re-casing it would add a transformation nothing verified. **Contract for Phase 5.2f:** input is the exact persisted `PayloadSnapshot` string, algorithm SHA-256, output the 64-character hex string the API returns, stored in `ZJP_PO_DLV-PayloadHash`. Original text follows | Answered. The original question is kept below because its reasoning still applies to the next unverified API |
| **P13 (original)** | **SHA-256 / payload hash API.** Identify a **released** API on this target, under the project's ABAP language version, that computes SHA-256 over a string. Section 4.2 specifies `payload_hash` as sha256 hex in `abap.char(64)`, and section 6.4's replay semantics depend on that hash being stable and correct, but **the original probe list had no entry for it at all** — the gap was found while reviewing what Phase 5.2b needs. Use ADT's Released APIs view / F2 element info, not a syntax check alone | The exact released API name and method signature ADT shows, whether it is released for the project's language version, and one sample output for a known input so the **representation** can be checked: 64 characters, hexadecimal, and lowercase or uppercase. The design expects canonical 64-character hex text, so a Base64 or byte-string result needs a documented conversion. **Candidates only, to be checked rather than trusted** — no production code will be written from memory, and P1 is the standing reason why. **This probe does not block Phase 5.2b table creation**; it must be answered before any code that computes `payload_hash` is written, which is Phase 5.2f |
| **P14** | ~~Released UUID *generation* API~~ — **ANSWERED / SAP-VERIFIED.** The API is **`CL_SYSTEM_UUID=>CREATE_UUID_X16_STATIC( )`**, which returns `SYSUUID_X16` **directly** — exactly the type `ZJP_PO_DLV-lease_owner` and `-last_correlation_id` store, so **no conversion is needed at all**. `XCO_CP_UUID` is **not** used: ADT rejected `XCO_CP_UUID=>CREATE( )` with *“Method “CREATE” is unknown or PROTECTED or PRIVATE.”*, and P5 had already chosen `CL_SYSTEM_UUID` over XCO on the grounds that two released options is not a reason to take the larger. **Phase 5.2g uses it for two consumers and no others:** one `LeaseOwner` per coordinator execution, minted once in the constructor, and a fresh correlation UUID per HTTP attempt. Original text follows | — probe class `ZJP_CL_UUID_PROBE`, disposable, ABAP for Cloud Development. **The first ADT syntax check rejected one of the two candidates and accepted the other.** `XCO_CP_UUID=>CREATE( )` was rejected with *“Method “CREATE” is unknown or PROTECTED or PRIVATE.”*, so that class publishes no static `CREATE` on this target. **`CL_SYSTEM_UUID=>CREATE_UUID_X16_STATIC( )` raised no error**, which is a compile-level indication that the method exists and is callable under ABAP for Cloud Development — but it is **not** an answer yet, because nothing has run and no value has been seen. The XCO candidate was removed rather than replaced with a second guess: candidate A already returns `sysuuid_x16`, exactly the type both consumers store, and P5 had already chosen `CL_SYSTEM_UUID` over XCO on the grounds that two released options is not a reason to take the larger. **Released UUID *generation* API.** P5 answered UUID **conversion** — `sysuuid_x16` → canonical text — and that is not the same question. **No ABAP code in this project has ever created a UUID**: Phase 5.2b chose `numbering : managed` for `DeliveryUUID` specifically to avoid needing one, so the gap was postponed rather than closed. It comes due now, because `X-Correlation-ID` is *"a fresh UUID per attempt"* and `ZJP_PO_DLV-last_correlation_id` exists to store it. Candidates to check rather than trust: `CL_SYSTEM_UUID` (which P5 already proved is released, so its creation methods are the first place to look) and `XCO_CP_UUID` | The exact released method that **creates** a UUID, its return type, and whether it is released for the project's ABAP language version. **This blocks correlation-ID generation by any component** — coordinator or transport — and it also constrains Phase 5.2e's test harness, which must therefore use **supplied** fixed identities rather than generated ones. **Widened by the Phase 5.2g blocker analysis:** it blocks **`LeaseOwner`** as well, which is `sysuuid_x16` and is documented in 4.2 as *“a per-run coordinator UUID rather than a user name”*. Every earlier reference to P14 in this repository says only “correlation ID”, and none noticed that claiming an intent has the identical dependency — so P14 gates the **first write the coordinator makes**, not a late diagnostic detail |
| **P15** | ~~Exact signatures of the proven HTTP chain, and URI-path override semantics~~ — **ANSWERED / SAP runtime-verified.** A new base destination **`ZJP_CAP_BASE`** was created with the proven host, port, TLS and OAuth configuration and **no application path prefix**. A throwaway console probe ran `CREATE_BY_DESTINATION` → `CREATE_BY_HTTP_DESTINATION` → `GET_HTTP_REQUEST` → `SET_URI_PATH( '/health/ping' )` → `EXECUTE` GET → `GET_STATUS` / `GET_TEXT` and returned **HTTP 200 `OK`** with the portal's health body. So **a request URI path applied to a path-less base destination reaches the intended route**, which is what the seam needed. The full signature set is recorded in 9.2. It also closes P1's outstanding **timeout** question: `EXECUTE` takes `I_TIMEOUT TYPE I DEFAULT 0`. **Still outstanding from P1**: the ABAP language version of the classes that run this chain | Settled for the signatures and the path semantics. Original text below |
| **P15 (original)** | **Exact signatures of the proven HTTP chain, and URI-path override semantics.** P1 answered *which* classes work; it did not record a single method signature beyond the two static entry points, and **the probe's source is not in this repository**. Needed before any production transport is written: how to obtain the request object from `IF_WEB_HTTP_CLIENT`, how to set an arbitrary header, how to set a text body, how to execute a POST, how to read status and response body, whether the client must be closed, and which exceptions each stage raises. **Plus the decisive one for the seam:** does setting a URI path on the request **replace** the destination's configured path or **append** to it? | The ADT F2 / Released APIs method list for `IF_WEB_HTTP_CLIENT` and for whatever request and response interfaces its accessors return, with exception classes; and the **P1 follow-up that is still outstanding** — the ABAP **language version** of the class that ran the original probe, what the Released APIs view says about `CL_OUTBOUND_PROVIDER_HTTP` for ABAP Cloud, and whether a request **timeout** can be set. The path question is answerable safely against `ZJP_CAP` and `/health/ping` with a GET, with no ingestion data involved |
| **P16** | ~~Timestamp arithmetic~~ — **ANSWERED / SAP-VERIFIED.** The path is **`CL_ABAP_TSTMP=>ADD`** on a short `TIMESTAMP`, whose result **assigns directly to `ZJP_PO_DLV-LeaseExpiresAt`**. The fractional-second precision loss is **explicitly accepted** for lease semantics — a lease is a coarse deadline, not an audit timestamp. The `utclong` route is closed and stays closed: ADT rejected `GET TIME STAMP FIELD` into a `utclong` target with *“The type of “NOW_UTC” must be compatible with the type(s) of “TIMESTAMP, TIMESTAMPL”.”*, so on this target that statement produces the packed timestamp types only. **`lease_seconds` remains an explicit coordinator input**; Phase 5.2g introduces no production lease default and no configuration object. Original text follows | — Answered by the throwaway probe `ZJP_CL_TSTMP_ADD_PROBE`, **deleted once the answer was recorded**. **The first ADT syntax check settled the `utclong` route negatively and left the `CL_ABAP_TSTMP` route standing.** `DATA now_utc TYPE utclong` followed by `GET TIME STAMP FIELD now_utc` was rejected with *“The type of “NOW_UTC” must be compatible with the type(s) of “TIMESTAMP, TIMESTAMPL”.”* — so on this target **`GET TIME STAMP FIELD` accepts the short and long packed timestamps only and cannot produce a `utclong` at all**, which means the whole `utclong_add( )` route needs a different source for “now” before it can even be attempted. That candidate was removed rather than replaced with a second guess. **`CL_ABAP_TSTMP=>ADD( tstmp = ... secs = ... )` raised no error**, so both the method and those two parameter names appear valid — again a compile-level indication only, with the arithmetic itself and the precision question still unproven. **Timestamp arithmetic**, newly identified by the Phase 5.2g blocker analysis. Phase 5.2g must compute `lease_expires_at = now + lease_seconds`, and the target column `ZJP_PO_DLV-lease_expires_at` is `abp_lastchange_tstmpl`, a **long** timestamp. **This is not P7**, which asks how to *format* a timestamp for the wire; this asks how to do *arithmetic* on one, and the two have different answers. `GET TIME STAMP FIELD` is settled and already runs inside `ZJP_CL_PO_EML_TEST`, so obtaining “now” is not the question; adding a duration to a long timestamp has **no precedent anywhere in this repository**. A long timestamp is packed as `YYYYMMDDhhmmss.fffffff`, so ordinary addition would advance the seconds field past 59 rather than the clock, which is why a candidate that merely compiles proves nothing. Candidates to check rather than trust: `CL_ABAP_TSTMP`, the built-in `utclong_add( )`, and `XCO_CP_TIME` | The exact API, its input and output types, its release state for ABAP for Cloud Development, a sample “now”, the injected seconds, the resulting expiry, **whether the result assigns directly to `ZJP_PO_DLV-lease_expires_at`**, and any precision loss or conversion involved. The probe injects an explicit test value and establishes **no** production timeout — the lease duration is an explicit coordinator input by architectural decision |
| **P17** | ~~JSON *reading*~~ — **RESOLVED BY THE PERMANENT READER AND SAP RUNTIME-VERIFIED.** The SAP method list settled the shape: `IF_XCO_CP_JSON_DATA` exposes **`APPLY`, `TO_STRING`, `TRAVERSE` and `WRITE_TO`** and **no `GET_MEMBER`-style accessors at all**, which is why three successive member-walk guesses were rejected. The reader is therefore a **`WRITE_TO` binding into an intermediate structure that mirrors the source contract, followed by an explicit mapping onto `TY_DELIVERY`** — one mechanical step plus one readable step, rather than one clever one. `TRAVERSE` was not needed. **`ZJP_CL_DLV_SNAPSHOT_READER` now carries this permanently** and the probe is disposable. **One unresolved signature remains, isolated to a single method:** the `C36` to `X16` conversion. ADT confirmed the METHOD `CL_SYSTEM_UUID=>CONVERT_UUID_C36_STATIC` exists — the rejection was *“The formal parameter “UUID_C36” does not exist”*, a parameter complaint rather than a method complaint — but its parameter names are not yet known, because P5 proved only the opposite direction. **Both unknowns are now closed by SAP evidence.** The chain order was wrong in the first draft and the compiler settled it: **`WRITE_TO` has no `RETURNING` parameter on this target and is TERMINAL**, so it cannot appear in an expression chain at all. The verified order is **`FROM_STRING` -> `APPLY` -> `WRITE_TO`**. And the conversion signature is **`EXPORTING uuid = <C36>` / `IMPORTING uuid_x16 = <X16>`** — `uuid` is the *input* in both directions and the output is named after the target representation, so the symmetry the earlier guess assumed does not exist. **The runtime proof:** the persisted snapshot round-tripped through the reader and back out of `ZJP_CL_DLV_SNAPSHOT_JSON` **byte-identically**, and the reconstructed DTO was accepted by `ZJP_CL_CAP_ORDER_MAPPER` unchanged. `TRAVERSE` was never needed. Original text follows | — Explored by the throwaway probe `ZJP_CL_JSON_READER_PROBE`, **deleted once the permanent reader superseded it**. **The first ADT syntax check rejected the published table type**: `if_xco_cp_json_data=>tt_data` failed with *“Type “TT_DATA” is unknown.”*, so the interface publishes no table type under that name. Rather than guess a second name, the probe now declares **its own** `STANDARD TABLE OF REF TO if_xco_cp_json_data`, an element type already proven real because the verified `FROM_STRING( )` returns it — so a compatible `GET_CHILDREN( )` assigns cleanly and an incompatible one names the actual return type in the error, which answers the question either way. **A second syntax check then rejected the accessors as well**, three times over: *“Method “GET_MEMBER” is unknown or PROTECTED or PRIVATE.”* — so the member accessor is not called `GET_MEMBER`, and **no fourth name was invented**. The same pass produced a more informative rejection on the UUID conversion: *“The formal parameter “UUID_C36” does not exist. However, the following parameters have similar names: “UUID_C26” and “UUID_C32”.”* That is a **parameter** complaint rather than a method complaint, so **`CL_SYSTEM_UUID=>CONVERT_UUID_C36_STATIC` exists and is callable** and only its signature is unknown — P5 had proven only the opposite direction, where `UUID_C36` is the *importing* parameter of `CONVERT_UUID_X16_STATIC`. **After three rounds of name-guessing the probe changed shape rather than guessing a fourth time:** it now uses RTTI to print the real method and parameter lists for `IF_XCO_CP_JSON_DATA` and for `CL_SYSTEM_UUID`, so one run answers both open questions from the system itself. The reconstruction is **parked behind an `api_known` flag** rather than deleted, so adopting the real names is four one-line helpers and a flag. **JSON *reading***, newly identified by the Phase 5.2g blocker analysis and the one gap that was not anticipated. The coordinator must dispatch the **persisted** snapshot and must not rebuild it, but `ZJP_PO_DLV-PayloadSnapshot` is a **string** while `ZJP_CL_CAP_ORDER_MAPPER=>map` takes the **typed** `ty_delivery`, and nothing in this project converts the one into the other — Phase 5.2f only ever needed the one-way trip. **P10 does not cover it**: it verified `TO_STRING( )` and `FROM_STRING( )` round-tripping, never *traversing* a parsed document to pull members out of it, and reading is a different API surface from writing. The alternatives were rejected on architecture rather than convenience: posting the source shape sends CAP the wrong contract, and persisting the mapped body instead is exactly what ADR-032’s second decision forbids, because Phase 6 deletes the mapping hop and keeps the source one. Candidates: the `IF_XCO_CP_JSON_DATA` member, value and array accessors, and **`CL_SYSTEM_UUID=>CONVERT_UUID_C36_STATIC`**, since P5 proved only the `x16` to `C36` direction and the inverse is its own unverified call | The exact interfaces and methods, their release state, and the conversions needed for UUID, `revision`, `totalAmount`, `quantity`, `netPrice` and the item number — the character-to-packed direction especially, because P6 established that *writing* a decimal needs an explicit locale-independent format and the reverse has never been tested here at all. Proven by a **round trip** rather than by inspection: rebuild the DTO from the golden Phase 5.2f snapshot, re-serialize it with the verified `ZJP_CL_DLV_SNAPSHOT_JSON`, compare byte-for-byte, then hand it to the real mapper. **If it does not compile, the method list ADT shows for `IF_XCO_CP_JSON_DATA` answers P17 on its own** |

**Answered: P1, P2/P3, P4 and P12** by the outbound runtime probe, **P11** by the Phase 5.2a runtime evidence, **P8 and P9** by the Phase 5.2b activation, and **P5, P6 and P10** by the Phase 5.2d probes. **Open: P7 only.** **P14, P16 and P17 are all closed.** P14 and P16 are ANSWERED and SAP-verified; **P17 is RESOLVED** by the permanent `ZJP_CL_DLV_SNAPSHOT_READER`, whose round trip and mapper hand-off are SAP runtime-verified. P16 and P17 were newly identified by the Phase 5.2g blocker analysis, the same way P13 was added for 5.2b and P14 and P15 for 5.2e: the original list had no entry for either, and both were closed within one slice of being raised. **Nothing in Phase 5.2g is left awaiting ADT.** **P7 remains open and still blocks nothing**: it is a wire-format question and no outbound body in this design carries a timestamp. **P13 is ANSWERED** by the `ZJP_CL_HASH_PROBE` run, which removes the last probe standing between the design and Phase 5.2f's payload hash. **P14 does not block 5.2e or 5.2f**: neither generates an identity — `DeliveryUUID` comes from managed numbering, and `last_correlation_id` and `lease_owner` stay initial under ADR-015 until the 5.2g coordinator claims an intent. **P7 does not block 5.2f either**: it is a wire-format question and the outbound body carries no timestamp. P14 and P15 were added while reviewing what Phase 5.2e needs, the same way P13 was added for 5.2b — the original list had no entry for either. Neither blocks Phase 5.2d: the outbound `Orders` body carries no timestamp, and nothing computes `payload_hash` until 5.2f. The transport seam is no longer the blocker and neither is persistence — every remaining unknown is about *building* the payload rather than sending or storing it.

**Nothing open gated Phase 5.2c**, the transport abstraction, and it is now built and runtime-verified: `ZJP_IF_OUTBOUND_TRANSPORT` uses only `abap_bool` and built-in types by design, which the compiler confirmed, and `ZJP_CL_TRANSPORT_FAKE` touches no network, which the run confirmed by needing none. **The open probes now block Phase 5.2d, which is therefore PROBE REQUIRED and not started.** Narrowed on inspection: **P5, P6 and P10** — canonical UUID text, decimal formatting under a comma-decimal user, and JSON with exact camelCase — are the builder's and the mapper's and must be answered before either is written. **P7 does not block 5.2d**: the outbound order body carries no timestamp field at all, which the CAP `Orders` contract confirms, so RFC 3339 formatting belongs to the inbound leg and to diagnostics. See 9.1 for the smallest next step. The remaining probes attach to specific later slices and should be answered just before them, not forgotten and not front-loaded: **P5, P6, P7 and P10** — canonical UUID text, decimal formatting under a comma-decimal user, UTC timestamps, and JSON with exact camelCase — belong to the builder and mapper in 5.2d, and **P13**, the released SHA-256 API, is needed when `payload_hash` is first computed in 5.2f. P13 is why the 5.2b probe row carries 64 zeros rather than a hash. **No ABAP HTTP call was authored from memory in this project, and none will be** — the chain above is recorded because it executed, not because it looked right.

### 9.1 The Phase 5.2d probes, answered

**P5, P6 and P10 were the three unknowns that blocked the builder and the mapper, and all three are now SAP runtime-verified** — see their rows above. The pattern held once more: the repository contained no precedent for any of them, candidates were named rather than trusted, and the answers came from execution.

| Need | Verified API | Used by |
| --- | --- | --- |
| `sysuuid_x16` → canonical C36 text | `CL_SYSTEM_UUID=>CONVERT_UUID_X16_STATIC` | Mapper, for `deliveryId`, `source.orderId`, `lines[].sourceItemId` |
| Fixed-scale locale-independent decimal | `\|{ value NUMBER = RAW DECIMALS = n }\|` | Mapper, scales 2 / 3 / 4 |
| JSON with exact camelCase and nesting | `XCO_CP_JSON=>DATA->BUILDER( )` … `GET_DATA( )->TO_STRING( )` | Mapper, whole body |

**Two of these answers shaped the design rather than merely enabling it.** Because the decimals travel as JSON **strings** at a scale the contract fixes, the canonical snapshot keeps them **numeric** and the mapper formats them — putting scale on the wire side of the seam, where it belongs, instead of freezing a representation into a snapshot meant to outlive the endpoint. And because `ADD_MEMBER` takes the member name explicitly, the wire contract is written out in the mapper's source instead of being produced by an implicit underscore-to-camelCase rule; the contract's names are case-sensitive, so an implicit rule is a silent failure waiting for the first field that does not round-trip.

All three answers are now carried by production code that has run: the mapper converted `37FC…`-style raw UUIDs to canonical C36 text, emitted `1500.00` / `2.000` / `750.0000` at the contract's three scales, and built the whole body through the XCO builder with explicit member names.

### 9.2 Phase 5.2e — the HTTP chain, and where the path lives

**P15 is answered and Phase 5.2e is SAP runtime-verified.** `ZJP_CL_OUTBOUND_TRANSPORT` and its harness `ZJP_CL_HTTP_TRANSPORT_TEST` activated and ran to `PASS: Phase 5.2e real HTTP transport verified.` SAP now performs a real OAuth-protected POST to the deployed portal through the same seam the fake implements — **201**, an idempotent **200** returning the identical receipt, a **409 `DELIVERY_PAYLOAD_CONFLICT`** with the receiver body intact, and an unresolvable destination classified as a technical failure.

**Why a probe was needed at all.** P1 recorded which classes work; it recorded **not one method signature**, and the original probe's source is **not in this repository**. Writing the adapter from that would have meant authoring released-API calls from memory — which P1 itself is the standing argument against, having named three plausible candidate methods on the wrong class entirely.

**Path ownership, settled by evidence rather than preference.** `ZJP_CAP_INGEST` carries the application path `/rest/integration/v1/Orders`, and the verified mapper emits the same string, so using that destination would have made `ty_request-path` decorative and hidden the real route in SM59 where no test can see it. A new base destination **`ZJP_CAP_BASE`** — proven host, port, TLS and OAuth, **no path prefix** — plus `SET_URI_PATH` reached `/health/ping` and returned **HTTP 200**. The division is therefore:

| Owns | What |
| --- | --- |
| SM59 destination `ZJP_CAP_BASE` | Host, port, TLS trust, OAuth2 / XSUAA |
| `ZJP_IF_OUTBOUND_TRANSPORT=>TY_REQUEST-PATH` | The application route |

That is exactly what section 6.2's *"path only; the base URL and its credentials belong to the destination configuration"* always intended, and it means a CAP route change is a one-line change in the mapper rather than an SM59 edit. **`ZJP_CAP` and `ZJP_CAP_INGEST` are not used by the production adapter**; they remain as the manual probe's evidence and are not deleted.

**The verified signature set**, recorded here so the next reader does not have to re-probe:

| Step | Call |
| --- | --- |
| Destination | `CL_OUTBOUND_PROVIDER_HTTP=>CREATE_BY_DESTINATION( i_name TYPE rfcdest )` → `IF_HTTP_DESTINATION`, raising `CX_OUTBOUND_PROVIDER_HTTP` |
| Client | `CL_WEB_HTTP_CLIENT_MANAGER=>CREATE_BY_HTTP_DESTINATION( i_destination )` → `IF_WEB_HTTP_CLIENT`, raising `CX_WEB_HTTP_CLIENT_ERROR` |
| Request | `client->GET_HTTP_REQUEST( )` → `IF_WEB_HTTP_REQUEST` |
| Route | `SET_URI_PATH( i_uri_path TYPE string )`, raising `CX_WEB_MESSAGE_ERROR` |
| Headers | `SET_HEADER_FIELD( i_name, i_value )`, raising `CX_WEB_MESSAGE_ERROR` |
| Body | `SET_TEXT( i_text TYPE string )`, raising `CX_WEB_MESSAGE_ERROR` |
| Send | `client->EXECUTE( i_method = IF_WEB_HTTP_CLIENT=>POST, i_timeout TYPE i DEFAULT 0 )` → `IF_WEB_HTTP_RESPONSE`, raising `CX_WEB_HTTP_CLIENT_ERROR` |
| Status | `GET_STATUS( )` → `HTTP_STATUS` with `CODE TYPE i`, `REASON TYPE string` |
| Body | `GET_TEXT( )` → `string` |
| Cleanup | `client->CLOSE( )`, raising `CX_WEB_HTTP_CLIENT_ERROR` |

`SET_HEADER_FIELDS` exists too and is deliberately not used: the seam already carries its own header table, and iterating it with `SET_HEADER_FIELD` keeps the adapter ignorant of which headers exist.

**Three implementation decisions worth defending.**

**Timeout stays at the API default.** The repository has chosen no timeout policy, and a timeout is a business decision about how long a delivery may hang — not something a transport adapter should invent. Recorded rather than implemented.

**Cleanup never changes the outcome.** `CLOSE( )` runs outside the classification, and a failure to close is swallowed. Once the receiver has answered, that answer is a fact; turning it into *unanswered* because a socket could not be closed would invent a non-delivery the system has evidence against, and a replay of a delivery CAP already committed is precisely the failure mode the outbox exists to prevent.

**One narrow case is conceded on purpose.** `CX_WEB_MESSAGE_ERROR` raised while *reading* a reply is classified as unanswered, even though a reply existed. Section 6.3 makes this classification deliberately conservative — over-classifying as `UNKNOWN` costs one replay, which Phase 4.3 verified is safe, while under-classifying risks a duplicate order — and reporting a status the adapter never actually observed would be worse than reporting that it does not know.

**Correlation ID: unchanged from discovery, and the seam stays untouched.** The transport generates nothing. The 5.2g coordinator creates the correlation UUID, persists it to `ZJP_PO_DLV-last_correlation_id` and passes `X-Correlation-ID` as an ordinary header, which the adapter forwards without knowing what it is — **all of which is now built and SAP runtime-verified**, with the seam unchanged exactly as this paragraph predicted. **P14 is ANSWERED**: `CL_SYSTEM_UUID=>CREATE_UUID_X16_STATIC( )`, which never blocked 5.2e and gated only the coordinator.

**The runtime evidence, and one operational lesson that cost real time.** Every claim above is from an executed run. CREATED returned `answered = X`, `201` and the receipt `{"deliveryId":"7c4e1b90-…","sourceOrderId":"5a2f8d31-…","portalOrderId":"5c07ecdc-7210-4a87-9e54-dc183730794b","status":"RECEIVED","receivedAt":"2026-09-18T14:53:01.940Z"}`. REPLAYED returned `200` with **the same `portalOrderId` and the same `receivedAt`** — the stored original receipt, which is what makes a replay safe. CONFLICT returned `409` carrying `DELIVERY_PAYLOAD_CONFLICT` and a receiver message confirming the stored order was unchanged; it arrived as `answered = X`, which is the assertion that matters, because a 409 is a protocol answer and not a transport failure. The unresolvable destination `ZJP_NO_SUCH_DEST` returned `answered = false`, status `0`, an initial body and safe diagnostic text.

> **A health endpoint can be green while the database is not.** Before this run, the same unchanged ABAP returned **HTTP 500** twice, and the CAP log said only `Pool resource could not be acquired within 1s` at `HANAService.begin`. That pointed at connection pooling, and a pool timeout was the reasonable first hypothesis — `@cap-js/hana` does override `acquireTimeoutMillis` to **1000 ms in production**, against a 10000 ms base, so the symptom fitted. It was the wrong cause. Deeper Cloud Foundry logs eventually exposed `HANA Database instance is stopped`, SQL code **1890**, SQL state **HY000**, and HANA Cloud Central confirmed `pih-hana` was **Stopped**. Starting that same database and waiting for `RUNNING` made the **unchanged** test pass.
>
> Three things made this slow to see, and all three are worth remembering. The service instance and its broker reported healthy — `create succeeded`, *"HanaService is ready. All pods are running"* — which describes the **service**, not the **database runtime** underneath it. The HDI binding was intact and the application was `1/1 running`. And `/health/ping` returned **200** throughout, because it touches no database; a liveness probe that never opens a connection cannot report that connections are impossible. The pool-timeout message was a true statement about a symptom and a misleading guide to the cause: acquiring a connection to a stopped database will always time out, whatever the timeout is.
>
> **Nothing was changed to fix it.** Not the transport, not the CAP payload, not the HDI binding, not the HANA service. The `acquireTimeoutMillis` override written during diagnosis was **reverted** once the real cause was known, because a diagnostic experiment that did not turn out to be the fix has no business surviving as production configuration.

**P7 and P14 stay open and neither blocks this slice**; the outbound body has no timestamp field, and P14 is why the harness used a fixed delivery identity. **P13 has since been answered** — see its row.

### 9.3 Phase 5.2f — the DeliveryIntent LUW probe, and what it deliberately did not prove

**A throwaway probe `ZJP_CL_LUW_PROBE` settled the first of Phase 5.2f's technical unknowns.** It carries no P number because it asks about this project's own RAP objects rather than a released SAP API, but it was run and recorded the same way and the object was deleted afterwards.

**What it proved.** A `DeliveryIntent` was created through EML with **no key supplied**; managed numbering produced `37FC3FA8EB2D1FE1ACF01F9DF3F9FC13`, readable from **`MAPPED` before any commit**, with `FAILED` empty. That generated key was converted to canonical C36 text through the P5 API, embedded in a snapshot, hashed with the P13 API, and used to **`UPDATE` the same newly-created instance with no commit in between** — `FAILED` empty again. A **single** `COMMIT ENTITIES` accepted both operations, `sy-subrc = 0`, and exactly **one** row persisted carrying the generated key, the post-update `PayloadSnapshot` and its hash `61514BAE…`, with `DispatchState = PENDING`. The probe then deleted its own row through EML and verified zero residue.

Four things are now evidence rather than assumption: **managed numbering is sufficient** and need not be reconsidered; the key is **available early enough** to build a payload containing it; **create-then-update of the same instance in one LUW is viable**, which turns the `deliveryId`-in-snapshot question from a feasibility problem into a contract decision; and SHA-256 can be computed once the key is known. No `PurchaseOrder` row was involved and no HTTP occurred.

**What it did not prove, and the distinction was the whole point.** Nothing in that probe ran inside a **behavior handler** — it is a console class issuing EML from outside RAP. It therefore said nothing about whether `ZBP_I_PURCHASEORDER`'s action handler may execute EML against the `DeliveryIntent` business object in the same LUW, which is exactly what section 7.1 step 2 requires when it says the intent is *"created through EML inside the action's own LUW"* and *"the framework commits both or neither"*. Every EML statement in that handler was `IN LOCAL MODE` on its own business object, with **no cross-BO precedent anywhere in this project** — load-bearing, because if it did not hold, the transaction boundary that makes `sendToSupplier` an outbox rather than an HTTP call would have needed redesigning.

**That second question is now ANSWERED and SAP runtime-verified.** A temporary action `probeIntentLink` was added to `ZJP_I_PURCHASEORDER`, implemented in `ZBP_I_PURCHASEORDER` and driven from `ZJP_CL_PO_EML_TEST`, then **removed again** once the evidence was captured; none of it remains in the repository. From inside the handler, a `DeliveryIntent` was created through cross-BO EML with `FAILED` empty, its managed key `37FC3FA8EB2D1FE1ACF1259C6598FEB6` came back through **`MAPPED`**, and the handler wrote that key and `IntegrationStatus = 'PENDING'` onto its own root through `IN LOCAL MODE`. Both business objects were then readable from the **same transactional buffer** — the intent carrying `PurchaseOrderUUID 37FC…5EB6`, `OrderRevision 0`, `DispatchState PENDING`, and `PayloadSnapshot` and `PayloadHash` **initial**, exactly as ADR-015 expects of values nothing has decided yet. A `ROLLBACK ENTITIES` from the harness discarded **both** changes: zero persisted intents, and the header still `NOT_REQUESTED` with an initial `DeliveryId`. No commit was issued inside the handler, and no network call occurred.

So the five things Phase 5.2f needed are established: a handler **may** drive a second business object; the managed key is available to it through `MAPPED`; that key can be written back to the root in local mode; both operations share one transactional buffer; and the external harness alone controls commit or rollback, which is what the repository's *"no `COMMIT WORK` in handler code"* rule always assumed.

**What this deliberately did not settle.** The probe ran against a `DRAFT` fixture at `OrderRevision 0` **because eligibility was outside its scope**, and that is not a statement about what `sendToSupplier` should accept. It defines no business eligibility, no repeat-send semantics, no `PayloadSnapshot` ownership and no `ApprovedBy`/`ApprovedAt` source. Those are contract decisions, and the remaining Phase 5.2f work is entirely of that kind — no technical unknown is left.

---

### 9.4 Phase 5.2g — the coordinator, and three things only running it could find

**Phase 5.2g is SAP runtime-verified.** The A—J matrix passed in two parts: one network-free run covering A—D and F—J against the deterministic fake, and one real-HTTP run covering E against the deployed portal.

| | What was proven | Evidence |
| --- | --- | --- |
| **D1** | The persisted snapshot survives a full round trip | reader —> `TY_DELIVERY` —> `ZJP_CL_DLV_SNAPSHOT_JSON` returned the **byte-identical** golden snapshot |
| **D2** | The reconstruction is usable, not merely equal | the rebuilt DTO was accepted by `ZJP_CL_CAP_ORDER_MAPPER` with no adaptation |
| **A** | A `PENDING` intent is claimable | `IN_FLIGHT`, `LeaseOwner` = this run, expiry in the future, immutable evidence intact |
| **B** | A live lease cannot be stolen | second worker refused with `LEASE_LIVE`; owner, expiry and state all untouched |
| **C** | A stale lease is recoverable | expiry forced into the past, reclaimed by a second worker — **same `DeliveryUUID`**, new owner, new expiry |
| **E** | The real delivery works | **HTTP 201** from the deployed portal: intent `DELIVERED`, order `APPROVED` —> `SENT`, `IntegrationStatus` `DELIVERED`, `PortalOrderUUID` stored, lease released |
| **F** | An idempotent 200 is a success, not a duplicate | intent `DELIVERED`, exactly **one** intent, same identity, order `SENT` |
| **G** | A 409 stays meaningful | `answered = true`, `DispatchState` `FAILED`, order `ERROR`, `HTTP_409` evidence persisted, lease released |
| **H** | An unanswered call is ambiguous, not failed | classified `UNKNOWN`, order `ERROR`, correlation and error evidence persisted |
| **I** | Attempt identity differs from message identity | second attempt minted a **new correlation UUID**; `DeliveryUUID` unchanged |
| **J** | The approved message is immutable | `PayloadSnapshot`, `PayloadHash`, `ApprovedBy` and `ApprovedAt` all unchanged across a full run |

**The 201 run in full:** `CLAIMED` X, `DISPATCHED` X, `ANSWERED` X, `HTTP_STATUS` 201, `FINAL_STATE` `DELIVERED`, `BUSINESS_STATUS` `SENT`, `RECORDED` X, both error fields initial. After the commit the intent carried `DispatchState DELIVERED`, the original snapshot and hash, `ApprovedBy ZHUB.USER`, the attempt’s correlation id, a complete `PortalOrderUUID` and **initial lease fields**; the header carried `Status SENT`, `IntegrationStatus DELIVERED`, an unchanged `DeliveryId`, the correlation id and no error.

**Three things only running it could find, and all three are now permanent.**

**XCO’s `WRITE_TO` is terminal.** The first draft chained `FROM_STRING` —> `WRITE_TO` —> `APPLY`; the compiler refused it because `WRITE_TO` has no `RETURNING` parameter and cannot sit in an expression chain. The verified order is **`FROM_STRING` —> `APPLY` —> `WRITE_TO`**, in both places that bind JSON.

**`CL_SYSTEM_UUID`’s conversions are named by representation, not by direction.** The inverse of P5’s call is **`EXPORTING uuid = <C36>` / `IMPORTING uuid_x16 = <X16>`**: `uuid` is the input both ways.

**A lowercase UUID converts into a silently corrupted one.** CAP returns `portalOrderId` in lowercase. On this target that produced the X16 `93933000000000000000000000000000` from `93933dd0-aad3-49ff-bc92-…` — stopping at the first lowercase hex letter — **with no exception**. A run therefore reached 201 and stored a garbage receipt identity while reporting success everywhere. Debugging proved the CAP body and the XCO binding were both correct. The permanent fix uppercases the value **and then verifies it by converting back to C36 and comparing**, discarding it if it does not survive: this API has already returned a wrong answer without raising, so a clean return is not evidence. The final run stored `ED267DA783E24A388CB3DFE095F7A5FC`. **This is not debug code and must not be simplified away.**

**Two environment findings came with it.** A Cloud Foundry **404 `requested route does not exist`** meant `cap-supplier-portal-srv` was in requested state **stopped** (`web:0/1`), not that `ZJP_CAP_BASE` was wrong; `cf start` fixed it and the route never changed, so confirm application state before editing a destination. And the deployed portal answered **400 `UNKNOWN_SUPPLIER`** for `SUP041`, correctly — production CAP HANA carries no local fixture data. The runtime test therefore uses the synthetic **`RTTEST001`**, *“Runtime Test Supplier (synthetic, HANA runtime verification)”*, which is a **deployed prerequisite** of test E: if it is missing the test fails with a 400, and the fix is to restore the supplier, never to special-case it in the builder or the mapper. That 400 was useful in itself — it proved route, OAuth, HTTP adapter, endpoint and CAP validation were all working before a single order was accepted.

---

## 10. Proposed ABAP object inventory for Phase 5.2

**Objects 1–4 now exist and are SAP runtime-verified as Phase 5.2b**, together with the Table Index the inventory did not originally list because P8 had not yet established that an index is a separate repository object. **Objects 5, 6 and 13 exist and are SAP runtime-verified as Phase 5.2c.** Objects **7–11 do not exist** — in particular there is no builder, no mapper, no real HTTP transport, no `sendToSupplier` and no coordinator, and Phase 5.2d has not started. Object **12** already existed and has been extended twice, in 5.2a and 5.2b; Phase 5.2c did **not** extend it, because 5.2c changes no RAP behavior. Object **13**, `ZJP_CL_TRANSPORT_TEST`, is new to this inventory and was added by the explicit decision recorded in 10.1 — it is 5.2c's own console harness and exists as unactivated source alongside objects 5 and 6. Activation order matters — persistence before views, views before behavior — and the 5.2b activation confirmed it.

The Phase 5.2b stack as built: `ZJP_PO_DLV`, `ZJP_PO_DLV~REV`, `ZJP_I_DeliveryIntent`, `ZJP_I_DELIVERYINTENT`, `ZBP_I_DELIVERYINTENT`, and the `ZJP_CL_PO_EML_TEST` extension. The Phase 5.2c source added on top of it: `ZJP_IF_OUTBOUND_TRANSPORT`, `ZJP_CL_TRANSPORT_FAKE` and `ZJP_CL_TRANSPORT_TEST`. **No projection, no OData binding, no draft, no HTTP, no real transport, no mapper, no dispatcher and no `sendToSupplier`.**

### 10.1 Decision — a dedicated console harness, `ZJP_CL_TRANSPORT_TEST`

Phase 5.2c needed compiler and runtime evidence before it could be VERIFIED, and the inventory did not say where that evidence should be produced. Neither existing candidate fitted, so the question was raised rather than answered silently. **It was decided: a dedicated console class, `ZJP_CL_TRANSPORT_TEST`, object 13 of the inventory above — now built, activated and runtime-verified.** The decision is recorded here so the object is no longer an undocumented exception to the section 10 inventory. The division it establishes is the one to keep: `ZJP_CL_TRANSPORT_TEST` owns the transport seam, `ZJP_CL_PO_EML_TEST` stays the RAP lifecycle regression suite and was not touched, and `ZJP_CL_PO_DISPATCH_TEST` stays reserved for the Phase 5.2g coordinator.

| Candidate | Why it does not simply fit |
| --- | --- |
| `ZJP_CL_PO_EML_TEST` (object 12) | The repository rule is to extend it *whenever RAP behavior changes*. Phase 5.2c changes no RAP behavior at all — it adds an interface and a class that touch no business object — so extending it would widen a lifecycle regression suite into a unit-test harness for a non-RAP object. It is, however, the project's only existing console test class, and the 5.2b naming decision already treated it as the default home for anything that is not dispatch |
| `ZJP_CL_PO_DISPATCH_TEST` (object 11) | Reserved for the coordinator — *claim, dispatch, record, commit* — which is Phase 5.2g. Using it now would either implement dispatcher behaviour early or leave a coordinator-named class containing only transport unit tests |
| A new console class | Means adding an object the section 10 inventory did not list — acceptable only as a recorded decision, which is what this section now is |

**The third was chosen, over a recommendation to extend `ZJP_CL_PO_EML_TEST`.** The reasoning that decided it is the same reasoning that made the first two uncomfortable, taken to its conclusion: a test object's name is where a scope boundary is visible, and the 5.2b naming decision already treated it that way. `ZJP_CL_PO_EML_TEST` is an EML lifecycle regression suite for a RAP business object, and 5.2c contains no EML, no business object and no RAP behavior at all; putting transport unit tests inside it would make the suite's name a lie and couple a seam test to a lifecycle fixture chain it has no reason to depend on. The cost is a second runnable console class, which is a smaller price than a misleading one.

`ZJP_CL_TRANSPORT_TEST` is therefore deliberately narrow: it verifies the seam and its fake and nothing else, it is not a test framework, and it is not a home for future unrelated tests. When the coordinator arrives in 5.2g it gets `ZJP_CL_PO_DISPATCH_TEST`, which stays reserved for exactly that.

### 10.2 Decision — `ZJP_CL_BUILDER_TEST` for Phase 5.2d

The same question returned for the builder and the mapper, and was decided the same way and for the same reason: **Phase 5.2d changes no RAP behavior**, so the rule that `ZJP_CL_PO_EML_TEST` changes whenever RAP behavior changes does not reach it, and `ZJP_CL_PO_DISPATCH_TEST` stays reserved for 5.2g. `ZJP_CL_BUILDER_TEST` is object 14 of the inventory above, recorded here so it is not an undocumented exception.

**It carries two kinds of evidence that cannot be merged, and the split is the interesting part.** The **builder** is tested against a **real active PurchaseOrder**, because what is worth proving is that it copies what SAP actually holds — expected values are read independently with a read-only `SELECT`, so the builder's EML path and the test's SQL path have to agree, and a mistake in either is visible. It creates no fixture, writes nothing and commits nothing; it also counts persisted rows before and after so "read-only" is asserted rather than assumed. The **mapper** is tested against a **deterministic in-memory snapshot**, because what is worth proving there is byte-exact wire output, and a live order with generated identities can never give that. Its expected body is the golden payload the P10 probe produced, which is in turn the shape the deployed CAP `IntegrationService` accepted with 201.

That one byte comparison covers every member name, the nesting, the scalar types, all four decimal scales, the C36 UUID form, `revision` and `lineNumber` as JSON numbers, `00010` → `10` and `EA` → `PCE` at once — and it cannot be satisfied by accident, which a field-by-field assertion can. **The run passed it.**

### 10.3 Decision — `ZJP_CL_HTTP_TRANSPORT_TEST` for Phase 5.2e

The same question, answered the same way a third time, and here the reason is sharper than scope hygiene. `ZJP_CL_TRANSPORT_TEST` is the Phase 5.2c harness and its **verified meaning is that it touches no network** — that claim is asserted in its own source and was checked by scanning every identifier in its executable code. Putting real HTTP into it would not merely widen its scope; it would falsify a statement the repository has already proven. `ZJP_CL_PO_DISPATCH_TEST` stays reserved for the 5.2g coordinator. So Phase 5.2e gets its own object, number 15 in the inventory above.

It is the **only test object in this project that makes real network calls**, and it says so at the top of its own source. It drives the production adapter through `REF TO ZJP_IF_OUTBOUND_TRANSPORT`, naming the concrete class once at construction, so a passing run proves the seam carries a real implementation as well as a fake — which is the whole claim Phase 5.2c's boundary was drawn to make possible.

**It deliberately does not use the builder or the mapper.** Deterministic literal bodies isolate transport behaviour: if an assertion fails, the adapter is the only thing that can have caused it. Those bodies are built by concatenation rather than held as constants, because Phase 5.2d established that a text literal caps at 255 characters and a `CONSTANTS` `VALUE` cannot be split.

**The delivery identity is fixed, and that has a consequence worth stating rather than hiding.** No released UUID-generation API is verified on this target — that is **P14**, still open — so the harness cannot mint one. CAP's ingestion is idempotent on `deliveryId`, so the first call returns **201 only on the first ever run**; a rerun returns **200**. The harness prints a plain note in that case and passes, and the replay and conflict assertions are untouched, because neither ever depended on the first call's status code. Solving this by adding UUID creation to production code would be the wrong trade entirely.

**The split earned its keep on the first run, in a way worth recording.** The order the builder happened to pick carried **`OrderRevision = 0`** — a row persisted before Phase 5.2a, which P11 already established keeps its original values and was never back-filled. The snapshot carried `0` through unchanged. That is **stronger** evidence than a `1` would have been: `1` is exactly what a builder that quietly recalculated the revision would also produce, so the copy and the mistake would have looked identical. A `0` can only have been copied. Meanwhile the mapper's fixture carries `revision = 1`, because it is an independent deterministic path whose job is byte-exact wire output, not RAP read behaviour. The two numbers differ because the two tests prove different things, which is the point of keeping them apart.

| # | Object | Type | Purpose |
| --- | --- | --- | --- |
| 1 | `ZJP_PO_DLV` | Database table | Delivery intent persistence, section 4.2. **EXISTS — Phase 5.2b, runtime-verified.** `payload_snapshot` kept as `abap.string` on P9 evidence |
| 1a | `ZJP_PO_DLV~REV` | **Table Index** | Not in the original inventory, because P8 had not yet shown an index is a separate repository object. Unique over `CLIENT`, `PURCHASE_ORDER_UUID`, `ORDER_REVISION`. **EXISTS — physically present in the database, verified through SE14 and by an ST22 dump on a deliberate violation** |
| 2 | `ZJP_I_DeliveryIntent` | Root view entity | Exposes the table to RAP; no composition. **EXISTS — Phase 5.2b, runtime-verified** |
| 3 | `ZJP_I_DELIVERYINTENT` | Behavior definition | Managed, `strict ( 2 )`, **no draft**; every integration field `readonly`; no projection and no binding. **EXISTS — Phase 5.2b, runtime-verified**, with two corrections from compiler evidence: `lock master` with **no total etag** (ADT: a total etag needs `with draft`, which this BO deliberately does not have), and `field ( readonly, numbering : managed ) DeliveryUUID`, which makes a caller-supplied duplicate key a compile error rather than a runtime case |
| 4 | `ZBP_I_DELIVERYINTENT` | Behavior pool | Claim-under-lease and state-transition handlers; instance authorization consistent with the existing study stub. **EXISTS as a skeleton — Phase 5.2b, runtime-verified.** Only `get_instance_authorizations` is implemented, which is all `authorization master ( instance )` obliges; the claim and state-transition handlers belong to later slices |
| 5 | `ZJP_IF_OUTBOUND_TRANSPORT` | Interface | The seam, section 6.2. **EXISTS — Phase 5.2c, SAP runtime-verified.** Implemented exactly as section 6.2 specifies it, and activated unchanged. A consumer holding `REF TO ZJP_IF_OUTBOUND_TRANSPORT` dispatched to an implementation at runtime, so the seam is demonstrated and not merely declared |
| 6 | `ZJP_CL_TRANSPORT_FAKE` | Class | Scripted 201 / 200 / 409 / timeout for tests; no network. **EXISTS — Phase 5.2c, SAP runtime-verified.** All four scenarios returned their deterministic outcomes; four scenarios by constructor injection; structurally proven network-free and confirmed so at runtime, since the run needed no destination, no OAuth and no connectivity of any kind; see 6.5 |
| 7 | `ZJP_CL_OUTBOUND_TRANSPORT` | Class | Real HTTP. **EXISTS — Phase 5.2e, SAP runtime-verified.** Performed real OAuth-protected POSTs to the deployed portal returning 201, 200 and 409, and classified an unresolvable destination as a technical failure. Implements the verified seam over `ZJP_CAP_BASE`, applying `TY_REQUEST-PATH` through `SET_URI_PATH`; destination name is constructor-injected and no route is hard-coded. Forwards headers generically and sends the body unchanged; contains no SQL, no EML, no `COMMIT` and no `ROLLBACK`, knows nothing of PurchaseOrder or DeliveryIntent, interprets no CAP business error, and generates no correlation UUID. P15 and the path-ownership decision in 9.2 are settled. P1–P4 are answered and the working chain is proven (1.5). This class is where the destination-based chain is wrapped, and the one place a Standard ABAP language version may be required; see the boundary note below |
| 8 | `ZJP_CL_ORDER_DELIVERY_BUILDER` | Class | RAP buffer → source delivery DTO; no HTTP, no JSON. **EXISTS — Phase 5.2d, SAP runtime-verified.** Built a snapshot from a real active order and changed nothing: reads one active order through EML and is read-only. Publishes the canonical snapshot types `TY_ITEM` / `TY_ITEMS` / `TY_DELIVERY`, which keep **SAP-native** values — raw `sysuuid_x16`, numeric amounts, `NUMC` item number, `EA` — so that Phase 6 can delete the mapping hop and keep this one |
| 9 | `ZJP_CL_CAP_ORDER_MAPPER` | Class | Source delivery → mapped CAP order JSON; pure and deterministic; owns `EA` → `PCE`. **EXISTS — Phase 5.2d, SAP runtime-verified.** Produced the golden CAP payload **byte for byte**, twice from the same snapshot, and refused an unmapped unit. Produces the verified seam's `TY_REQUEST`; every wire concern lives here — C36 UUIDs, fixed-scale decimal strings, `NUMC` → JSON number, explicit camelCase members |
| 10 | `sendToSupplier` | Action on `ZJP_I_PurchaseOrder` | Parameterless, active-instance only, `authorization : update`, following the verified `submit` / `approve` / `cancel` shape. **EXISTS — Phase 5.2f, SAP runtime-verified.** Creates or reuses the durable intent per the 7.4 contract, with no HTTP, no commit and no rollback. **All eight branches passed**: new intent, `PENDING` replay, `FAILED` retry, non-approved refusal, technical-draft refusal, `IN_FLIGHT` no-op, `DELIVERED` informational no-op with no `SENT` transition, and `UNKNOWN` retry. **Still not exposed through `ZJP_C_PurchaseOrder`** — projection exposure is a separate decision, and an action is proven through EML before it is offered to a UI |
| 11 | `ZJP_CL_PO_DISPATCH_TEST` | Console class | The coordinator harness, run explicitly. **EXISTS — Phase 5.2g, SAP runtime-verified**, description *Purchase Order Dispatch Coordinator Test*. Reserved for this since 5.2c and used for it now. It supplies fixtures through the production path only — create, submit, approve, `sendToSupplier` — chooses which transport goes into the coordinator, and asserts the A-J matrix. **It is the second object in the project that makes real network calls**, in test E only, and says so in a banner on its first console line |
| 16 | `ZJP_CL_DLV_SNAPSHOT_JSON` | Class | **Added by decision in Phase 5.2f** — the source order delivery snapshot serializer, typed `TY_DELIVERY` → deterministic JSON string for `ZJP_PO_DLV-PayloadSnapshot`. Stateless and pure; no EML, no database, no HTTP, no hashing, and no CAP vocabulary — the source contract keeps `EA`, so `EA` → `PCE` stays the mapper's alone. It exists because objects 8 and 9 deliberately cannot do this: the builder is specified "no JSON" and the mapper emits only the CAP shape. **EXISTS — Phase 5.2f, SAP runtime-verified**: it produced the golden source snapshot byte for byte, twice from the same DTO |
| 17 | `ZJP_CL_DLV_SNAPSHOT_READER` | Class | **Added by decision in Phase 5.2g** — the exact inverse of object 16: `ZJP_PO_DLV-PayloadSnapshot` back to `TY_DELIVERY`, so the coordinator can dispatch the **persisted** snapshot instead of rebuilding one. It exists because the two verified objects do not fit together — the snapshot is a string and `ZJP_CL_CAP_ORDER_MAPPER=>MAP` takes a typed structure — and because ADR-032 forbids both shortcuts that would avoid it. Stateless and pure; reads no PurchaseOrder, reads no `ZJP_PO_DLV` row, opens no connection, computes no hash and mutates nothing. **EXISTS — Phase 5.2g, SAP runtime-verified.** Two target facts were learned by failing first and are recorded at their call sites: XCO’s `WRITE_TO` is terminal, and the `C36` to `X16` conversion corrupts lowercase input without raising |
| 18 | `ZJP_CL_DISPATCH_COORDINATOR` | Class | **Added by decision in Phase 5.2g** — the post-commit coordinator ADR-006 has described since Phase 1: claim under a lease and commit, POST, then record the outcome and commit. Runs **outside every behavior handler**, which is what makes the HTTP call legal at all. Transport is **injected through the verified seam**, never constructed, so the whole contract is testable with the fake and no network. **EXISTS — Phase 5.2g, SAP runtime-verified**, description *Purchase Order Dispatch Coordinator*. The split from object 11 is deliberate and recorded in 10.4 |
| 19 | `recordDeliveryResult` + `ZJP_A_RecordDeliveryResult` | Action + abstract entity | **Added by decision in Phase 5.2g**, moved forward from 5.x. The coordinator’s outcome boundary, and the only way the header’s readonly integration fields can be written: `Status`, `IntegrationStatus`, `LastErrorCode`, `LastErrorMessage`, `LastErrorAt` and `LastCorrelationId` are every one of them `field ( readonly )`, so an external EML consumer cannot touch them and only a handler in local mode may. **A normal action, not an `internal action`** — the coordinator is an external consumer and `internal` would put it out of reach; “restricted” here means **not projected**. **EXISTS — Phase 5.2g, SAP runtime-verified.** The parameter entity’s description is *Purchase Order Delivery Result Parameter* |
| 15 | `ZJP_CL_HTTP_TRANSPORT_TEST` | Console class | **Added by decision in Phase 5.2e, see 10.3** — the runtime harness for the real HTTP adapter, and the only test object in this project that makes **real network calls**. Drives the production adapter through `REF TO ZJP_IF_OUTBOUND_TRANSPORT` against the deployed CAP application: 201, idempotent 200, 409 `DELIVERY_PAYLOAD_CONFLICT`, and an unresolvable destination for the unanswered path. **EXISTS — Phase 5.2e, SAP runtime-verified**, ending with `PASS: Phase 5.2e real HTTP transport verified.` |
| 14 | `ZJP_CL_BUILDER_TEST` | Console class | **Added by decision in Phase 5.2d, see 10.2** — the runtime harness for the builder and the mapper. Tests the builder against a **real active order** with expected values read independently by SQL, and the mapper against a **deterministic in-memory snapshot** compared byte for byte with the golden CAP payload. **EXISTS — Phase 5.2d, SAP runtime-verified**, ending with `PASS: Phase 5.2d outbound builder and CAP mapper verified.` One compiler correction on the way: the golden payload could not be a `CONSTANTS` `VALUE`, because a text literal caps at 255 characters and a constant's value must be a single literal, so it became a concatenating method |
| 13 | `ZJP_CL_TRANSPORT_TEST` | Console class | **Added by decision in Phase 5.2c, see 10.1** — the runtime harness for the transport seam and its fake. Drives all four scenarios through `REF TO ZJP_IF_OUTBOUND_TRANSPORT`, never through the concrete class after construction. **EXISTS — Phase 5.2c, SAP runtime-verified**, ending with `PASS: Phase 5.2c outbound transport abstraction verified.` and no `STOP`. Deliberately narrow: it is not a test framework and not a home for unrelated tests |
| 12 | `ZJP_CL_PO_EML_TEST` | **Existing** console class | Must be extended whenever RAP behavior changes, per repository policy. **Already extended in Phase 5.2a** for the B1 revision change and the B2 initial value, with a new `check_integration_fields` helper and five assertions; still to be extended for `sendToSupplier` |

Also for 5.2, and deliberately listed so they are not forgotten: the ADR-022 `APPROVED` → `CANCELLED` delivery-request guard, which `DeliveryIntent` finally makes representable; and the `IntegrationStatus` initial-value decision from B2.

**The ABAP Cloud boundary, now that the transport chain is known.** The working probe reaches its target by **destination name** through `CL_OUTBOUND_PROVIDER_HTTP=>CREATE_BY_DESTINATION`, and the surrounding configuration — an HTTP destination, an SSL client PSE, a trust list — is classic on-premise administration rather than the communication-arrangement mechanism ABAP for Cloud Development expects. That makes it **likely, but not yet established, that the probe ran under the Standard ABAP language version.** The repository must not assume either way: the follow-up on P1 is to report the class's ABAP language version and what ADT's Released APIs view says about `CL_OUTBOUND_PROVIDER_HTTP` for ABAP Cloud.

The design already places the seam correctly for either answer. Object 5, `ZJP_IF_OUTBOUND_TRANSPORT`, deliberately uses nothing but `abap_bool` and built-in types, so it compiles on both sides of the boundary; object 7, `ZJP_CL_OUTBOUND_TRANSPORT`, is the **only** object that touches an HTTP API. If the chain turns out to be unavailable under ABAP Cloud, object 7 is the single object that carries the Standard ABAP language version and everything else — the `DeliveryIntent` BO, the builder, the mapper, `sendToSupplier` and the coordinator — stays ABAP Cloud, depending on the interface rather than on the client. That is the boundary working as intended, and it is the reason the seam was specified before the API was known.

`ZJP_PO_H`, `ZJP_PO_I`, both base views, both projections, both behavior definitions, the behavior pool, the service definition and the binding are **unchanged**. Nothing in Phase 5.2 as scoped here requires editing a Phase 1–3 artifact except adding one action line to the base BDEF and one write to `submit`.

---

### 10.4 Decision — a coordinator service **and** a console runner for Phase 5.2g

**Two objects, not one, and the reason is testability rather than tidiness.** The section 10 inventory listed only object 11, a console class described as *“the coordinator, run explicitly; claim, dispatch, record, commit”*. Building it that way would have made the only runnable coordinator the one that always calls the network.

`ZJP_CL_DISPATCH_COORDINATOR` takes its transport through `REF TO ZJP_IF_OUTBOUND_TRANSPORT`, so the claim contract, the lease rules, the snapshot reconstruction and three of the four classification branches can be exercised with the deterministic fake and **no network at all**. Only test E needs the real adapter. Folding the two together would have left the lease and classification contracts unexercisable, and would have repeated the mistake the builder/builder-test and transport/fake splits were drawn to avoid — the same argument 10.1 used to give the transport seam its own harness.

**The split is also what ARCHITECTURE asks for.** *“The first coordinator can be an explicitly run ABAP console application outside BO handlers”* describes the runner; *“claim through EML, commit, send using a released HTTP client, then record the receipt through EML and commit”* describes the service. `CLAIM_INTENT` is public for the same reason: *“this makes the commit boundaries observable”*, so transaction A can be run and inspected on its own with a durable row in between.

---

## 11. Deferred to Phase 5.2 and later

| Item | Phase |
| --- | --- |
| `sendToSupplier` implementation and its intent creation | 5.2 |
| ~~`OrderRevision = 1` at submit (B1) and the `IntegrationStatus` initial value (B2)~~ — **done in Phase 5.2a and SAP runtime-verified** | 5.2a ✔ |
| ~~The transport seam `ZJP_IF_OUTBOUND_TRANSPORT`, the fake `ZJP_CL_TRANSPORT_FAKE` and the harness `ZJP_CL_TRANSPORT_TEST`~~ — **done in Phase 5.2c and SAP runtime-verified** | 5.2c ✔ |
| ~~The builder and the mapper~~ — **done in Phase 5.2d and SAP runtime-verified**, after P5, P6 and P10 were answered | 5.2d ✔ |
| ~~The real HTTP transport `ZJP_CL_OUTBOUND_TRANSPORT`~~ — **done in Phase 5.2e and SAP runtime-verified**, after P15 was answered | 5.2e ✔ |
| ~~`sendToSupplier`, durable intent creation and the `payload_hash`~~ — **done in Phase 5.2f and SAP runtime-verified** | 5.2f ✔ |
| ~~The coordinator, the first real `POST` from a persisted intent, receipt handling, the `SENT` transition and lease management~~ — **done in Phase 5.2g and SAP runtime-verified.** Formerly not started; gated by **P14**, **P16** and **P17**, all three now source-prepared and awaiting SAP verification. **Two architectural decisions are locked.** `lease_seconds` is an **explicit coordinator input**: tests and runners inject a value, and no production default or configuration object is introduced yet, which settles the lease duration without inventing an operational timeout. And **`recordDeliveryResult` moves into 5.2g** (row below), because the coordinator cannot externally write the header outcome fields and 5.2g owns the `APPROVED` → `SENT` transition | 5.2g ✔ |
| The real HTTP transport, after P1–P4 | 5.2e |
| The coordinator, the first real `POST`, and receipt handling | 5.3 |
| `retryDelivery`, the bounded retry budget and `attempt_count` | 5.x |
| `applySupplierResponse`, the restricted integration projection and Web API binding (OI-03 remainder) | 5.x |
| The CAP → SAP response sender, and CAP's transport state beyond `PENDING` | 5.x |
| ~~`recordDeliveryResult` as a separate restricted operation~~ — **moved from 5.x into 5.2g and SAP runtime-verified.** Every header field the outcome step must write — `Status`, `IntegrationStatus`, `DeliveryId`, `LastErrorCode`, `LastErrorMessage`, `LastErrorAt`, `LastCorrelationId` — is `field ( readonly )` in the base BDEF, so an external console coordinator cannot write them by plain EML; only in-handler `IN LOCAL MODE` can, which is why `sendToSupplier` writes that way. The `DeliveryIntent` side has no such problem, and its external EML updates are already runtime-verified. It **stays internal** — not exposed through `ZJP_C_PurchaseOrder` and not through OData, per API_CONTRACTS’ *“prefer EML-only access for coordinator bookkeeping”*. **Its parameter structure is deliberately not designed yet**; that comes with the 5.2g RAP outcome boundary, after the probes | **5.2g** |
| Integration Suite, CPI/iFlows | 6 |
| DeliveryAttempt history | 7 |
| OAuth, XSUAA, IAS, destinations, production credentials | 8 |
| Event Mesh | 9 |
| API Management | 10 |
| Scheduler or background retry worker | later, release-dependent |

## 12. What Phase 5.1 did not do

No ABAP object was created or changed. No table, view, behavior definition, behavior pool, service definition or binding was touched. No CAP file was modified, and no CAP behavior changed. **Phase 5.2 is not started**: none of the twelve objects in section 10 exists.

*Since this section was written, four things have happened. **Phase 5.2b built objects 1–4 of the section 10 inventory plus the Table Index**, all SAP runtime-verified, so "no table was touched" and "Phase 5.2 is not started" no longer hold — though no projection, binding, draft or HTTP was added, and `sendToSupplier` still does not exist. The connectivity half of 5.1 was carried out and runtime-verified — CAP was deployed to Cloud Foundry, SAP-side destinations and OAuth2 were configured, certificate trust was fixed, and an outbound probe reached the deployed endpoint (see 1.5) — so the original sentence "no HTTP request was made in either direction" no longer holds and **blocker B3 is resolved**. And **Phase 5.2a resolved blockers B1 and B2** by changing two existing classes, `ZBP_I_PURCHASEORDER` and `ZJP_CL_PO_EML_TEST`, so "no behavior definition changed" remains true but RAP behavior itself did change. And **Phase 5.2c built objects 5 and 6** — the transport interface and its fake — plus a thirteenth object the original inventory did not contain, the console harness `ZJP_CL_TRANSPORT_TEST` added by the decision in 10.1. So "none of the twelve objects exists" is now false for six of them, and the inventory itself has grown by one; all three 5.2c objects activated and ran, and are SAP runtime-verified. The design half of 5.1 is otherwise unchanged and still not runtime-verified: no builder, no mapper, no real transport class and no `sendToSupplier`, and no revision-increment behaviour.*
