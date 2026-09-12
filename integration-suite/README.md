# Integration Suite

Planned for Phase 6. No iFlows have been built, exported or deployed.

- `iflows/`: Actual exported Cloud Integration artifacts when available.
- `mappings/`: Source/target XSDs, field/value mapping specifications and fixtures.
- `groovy/`: Reserved; scripts require a specific documented need.
- `payloads/`: Valid/invalid request and response fixtures derived from the [contracts](../API_CONTRACTS.md).
- `docs/`: Adapter settings, deployment steps, Exception Subprocess design and monitoring evidence.

Use standard components first. A local integration simulator, if required later, must be labeled and cannot serve as evidence of deployed Cloud Integration experience. See [target flow](../ARCHITECTURE.md#cloud-integration-design).
