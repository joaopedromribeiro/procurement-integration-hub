# Phase 2.4B — SAP runtime evidence

Evidence date: 2026-09-13. Environment: learner's SAP S/4HANA study system with ABAP Cloud. Evidence source: learner-reported execution of `ZJP_CL_PO_EML_TEST`; the assistant did not independently connect to SAP.

## Verified outcomes

- Deep create produced Quantity 2 × NetPrice 750 = item TotalAmount 1500 in the RAP buffer before `COMMIT ENTITIES`.
- Updating Quantity to 3 recalculated item TotalAmount to 2250.
- Updating NetPrice to 800 recalculated item TotalAmount to 2400.
- The calculated values persisted correctly after each commit.
- Managed Status initialization, CRUD and cleanup checks continued to pass.

Reported final console line:

```text
PASS: item totals 1500/2250/2400; status, CRUD and cleanup.
```

This evidence completes Phase 2.4B. It does not establish header aggregation, validations, draft, actions, OData or integration behavior. Header aggregation is the separate [Phase 2.4C checkpoint](phase-2-4c-header-total-determination.md).
