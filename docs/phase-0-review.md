# Phase 0 review and expected results

This is a design walkthrough, not a runtime test. It requires only the documents. Stop after this phase; no ABAP or CAP implementation is required for the exercise.

## What was built and why

The repository defines business ownership, a composed order model, independent API contracts, synchronous HTTP exchanges, and a later messaging extension. It makes transaction failures visible before they become implementation surprises. The initial artifact is the architecture itself; runtime code starts in Phase 1.

Read [README](../README.md), [architecture](../ARCHITECTURE.md), [domain model](architecture/domain-model.md), [API contracts](../API_CONTRACTS.md), then [environments](environments.md).

## Walkthrough A: normal order

1. Create a technical draft with supplier SUP001 and two laptops at EUR 750.0000 each. Expected: draft persistence is editable; no portal order exists.
2. Activate. Expected: an active RAP order can still have business status DRAFT; item/header amount is EUR 1500.00.
3. Submit, then approve. Expected: SUBMITTED → APPROVED; commercial data is frozen. Approving a DRAFT order must fail.
4. Request send. Expected: business status stays APPROVED, integration state becomes PENDING, and an immutable delivery ID/snapshot is committed.
5. Dispatch through CI. Expected mapping: source items become lines, EA becomes PCE, amounts stay exact strings, organizational codes stay within SAP.
6. CAP commits and returns RECEIVED. Expected: SAP becomes SENT only after receipt processing.
7. Supplier accepts with an estimated date. Expected: CAP becomes ACCEPTED; a separate response request changes RAP to CONFIRMED and copies the date.

## Walkthrough B: failures and race conditions

| Scenario | Expected reasoning |
| --- | --- |
| Submit zero items | Rejected before submission; no dispatch |
| Quantity 0 or negative price | Validation failure; no valid submitted order |
| Portal times out after saving | SAP ERROR/UNKNOWN; same delivery replay returns receipt, not a second order |
| Supplier accepts before SAP records SENT | Matching dispatched intent permits direct CONFIRMED; later receipt does not regress it |
| Supplier decision saved but SAP unavailable | CAP preserves decision and pending response; retries same response ID |
| Same response replayed | ALREADY_APPLIED; unchanged date/status |
| Changed payload reuses delivery ID | 409 conflict; existing order untouched |
| Supplier rejects | Successful callback, RAP REJECTED with origin SUPPLIER |
| Approver rejects | RAP REJECTED with origin APPROVER; no CAP order exists |
| Cancel after delivery requested | Disallowed in v1, including unknown timeout outcomes |

## Walkthrough C: arithmetic

First line: 2 × 750.0000 = 1500.00. Second line: 3 × 0.3350 = 1.0050, rounded half up to 1.01. Expected header: EUR 1501.01. Rounding lines before summing avoids mismatches between displayed line totals and header total.

## Environment exercise

Identify the ABAP system product/release and whether you can create ABAP Cloud development objects. This is the next environment fact needed, not a request to activate every BTP service. If no system is available, ABAP source can be studied locally but activation and RAP tests remain unverified.

## Phase 0 acceptance

- The order has exactly one owner for each category of business data.
- Technical drafts, business status and integration status have distinct meanings.
- The mapping changes structure and units while preserving identity and money.
- Human supplier response is a separate transaction from order delivery.
- Duplicate requests, timeouts and late receipts have explicit outcomes.
- Every SAP service has an access requirement and an honestly labeled fallback.
- All technology implementation claims remain planned until evidence exists.

Document any change to these decisions before it affects code. The learner has confirmed Phase 0 complete and subsequently reported successful Phase 1 activation. This document remains the historical architecture exercise; it does not establish later transactional or integration execution results.
