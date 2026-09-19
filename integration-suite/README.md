# Integration Suite

**Phase 6.1 is SAP Integration Suite runtime-verified.** `PIH_OrderDelivery_v1` is built and deployed in the dedicated `PIH Integration` subaccount, and a real HTTPS request was converted, validated against the source contract and answered with the caller’s own correlation ID; an invalid `schemaVersion` was rejected by the schema and shows as **Failed** in monitoring. See [the Phase 6 guide](docs/phase-6-cloud-integration.md).

**No exported iFlow artifact is in this repository yet.** The deployed artifact lives in the tenant; `iflows/PIH_OrderDelivery_v1/` is still empty and must be filled by a manual export from Integration Suite. The XSDs and payload fixtures here are repository-authored and are not SAP exports.

Phase 6.2, mapping parity, is designed and not built. Phase 6.3 onward remain planned.

- `iflows/`: Actual exported Cloud Integration artifacts when available. **Still empty** — `PIH_OrderDelivery_v1` is deployed in the tenant but has not been exported here.
- `mappings/`: Source/target XSDs, field/value mapping specifications and fixtures. Holds the runtime-verified source contract `pih-order-delivery-source-v1.xsd` (a repository copy, not a byte-level export) and the **proposed, undeployed** target contract `pih-cap-order-target-v1.xsd`.
- `groovy/`: Reserved; scripts require a specific documented need.
- `payloads/`: Valid/invalid request and response fixtures derived from the [contracts](../API_CONTRACTS.md). Includes the Phase 6.1 valid and invalid source payloads, the `VALIDATED` stand-in response, and `cap-order-target-golden-v1.json` — the byte-exact Phase 5 ABAP mapper output that serves as the **parity oracle** for Phase 6.2.
- `docs/`: Adapter settings, deployment steps, Exception Subprocess design and monitoring evidence.

Use standard components first. A local integration simulator, if required later, must be labeled and cannot serve as evidence of deployed Cloud Integration experience. See [target flow](../ARCHITECTURE.md#cloud-integration-design).
