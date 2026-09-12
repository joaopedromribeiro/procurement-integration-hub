# SAP technical references

Reviewed 2026-09-12. Primary sources inform platform capabilities; architecture choices such as status names, endpoint names, limits, timeouts and retry delays are project proposals. Verify actual release support and account entitlements at implementation time.

| Topic | Official source | Use in this design |
| --- | --- | --- |
| RAP overview | [ABAP RESTful Application Programming Model](https://help.sap.com/docs/abap-cloud/abap-rap/abap-restful-application-programming-model) | RAP business services and OData exposure |
| RAP transaction rules | [General RAP BO implementation contract](https://help.sap.com/docs/abap-cloud/abap-rap/general-rap-bo-implementation-contract) | Framework-controlled transactions and response handling |
| RAP draft | [Draft](https://help.sap.com/docs/ABAP_PLATFORM_NEW/fc4c71aa50014fd1b43721701471913d/a81081f76c904b878443bcdaf7a4eb10.html) | Technical draft support |
| RAP events | [Develop business events](https://help.sap.com/docs/abap-cloud/abap-rap/develop-business-events) | Planned BO events and later binding work |
| ABAP trial | [Create an SAP BTP ABAP Environment trial user](https://developers.sap.com/tutorials/abap-environment-trial-onboarding.html) | Possible learning-system access, subject to availability |
| CAP TypeScript | [Using TypeScript](https://cap.cloud.sap/docs/node.js/typescript) | Typed handlers and development/build workflow |
| CAP protocols | [Serving provided services](https://cap.cloud.sap/docs/node.js/cds-serve) | Native REST/OData adapters and configurable service paths |
| CAP production | [Deploy to Cloud Foundry](https://cap.cloud.sap/docs/guides/deploy/to-cf) | SQLite development and HANA/auth production preparation |
| CAP security | [Authentication](https://cap.cloud.sap/docs/node.js/authentication) | Mock users, token-based authentication and XSUAA |
| CI HTTP | [HTTP receiver adapter](https://help.sap.com/docs/integration-suite/sap-integration-suite/http-receiver-adapter) | HTTP transport for REST receiver calls |
| CI errors | [Define Exception Subprocess](https://help.sap.com/docs/cloud-integration/sap-cloud-integration/define-exception-subprocess) | Error processing behavior |
| BTP access | [Trial accounts and free tier](https://help.sap.com/docs/btp/sap-business-technology-platform/trial-accounts-and-free-tier) | Account distinction and changing service conditions |
| Event Mesh capability | [Initiating the message broker](https://help.sap.com/docs/integration-suite/sap-integration-suite/initiating-event-mesh) | Capability activation and broker setup |
| Messaging offerings | [Activating Event Mesh bridge](https://help.sap.com/docs/integration-suite/sap-integration-suite/activating-event-mesh-bridge) | Distinguishes Event Mesh capability and advanced event mesh prerequisites |
| API Management | [Activate and configure API Management](https://help.sap.com/docs/integration-suite/sap-integration-suite/enabling-api-management-capability-from-integration-suite) | Later capability provisioning |

Links describe SAP products rather than guaranteeing this user's access. No external repository code or tutorial implementation has been copied into this foundation.
