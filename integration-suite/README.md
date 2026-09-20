# Integration Suite

**Phases 6.1, 6.2, 6.3 and 6.4 are all runtime-verified, and SAP is cut over. Phase 6 is not complete** — 6.5 has not started. `PIH_OrderDelivery_v1` is built and deployed in the dedicated `PIH Integration` subaccount, and a real HTTPS request was converted, validated against the source contract and answered with the caller’s own correlation ID; an invalid `schemaVersion` was rejected by the schema and shows as **Failed** in monitoring. See [the Phase 6 guide](docs/phase-6-cloud-integration.md).

**Phase 6.2 added the Graphical Message Mapping**, reaching semantic parity with the Phase 5 ABAP mapper on a one-item and a two-item payload, with `EA` becoming `PCE`, the header currency replicated per line, SAP-internal fields excluded and **no Groovy**. Reaching the flow at all first required **disabling CSRF protection** on the HTTPS Sender: with it enabled an authenticated service-key POST was rejected `HTTP 403` and created no Message Processing Log, which placed the rejection at the endpoint boundary rather than in the iFlow. Authentication itself was never at fault. **`CSRF Protected = disabled` is the current runtime configuration and not a declared production posture** — the final inbound posture is an open decision.

The target contract is an **OpenAPI 3.0.3 document**, not the XSD originally proposed. That declaration was half of the answer to JSON numeric typing and array handling; the other half was mapping-side — *Basic Data Type Handling* set to the target schema types, and an explicit `items` → `lines` structure mapping. No script was needed for either.

**The exported iFlow is now in the repository** as `iflows/PIH_OrderDelivery_v1.zip`, a real SAP export. The files under `mappings/` are extracted from it and are no longer hand-derived.

**Phase 6.3 added the CAP call**: a Request Reply step to the `CAP_Supplier_Portal` HTTP receiver over OAuth 2.0 client credentials (Security Material alias `PIH_CAP_OAUTH`), returning CAP's receipt unchanged, plus an Exception Subprocess. Verified with a `201` create, a `200` idempotent replay, a real `409` conflict preserved end to end, and a controlled `502` for a forced technical failure. Because **`Throw Exception on Failure` is OFF**, CAP's own status codes and error bodies survive the hop instead of collapsing into a generic `500`.

**Phase 6.4 cut SAP over.** The ABAP post-commit coordinator posts the persisted delivery snapshot **verbatim** to this iFlow over destination `ZJP_CI_ORDER_DELIVERY`, so Cloud Integration owns mapping on the active production path. Verified with a real `201`, a real `200` replay of the exact snapshot returning the same `portalOrderId`, and a real `409 DELIVERY_PAYLOAD_CONFLICT` for changed content under the same delivery id. Phase 5's direct SAP-to-CAP path survives intact as the fallback and parity reference.

**Phase 6.5, the inbound supplier response `PIH_SupplierResponse_v1`, is NOT STARTED** and is the only subphase left in Phase 6.

- `iflows/`: Actual exported Cloud Integration artifacts when available. Holds `PIH_OrderDelivery_v1.zip`, exported from the tenant and containing the deployed `.iflw`, the source XSD, the OpenAPI target and the `.mmap` mapping.
- `mappings/`: Source/target XSDs, field/value mapping specifications and fixtures. All three files are **extracted from the exported iFlow** and are therefore the deployed artifacts: the source contract `pih-order-delivery-source-v1.xsd`, the OpenAPI target contract `pih-cap-order-target-v1.openapi.json`, and the graphical mapping `PIH_OrderDelivery_to_CAP_Order_v1.mmap`.
- `groovy/`: Reserved; scripts require a specific documented need.
- `payloads/`: Valid/invalid request and response fixtures derived from the [contracts](../API_CONTRACTS.md). Includes the Phase 6.1 valid and invalid source payloads, the `VALIDATED` stand-in response (superseded in 6.3 by CAP's real receipt), `cap-order-target-golden-v1.json` — the byte-exact Phase 5 ABAP mapper output that is the **parity oracle** — the two-item pair used to prove that `lines` really is an array, and the three Phase 6.3 runtime bodies: the `201`/`200` receipt, the `409` conflict and the `502` technical error.
- `docs/`: Adapter settings, deployment steps, Exception Subprocess design and monitoring evidence.

Use standard components first. A local integration simulator, if required later, must be labeled and cannot serve as evidence of deployed Cloud Integration experience. See [target flow](../ARCHITECTURE.md#cloud-integration-design).
