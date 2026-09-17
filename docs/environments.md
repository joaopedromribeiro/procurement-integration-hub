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
| Direct HTTP / phase 5 | Released ABAP outbound HTTP APIs, supported communication setup, reachable CAP URL; reverse access to RAP Web API | Local CAP and contract test clients; explicitly labeled RAP stub if SAP is unavailable | Actual SAP connectivity and RAP runtime behavior |
| Cloud Integration / phase 6 | Integration Suite subscription/entitlement with Cloud Integration capability, developer/deployer and monitoring permissions | Mapping fixtures and a local Node.js integration simulator created in the relevant phase | iFlow deployment, adapters, graphical mapping runtime, message processing logs |
| OAuth / phase 8 | Identity provider, OAuth clients, XSUAA where chosen, roles/scopes and CAP service bindings | CAP mock users; later a local OAuth test issuer if useful | XSUAA provisioning, real trust/audience configuration and platform login |
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
| BTP account type, region, Cloud Foundry quota | Unknown |
| Integration Suite capabilities and roles | Unknown |
| HANA Cloud / HDI access | Unknown; optional until cloud database deployment |
| Event Mesh product and entitlement | Unknown; Phase 9 decision |
| XSUAA / identity provider / destination access | Unknown |
| GitHub remote | origin points to [procurement-integration-hub](https://github.com/joaopedromribeiro/procurement-integration-hub); main tracks origin/main, confirmed from local Git configuration |

Record non-secret environment facts here when available. Keep credentials, service keys, tokens, tenant-specific sensitive configuration and private destinations outside the repository.

## Cost-aware sequencing

Do not activate all services in Phase 0. Confirm ABAP access first for Phase 1. CAP can be built locally when Phase 4 begins. Investigate connectivity before Phase 5; activate Cloud Integration when ready for Phase 6, and Event Mesh/API Management near their own phases. Export non-secret source and design artifacts regularly because temporary environments may expire.

If SAP access blocks a phase, document the blocker and the exact fallback evidence. Continue design/contract exercises within that phase; ask for a deliberate change of phase order before moving to a later implementation milestone.
