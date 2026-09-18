# Environments, accounts and service access

Phase 0 needs only a local editor and Git. For Phase 1, the learner manually created and activated all six domain-model objects in an SAP S/4HANA study environment using ADT/Eclipse and ABAP Cloud. Exact release remains unrecorded; this report establishes access for that model work, not future communication-administration permissions. No SAP account has been inspected or provisioned through this workspace. Later service dependencies below are not confirmed entitlements. Source review date: 2026-09-12.

SAP BTP trial and free tier are different: trial is for limited personal evaluation, while free service plans belong to an enterprise account and have service-specific conditions. Region, provider, plan and quota affect availability; do not assume all listed services are free or available together. Check the cockpit and current service catalog before provisioning. See [SAP trial and free tier guidance](https://help.sap.com/docs/btp/sap-business-technology-platform/trial-accounts-and-free-tier).

## Production target and learning alternatives

| Capability / first needed | Real deployment requirement | Local or constrained alternative | What the alternative cannot prove |
| --- | --- | --- | --- |
| GitHub presentation / phase 11 | GitHub account and a remote repository | Local Git repository throughout development | Published GitHub portfolio until actually pushed |
| RAP / phases 1–3 | SAP BTP ABAP environment, or suitable S/4HANA ABAP Cloud development system; developer user/package permissions | Draft ABAP source and inspect design locally; a later HTTP stub can simulate its external contract | ABAP compilation, CDS activation, RAP draft, EML, ATC, real service binding |
| ABAP tooling / phase 1 | Eclipse with compatible ABAP Development Tools and a system connection | Editor for source review | ADT is a client, not a local ABAP runtime |
| Fiori Elements / phase 3 | Actual RAP OData V4 UI service; supported UI deployment or service preview | Local SAP Fiori tools and mock metadata/data for UI work | Real RAP actions, authorizations and draft interactions |
| CAP / phase 4 | Node.js application runtime; production target BTP Cloud Foundry | Node.js/TypeScript, CAP tooling and SQLite on laptop | BTP deployment/operations; local CAP itself is real CAP |
| CAP production database / later deployment | SAP HANA Cloud, HDI/container capabilities and bindings as appropriate | SQLite using portable CDS/CQN | HANA-specific semantics, SQL behavior and deployment compatibility |
| CAP HANA production configuration / prepared | `@cap-js/hana` on the production profile, plus an HDI deployer module from `cds build --production` | Local development keeps SQLite `:memory:` on the default profile; both profiles verified with `cds env` | Nothing about HANA at runtime. The generated DDL has been read, but no schema has been deployed, no query has run on HANA and no binding exists |
| Direct HTTP / phase 5 | Released ABAP outbound HTTP APIs, supported communication setup, reachable CAP URL; reverse access to RAP Web API | Local CAP and contract test clients; explicitly labeled RAP stub if SAP is unavailable | Actual SAP connectivity and RAP runtime behavior |
| Cloud Integration / phase 6 | Integration Suite subscription/entitlement with Cloud Integration capability, developer/deployer and monitoring permissions | Mapping fixtures and a local Node.js integration simulator created in the relevant phase | iFlow deployment, adapters, graphical mapping runtime, message processing logs |
| OAuth / phase 8 | Identity provider, OAuth clients, XSUAA where chosen, roles/scopes and CAP service bindings | CAP mock users; later a local OAuth test issuer if useful | XSUAA provisioning, real trust/audience configuration and platform login |
| Machine-to-machine token / prepared ahead of phase 8 | An XSUAA `application` instance whose descriptor grants the technical scope through top-level `authorities`, and an OAuth2 client-credentials configuration on the SAP side | Mocked `sapintegration` user carrying the `IntegrationClient` role locally | That a *deployed* CAP accepts such a token, that the `supplier` attribute reaches `req.user.attr`, and that SAP can obtain and send the token at all |
| Destinations / phase 8 | BTP Destination service for relevant consumers; credentials/configuration | Named local endpoint configuration | Destination service behavior and tenant configuration |
| CI credentials / hosted integration | Security Material and adapter authentication supported by tenant | Environment variables in local simulator | Actual Security Material and adapter setup |
| ABAP connectivity / hosted integration | Communication scenarios/systems/arrangements and released client APIs available for selected system | Contract-level tests | Permissions and release support for outbound/inbound communication |
| Private SAP backend / conditional | Cloud Connector and Connectivity service where the chosen network route requires them | Local mock or development SAP endpoint already reachable | Private network tunneling and routing |
| SAP Event Mesh / phase 9 | Compatible messaging offering, service plan, clients, queues/topics, RAP outbound channel and CI consumption support | Durable local event simulation with duplicate/reordering/failure fixtures | SAP Event Mesh administration, channels, adapters or broker guarantees |
| API Management / phase 10 | Integration Suite API Management capability, roles and API proxy deployment | Local proxy demonstrates token/rate-limit concepts | SAP API policies, deployment and analytics |
| UI development IDE / optional | SAP Business Application Studio or local tools; BAS entitlement if used | VS Code with appropriate SAP tooling | BAS operation; BAS is optional for this project |

SAP documents [ABAP trial onboarding](https://developers.sap.com/tutorials/abap-environment-trial-onboarding.html) and a [CAP Cloud Foundry deployment path](https://cap.cloud.sap/docs/guides/deploy/to-cf). Trial access to an ABAP development user does not establish that all communication administration or event configuration needed by later phases is available.

## Network reality

A cloud ABAP system or CI tenant cannot call the laptop's `localhost`. For a real round trip, CAP must be reachable from the caller using an authenticated HTTPS endpoint. Prefer deploying CAP to the selected BTP runtime when available. A deliberately configured development tunnel or supported private-connectivity route is a temporary alternative and must be recorded explicitly. It is not a destination configuration alone.

Local CAP may be able to call a reachable SAP endpoint even when SAP cannot call back to local CAP. Test each direction separately. If an actual runtime is missing, mark the round trip as contract simulation; do not silently switch technologies or advance the SAP-runtime completion gate.

Phase 5.1 reviewed this for the outbound SAP → CAP leg and compared the two permitted options — a deliberately configured HTTPS development tunnel, and CAP deployed to a reachable hosted runtime such as BTP Cloud Foundry — without choosing or configuring either; see the [Phase 5.1 outbound foundation](../abap-rap/docs/phase-5-1-outbound-foundation.md). **The choice is still open and nothing is deployed.** Two consequences are recorded there rather than assumed away: a tunnel must be written into this file while it is in use, and it publishes the CAP ingestion endpoint, which has no authentication of any kind, for as long as it runs.

## Event offering decision, deferred to phase 9

Confirm whether the account offers standalone SAP Event Mesh or Event Mesh as an Integration Suite capability, and whether the ABAP outbound channel and CI consumer support that offering. Record the exact product, plan, region, protocol and adapter. SAP documents [initialization of the Integration Suite Event Mesh capability](https://help.sap.com/docs/integration-suite/sap-integration-suite/initiating-event-mesh).

SAP Integration Suite, advanced event mesh is a separate offering; it is not required for this project's baseline. Its [bridge prerequisites](https://help.sap.com/docs/integration-suite/sap-integration-suite/activating-event-mesh-bridge) illustrate the distinct subscriptions. Do not substitute it automatically, or assume Cloud Integration JMS availability proves SAP Event Mesh access. Dead-letter and retry mechanisms must be checked against the selected product and plan.

## Environment record to complete before relevant implementation

| Item | Current value |
| --- | --- |
| ABAP product and release | SAP S/4HANA with ABAP Cloud confirmed by learner. Version baseline recorded from the Phase 2.6 target: SAP_BASIS 758 SP0001, S4CORE 108 SP0001, ADT Core 3.60.3, Business Object Tools 1.209.0, Eclipse 4.40.0 |
| ABAP language version / package / namespace suffix | ABAP Cloud target; learner reports six ZJP_ objects created/activated in ADT; actual package name not reported |
| Developer and communication administrator permissions | Development access demonstrated by reported activation; communication-administration permissions unknown |
| OData V4 UI / Web API binding support | To verify in target system |
| Released numbering and HTTP APIs | Numbering resolved: `CL_NUMBERRANGE_RUNTIME` with object `ZJP_PO` interval `01` is SAP runtime-verified in Phase 2.7E. Outbound HTTP remains unverified — the repository contains no reference to any ABAP HTTP client class, and the candidates plus the exact ADT probes needed are listed in the [Phase 5.1 outbound foundation](../abap-rap/docs/phase-5-1-outbound-foundation.md) |
| BTP account type, region, Cloud Foundry quota | **Trial** account. Cloud Foundry is available in region **`us10-003`**, and space **`dev`** exists and is usable. The CAP Supplier Portal **is deployed and running** in that space; see the section below. Exact quota figures and Trial lifecycle limitations — evaluation periods, automatic stopping of idle runtimes, account expiry and the conditions attached to individual service plans — are **environment-specific and must not be generalized from this record**; read them from the cockpit and the current service catalog at the time of use, per the trial-versus-free-tier guidance above |
| Integration Suite capabilities and roles | Unknown |
| HANA Cloud / HDI access | Available. Two service instances were created by the learner in Cloud Foundry space `dev`: **`pih-hana`** (service `hana-cloud`, plan `hana-free`) and **`pih-hdi`** (service `hana`, plan `hdi-shared`). The CAP application is deployed, **bound to `pih-hdi`**, and resolves its production profile to `HANAService`. HANA runtime behaviour is **verified for the ingestion path** — one real order written and read back — and **unverified for the supplier decision/update path**, since every write exercised was an INSERT |
| Event Mesh product and entitlement | Unknown; Phase 9 decision |
| XSUAA / identity provider / destination access | **XSUAA is available and exercised.** The `xsuaa` offering is in the Trial marketplace with the `application` plan (free), and a temporary probe instance **`pih-xsuaa-probe`** plus a service key `probe-key` exists in space `dev`, created solely to answer a client-credentials question and deliberately kept for now. Verified at the token level: a scope and role-template alone do not reach the application's own technical client; top-level `authorities` is required. Identity-provider configuration, role-collection assignment and Destination service remain **Unknown** and unexercised. No credential, service key or token is stored in this repository |
| GitHub remote | origin points to [procurement-integration-hub](https://github.com/joaopedromribeiro/procurement-integration-hub); main tracks origin/main, confirmed from local Git configuration |

Record non-secret environment facts here when available. Keep credentials, service keys, tokens, tenant-specific sensitive configuration and private destinations outside the repository.

## CAP deployed to Cloud Foundry, runtime-verified for auth and for HANA ingestion

The CAP Supplier Portal is **deployed and running** in Trial Cloud Foundry, region `us10-003`, space `dev`:

| Item | Value |
| --- | --- |
| Application | `cap-supplier-portal-srv` — started, 1/1 running, `nodejs_buildpack`, Node 24 |
| Route | `https://0badc38dtrial-dev-cap-supplier-portal-srv.cfapps.us10-003.hana.ondemand.com` |
| Schema deployer | `cap-supplier-portal-db-deployer` (MTA `hdb` module) |
| Database | existing HDI container **`pih-hdi`**, reused via `org.cloudfoundry.existing-service`; bound to app and deployer |
| Authentication | real XSUAA instance **`cap-supplier-portal-auth`**, created from the tracked `xs-security.json`, bound to the app |
| Redundant | **`pih-xsuaa-probe`** — bound to nothing, superseded by the real instance, **cleanup debt** |
| Test credential | **`runtime-test-key`** on `cap-supplier-portal-auth`, kept for the upcoming SAP outbound OAuth work. A standing credential; **temporary cleanup debt** — delete it when that work is done |
| Synthetic test data | One supplier `RTTEST001` and the order it received under `sourceSystem` `PIH_RUNTIME_TEST`, with its item and delivery receipt. **Intentionally left in place** as clearly labelled runtime-test data; see below |

**No duplicate HANA Cloud database and no duplicate HDI container were created** — the space still holds one `hana-cloud` instance and one `hdi-shared` container.

**Verified against the live route:** anonymous requests answer 401 everywhere; a real `client_credentials` token carrying `<xsappname>.IntegrationClient` reaches `/health/ping` with 200 and the ingestion handler with the portal's own 400; the same token is refused 403 on the supplier surface.

**HANA is also runtime-verified for the ingestion path.** The deployed application resolves the production profile to `HANAService`. Queried before any test data existed, the container held **0 rows in all four tables** while the tables themselves existed and were queryable — so the HDI deployment worked and the development-only fixture folder really did keep synthetic data out of production. A valid authenticated `POST /rest/integration/v1/Orders` then returned **201 RECEIVED** and HANA held exactly one Order, one OrderItem and one DeliveryReceipt, with the supplier association resolving and decimal scale and Timestamp precision surviving the round trip. An exact replay and a byte-different but business-equivalent replay both returned **200** with the same `portalOrderId` and the original `receivedAt`; a changed payload on the same `deliveryId` returned **409 `DELIVERY_PAYLOAD_CONFLICT`**; counts stayed at 1/1/1. The container's catalog holds **no `IntegrationService.Orders` table**, and `CDS_OUTBOX_MESSAGES` in it is a CAP framework table. **No HANA-specific runtime defect was found.**

**Still not verified:** the supplier decision/update path against HANA — every write exercised was an INSERT, so the accept/reject UPDATE, the `responseVersion` increment, the `modifiedAt` update behaviour and `SupplierResponseDeliveries` persistence are untested; the interactive `SupplierPortalUser` identity and the `supplier` attribute mapping, which need an interactive login; and SAP's own OAuth2 client.

## SAP S/4 → CAP outbound configuration, runtime-verified

The S/4HANA development sandbox can call the deployed CAP application. This is the SAP side of the connection; it is a **technical outbound probe**, not the `sendToSupplier` business flow.

| Item | Value |
| --- | --- |
| Destination | **`ZJP_CAP`** → `/health/ping` |
| Destination | **`ZJP_CAP_INGEST`** → `/rest/integration/v1/Orders` |
| SSL client PSE | **ANONYM** |
| Trust list | **DigiCert TLS RSA4096 Root G5** imported — see the note below |
| OAuth2 client profile | **`ZJP_CAP_OAUTH`** |
| OAuth2 client configuration | **`ZJP_CAP_XSUAA`** |
| Grant type | Client Credentials |
| Client authentication | HTTP Basic / standard HTTP |
| Resource authentication | `Authorization` header |
| Token scopes observed | `<xsappname>.IntegrationClient`, `uaa.resource` |

**Certificate trust — record the fact, not a rule.** The first outbound handshake failed with **`SSSLERR_PEER_CERT_UNTRUSTED`**. The Cloud Foundry endpoint's chain required **DigiCert TLS RSA4096 Root G5**, and importing that root into the selected **ANONYM** PSE's trust list resolved the handshake. **Do not generalize this certificate requirement to unrelated environments**: it is the anchor this specific route's chain happened to need at this moment, and a different endpoint, a different landscape or a rotated chain requires its own answer rather than a copy of this one.

**Verified from SAP:** the `ZJP_CAP` connection test returned **401 before OAuth** — which proved DNS, network path, TLS and CAP reachability all at once, since only the application can produce a 401 — and **200 / OK** after OAuth was configured. ABAP code read `/health/ping` for **200** with `status UP`, `component cap-supplier-portal`. Through `ZJP_CAP_INGEST`, a `{}` body returned the portal's own **400 `SCHEMA_VERSION_UNSUPPORTED`**, and a valid hand-built delivery returned **201 RECEIVED**, then **200** on an exact replay with the same `portalOrderId` and `receivedAt`, then **409 `DELIVERY_PAYLOAD_CONFLICT`** for a changed payload under the same `deliveryId`.

**Not verified:** anything in the business outbound flow — no RAP purchase order is mapped into the DTO, `OrderRevision` is unpopulated, the `DeliveryId` and `IntegrationStatus` lifecycles are unimplemented, `sendToSupplier` does not exist, and no HTTP outcome is written back into RAP. No client secret or access token is recorded here.

**Cleanup debt in this space:** `pih-xsuaa-probe` (bound to nothing), the `runtime-test-key` service key, and the synthetic HANA rows above. The rows are kept deliberately rather than deleted: `DeliveryReceipts.order` is an association rather than a composition, so removing the order would orphan the receipt and the referential effect was not established, and removing the receipt would destroy the idempotency record and make that `deliveryId` re-ingestable. Both are identifiable by `supplierCode RTTEST001` and `sourceSystem PIH_RUNTIME_TEST`.

Keep credentials, service keys, tokens and tenant-specific secrets out of this repository — none are recorded here.

## CAP HANA production preparation, configured but not deployed

The first CAP cloud-deployment preparation step is done: the portal now selects its database by CAP profile — SQLite `:memory:` for local development, SAP HANA through `@cap-js/hana` for production — and `cds build --production` generates an HDI deployer module. **Nothing was deployed and no binding was created**, so this is a build-time and configuration fact only. Details and the verification evidence are in the [CAP README](../cap-supplier-portal/README.md#production-build-hana) and [PROJECT_STATUS.md](../PROJECT_STATUS.md).

Because `pih-hana` and `pih-hdi` now exist, deploying CAP to the BTP Cloud Foundry runtime is **the chosen Phase 5 connectivity path**, replacing the earlier suggestion of proving the round trip through a public tunnel first; a tunnel survives only as a fallback and debugging aid. The reasoning is recorded in the [Phase 5.1 guide](../abap-rap/docs/phase-5-1-outbound-foundation.md#13-the-two-permitted-development-options-compared). Choosing the path is not walking it: the application is **unbound and undeployed**, so there is still no CAP URL an SAP system could call, and Phase 5.1 blocker **B3 stays open**. *Superseded as a record of that moment: the application has since been deployed and bound, HANA ingestion is runtime-verified, and **the S/4 sandbox has now called the route** over HTTPS with OAuth2 — so **blocker B3 is resolved**. See the outbound-probe section below.* Deploying also does not by itself make the endpoint safe to expose, because the production build still carries mocked authentication; see the open findings recorded in [PROJECT_STATUS.md](../PROJECT_STATUS.md).

## Cost-aware sequencing

Do not activate all services in Phase 0. Confirm ABAP access first for Phase 1. CAP can be built locally when Phase 4 begins. Investigate connectivity before Phase 5; activate Cloud Integration when ready for Phase 6, and Event Mesh/API Management near their own phases. Export non-secret source and design artifacts regularly because temporary environments may expire.

If SAP access blocks a phase, document the blocker and the exact fallback evidence. Continue design/contract exercises within that phase; ask for a deliberate change of phase order before moving to a later implementation milestone.
