# CAP Supplier Portal

Planned for Phase 4. No package manifest, CDS definitions or business handlers have been generated.

- `db/`: Suppliers, Orders and composed OrderItems; synthetic fixtures.
- `srv/`: Separate integration and supplier services with TypeScript handlers.
- `app/`: Minimal supplier interface to list orders, inspect items and submit decisions.
- `test/`: Meaningful handler/API tests, then supplier-isolation and integration tests.

Use real CAP with SQLite locally. Select compatible supported Node.js/CAP/TypeScript versions and commit the lockfile when implementation starts. HANA Cloud compatibility must later be verified on HANA. Business rules and API boundaries are in [architecture](../ARCHITECTURE.md) and [contracts](../API_CONTRACTS.md).
