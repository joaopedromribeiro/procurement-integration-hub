# Integration Suite

**Phase 6.1 and Phase 6.2 are both SAP Integration Suite runtime-verified.** `PIH_OrderDelivery_v1` is built and deployed in the dedicated `PIH Integration` subaccount, and a real HTTPS request was converted, validated against the source contract and answered with the caller’s own correlation ID; an invalid `schemaVersion` was rejected by the schema and shows as **Failed** in monitoring. See [the Phase 6 guide](docs/phase-6-cloud-integration.md).

**Phase 6.2 added the Graphical Message Mapping**, reaching semantic parity with the Phase 5 ABAP mapper on a one-item and a two-item payload, with `EA` becoming `PCE`, the header currency replicated per line, SAP-internal fields excluded and **no Groovy**. Reaching the flow at all first required **disabling CSRF protection** on the HTTPS Sender: with it enabled an authenticated service-key POST was rejected `HTTP 403` and created no Message Processing Log, which placed the rejection at the endpoint boundary rather than in the iFlow. Authentication itself was never at fault. **`CSRF Protected = disabled` is the current runtime configuration and not a declared production posture** — the final inbound posture is an open decision.

The target contract is an **OpenAPI 3.0.3 document**, not the XSD originally proposed. That declaration was half of the answer to JSON numeric typing and array handling; the other half was mapping-side — *Basic Data Type Handling* set to the target schema types, and an explicit `items` → `lines` structure mapping. No script was needed for either.

**The files under `mappings/` are extracted from a real SAP export** and are no longer hand-derived. The export archive itself is not yet committed under `iflows/`.

Phase 6.3, the CAP receiver call, is not built. SAP still posts directly to CAP.

- `iflows/`: Actual exported Cloud Integration artifacts when available. The `PIH_OrderDelivery_v1` export is **not committed yet**; the deployed artifacts it carries are present under `mappings/`.
- `mappings/`: Source/target XSDs, field/value mapping specifications and fixtures. All three files are **extracted from the exported iFlow** and are therefore the deployed artifacts: the source contract `pih-order-delivery-source-v1.xsd`, the OpenAPI target contract `pih-cap-order-target-v1.openapi.json`, and the graphical mapping `PIH_OrderDelivery_to_CAP_Order_v1.mmap`.
- `groovy/`: Reserved; scripts require a specific documented need.
- `payloads/`: Valid/invalid request and response fixtures derived from the [contracts](../API_CONTRACTS.md). Includes the Phase 6.1 valid and invalid source payloads, the `VALIDATED` stand-in response, `cap-order-target-golden-v1.json` — the byte-exact Phase 5 ABAP mapper output that is the **parity oracle** — and the two-item pair used to prove that `lines` really is an array.
- `docs/`: Adapter settings, deployment steps, Exception Subprocess design and monitoring evidence.

Use standard components first. A local integration simulator, if required later, must be labeled and cannot serve as evidence of deployed Cloud Integration experience. See [target flow](../ARCHITECTURE.md#cloud-integration-design).
