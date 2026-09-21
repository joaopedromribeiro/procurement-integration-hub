# Phase 7 — Error Handling, Monitoring & Operational Resilience

Phase 7 makes the bidirectional integration proven in Phase 6 operationally robust under real failure conditions. It adds no new integration product, no new architectural layer and no new authentication model: Event Mesh remains Phase 9 and API Management remains Phase 10, per the committed roadmap in [README.md](../README.md#project-roadmap). Every Phase 6 durable flow stays exactly as it is and is hardened in place.

**Subphase 7.1 is frozen design. No executable source was changed by it.** This document is that freeze: the fault model, the four failure categories, the CSRF investigation, the timeout reconciliation, and the terminology and direction decisions that subphases 7.2 through 7.9 must hold to.

| Subphase | Objective | State |
| --- | --- | --- |
| **7.1** | Fault model and acceptance criteria | **frozen — this document** |
| 7.2 | Real `UNKNOWN` and reconciliation, on the deployed droplet | designed, not executed |
| 7.3 | Attempt history | designed, not implemented |
| 7.4 | Retry / transient failure policy | designed, not implemented |
| 7.5 | Inbound concurrency hardening | designed, not implemented |
| 7.6 | Outbound recovery parity / `retryDelivery` | designed, not implemented |
| 7.7 | Monitoring and correlation | designed, not implemented |
| 7.8 | Operational runbook | designed, not written |
| 7.9 | Runtime resilience tests and closure | not started |

## 7.1 scope

What this subphase does: freeze the two-direction fault matrix with an explicit evidence level on every row; separate four failure categories that the current implementation partly conflates; investigate the inbound CSRF failure path from the committed artifacts; reconcile the documented timeout budgets against the values actually in the source and the exported iFlows; and freeze the terminology and the direction of 7.3 to 7.6.

What this subphase deliberately does not do: change any constant, any classifier, any schema, any iFlow or any ABAP object. Several defects are named below and **none of them is fixed here**. That separation is the point — a fault model written after the code was adjusted to match it proves nothing.

## Failure categories

The single most important correction this subphase makes to the Phase 6 implementation is that **"no HTTP answer" is not one condition**. The current code on both legs collapses every unanswered outcome into `UNKNOWN`, which is the state reserved for genuine ambiguity. That over-classification is safe — it costs a replay, and both receivers are runtime-proven idempotent — but it is semantically wrong, and it sends an operator to a reconciliation command for conditions that only need a cause fixed.

Phase 7 recognises **four** categories. They are distinguished by one question asked before any other: *could the receiver have committed the business request?*

### A. Pre-send / no-delivery failure

The business request provably never left the caller. Examples: DNS resolution failure; connection refused before the request was transmitted; a TLS handshake failure before transmission; and — on the inbound leg — a CSRF token fetch that fails before the `applySupplierResponse` POST is attempted.

- The receiver **could not** have committed. There is nothing to reconcile.
- **Deterministic no-delivery.** Not ambiguous, despite producing no HTTP answer.
- **Retry-eligible once the cause is resolved**, under the same business identity.
- **Durable state: `PENDING`.** No fifth state is introduced. `PENDING` already carries exactly this meaning — not delivered, still eligible — and `attempts` is what separates "never attempted" from "attempted and retryable", exactly as the outbound coordinator reasons when it returns a retryable intent to `PENDING` rather than inventing a new value.
- It must **not** require business reconciliation merely because the current implementation reports it as `UNKNOWN`.

### B. Deterministic HTTP refusal

The receiver answered, and the answer is a refusal that an unchanged replay would earn again: `400`, `401`, `403`, `404`, `409`, `412`, `413`.

- The receiver **did not** commit, and said so.
- **Deterministic.** **Not retry-eligible.**
- **Durable state: `FAILED`.** Operator fixes the cause; if the fix is a different business answer, that is a new decision at a new version, never an edit of this row.

### C. Deterministic transient response

The receiver answered, and the answer says "not now": `429`, `502`, `503`.

- The receiver **did not** commit.
- **Deterministic about the outcome, transient about the cause.** **Retry-eligible** under a bounded budget.
- **Durable state: `PENDING`.** Same state as category A, reached by a different route, and correctly so: both mean not delivered and still eligible.

### D. Ambiguous post-send / no-answer failure

The request was dispatched and the outcome cannot be established. Examples: a client timeout after transmission; a connection lost after the request was written; `500` or `504`; any HTTP or proxy failure where a receiver commit cannot be ruled out.

- The receiver **may** have committed.
- **Ambiguous.**
- **Never automatically replayed**, whatever the budget says.
- **Durable state: `UNKNOWN`.** Resolved only by explicit operator reconciliation, replaying the same business identity through the same mediated transport.

### Where the current implementation cannot tell A from D

The distinction above is a semantic one. Whether the code can *observe* it is a separate question, and the honest answer differs by leg and by error kind. This is recorded as a limitation, not designed around.

**Inbound (CAP → CI → SAP), [`ci-transport.ts`](../cap-supplier-portal/srv/lib/ci-transport.ts).** The catch block returns `{ answered: false, detail }` for everything and inspects only `error.name`, distinguishing `TimeoutError`/`AbortError` in the **message text alone**. It does not inspect `error.cause.code`, which is where Node places the discriminator for a failed `fetch`. The information therefore **exists and is discarded**:

| Node cause | Category | Currently |
| --- | --- | --- |
| `ENOTFOUND` (DNS) | **A** — not sent | `UNKNOWN` |
| `ECONNREFUSED` | **A** — not sent | `UNKNOWN` |
| TLS handshake failures (`ERR_TLS_*`, `CERT_*`) | **A** — not sent | `UNKNOWN` |
| `ECONNRESET` | **D** — may have applied; the reset can follow transmission | `UNKNOWN` (correct) |
| `TimeoutError` / `AbortError` | **D** — cannot be told apart; the abort may follow transmission | `UNKNOWN` (correct) |

So three of five inbound sub-cases are recoverable in 7.4 by reading `error.cause.code`, and two genuinely cannot be improved. A client timeout is irreducibly ambiguous: the socket aborted, and nothing observable on the client says whether the bytes had already reached the receiver.

**Outbound (SAP → CI → CAP), [`zjp_cl_outbound_transport`](../abap-rap/classes/zjp_cl_outbound_transport.clas.abap).** The exception handling already **states** the distinction in a comment and then discards it at the seam:

| ABAP exception | Comment in source | Category | Currently |
| --- | --- | --- | --- |
| `cx_outbound_provider_http` | *"The destination could not be resolved. Nothing was sent."* | **A** — not sent, and the source says so | `UNKNOWN` |
| `cx_web_http_client_error` | *"Client creation or execution failed: connect, TLS or timeout."* | **A or D — conflated in one exception** | `UNKNOWN` |
| `cx_web_message_error` | deliberately conservative over-classification | **D** by choice | `UNKNOWN` (intended) |

`cx_outbound_provider_http` is the clearest case in either leg: the code has already concluded nothing was sent and then reports the result as unanswered, which `classify` reads as ambiguous. `cx_web_http_client_error` covers connect, TLS and timeout in a single exception class, so splitting it needs a finer signal than the exception type alone — **an open question recorded below, not a gap to be papered over.**

**A category-A condition on either leg is therefore currently reported as `UNKNOWN` in every case.** The intended Phase 7 behaviour is that the transport result carries a delivery-certainty discriminator alongside `answered`, and `classify` maps a provably-unsent result to `PENDING`. That is 7.4's work and is not implemented here.

## Fault matrix — outbound, SAP → CI → CAP

Classification is [`zjp_cl_dispatch_coordinator=>classify`](../abap-rap/classes/zjp_cl_dispatch_coordinator.clas.abap). Delivery certainty: **NOT-SENT** / **ANSWERED** / **MAY-APPLY**. Category letters are the four above.

| Condition | Certainty | Cat. | D/A | Retry eligibility | Operator action | Durable state |
| --- | --- | --- | --- | --- | --- | --- |
| DNS resolution failure | **NOT-SENT** | A | D | eligible once resolved | fix destination/DNS | `PENDING` |
| Connection refused pre-transmission | **NOT-SENT** | A | D | eligible once resolved | fix endpoint/availability | `PENDING` |
| TLS handshake failure pre-transmission | **NOT-SENT** | A | D | eligible once resolved | fix trust/certificate | `PENDING` |
| Timeout before receiver commit | MAY-APPLY | D | A | none | reconcile | `UNKNOWN` |
| Timeout after receiver may have committed | MAY-APPLY | D | A | none | **reconcile — no command exists** | `UNKNOWN` |
| Connection lost after transmission | MAY-APPLY | D | A | none | reconcile | `UNKNOWN` |
| `400` malformed / invalid | ANSWERED | B | D | none | correct source or mapping | `FAILED` |
| `401` | ANSWERED | B | D | none | fix credentials; no credential loop | `FAILED` |
| `403` | ANSWERED | B | D | none | fix role or scope | `FAILED` |
| `404` | ANSWERED | B | D | none | fix routing or identity | `FAILED` |
| `409` identity reuse / conflict | ANSWERED | B | D | none | reconcile identity; never blind replay | `FAILED` |
| `412` stale precondition | ANSWERED | B | D | none | reread and reassess | `FAILED` |
| `413` too large | ANSWERED | B | D | none | reduce or correct request | `FAILED` |
| `429` throttling | ANSWERED | C | D | **eligible, bounded** | investigate if budget exhausts | `PENDING` |
| `500` | ANSWERED | D | A | none | reconcile | `UNKNOWN` |
| `502` upstream unavailable | ANSWERED | C | D | **eligible, bounded** | investigate upstream | `PENDING` |
| `503` service unavailable | ANSWERED | C | D | **eligible, bounded** | investigate upstream | `PENDING` |
| `504` gateway timeout | MAY-APPLY | D | A | none | reconcile | `UNKNOWN` |
| Malformed receipt body | ANSWERED | D | A | none | reconcile; receipt unreadable | `UNKNOWN` |
| Duplicate delivery, same `deliveryId`, same content | ANSWERED | — | D | n/a — **success** | none | `DELIVERED` |
| Concurrent delivery attempts | — | — | D | n/a | none — lease decides | unchanged |

`business_status_for` maps `DELIVERED` to RAP `SENT`, and **both `FAILED` and `UNKNOWN` to RAP `ERROR`**; a `PENDING` outcome leaves the business status untouched. The purchase-order header therefore cannot distinguish a deterministic refusal from an ambiguous outcome, and only `ZJP_PO_DLV.dispatch_state` can. That is intended behaviour and a runbook rule, not a defect.

### Outbound — current behaviour, intended behaviour, evidence

| Condition | Current implementation | Intended Phase 7 | Evidence level | Runtime proof missing |
| --- | --- | --- | --- | --- |
| DNS failure | `UNKNOWN` (`cx_outbound_provider_http` → unanswered) | **`PENDING`**, category A | **source-only** | the condition itself, and the reclassification |
| Connection refused | `UNKNOWN` (`cx_web_http_client_error`) | `PENDING` **if separable** — see open question OQ-1 | **source-only** | separability, then the condition |
| TLS handshake failure | `UNKNOWN` (`cx_web_http_client_error`) | `PENDING` **if separable** — OQ-1 | **source-only** | separability, then the condition |
| Timeout, either kind | `UNKNOWN` | `UNKNOWN` — unchanged, correct | **source-only** | the condition |
| `400` | `FAILED` | unchanged | **runtime-verified** (6.3, this boundary) | — |
| `401` / `403` | `FAILED` | unchanged | **source-only**; auth proven only positively in 6.3 | the negative case |
| `404` | `FAILED` **via the `WHEN OTHERS` `< 500` default** | unchanged answer, **explicit `WHEN` clause** | **source-only** | the condition |
| `409` | `FAILED` | unchanged | **runtime-verified** (6.3) | — |
| `412` | `FAILED` **via default** | unchanged answer, **explicit clause** | **source-only** | the condition |
| `413` | `FAILED` | unchanged | **source-only** | the condition |
| `429` | `PENDING`, no budget | `PENDING` + bounded budget + `attempt_count` | **source-only** | the condition and the budget |
| `500` | `UNKNOWN` | unchanged | **source-only** | the condition |
| `502` | `PENDING` | `PENDING` + bounded budget | **runtime-verified** (6.3/6.4, controlled `502`) | the budget |
| `503` | `PENDING` | `PENDING` + bounded budget | **source-only** | the condition |
| `504` | `UNKNOWN` **via the `>= 500` default** | unchanged answer, **explicit clause** | **source-only** | the condition |
| Malformed receipt | `UNKNOWN` (`read_receipt` catch-all) | unchanged | **source-only** | the condition |
| Duplicate, identical | `DELIVERED` — CAP answers `200` with the original receipt | unchanged | **runtime-verified** (4.3, 6.3) | — |
| Concurrent attempts | lease + post-commit ownership re-read | unchanged; **prove it** | **source-only** | **multi-runner runtime proof** |

**`404`, `412` and `504` reach the right answer only through `WHEN OTHERS`.** The contract names all three explicitly and the inbound classifier enumerates all three; the outbound classifier derives them from its `>= 500` split. The answers agree today. The risk is structural: an edit to the default silently reclassifies three codes that the contract states by hand. 7.4 makes them explicit clauses without changing any outcome.

## Fault matrix — inbound, CAP → CI → SAP

Classification is [`classify`](../cap-supplier-portal/srv/lib/supplier-response.ts) in `supplier-response.ts`.

| Condition | Certainty | Cat. | D/A | Retry eligibility | Operator action | Durable state |
| --- | --- | --- | --- | --- | --- | --- |
| Any `2xx` | ANSWERED | — | D | n/a | none | `DELIVERED` |
| DNS resolution failure | **NOT-SENT** | A | D | eligible once resolved | fix configuration | `PENDING` |
| Connection refused pre-transmission | **NOT-SENT** | A | D | eligible once resolved | fix endpoint | `PENDING` |
| TLS handshake failure pre-transmission | **NOT-SENT** | A | D | eligible once resolved | fix trust | `PENDING` |
| **CSRF fetch failure** | **NOT-SENT** | **A** | **D** | eligible once resolved | **fix credentials — not reconcile** | `PENDING` |
| Client timeout after dispatch | MAY-APPLY | D | A | none | reconcile | `UNKNOWN` |
| Connection reset after transmission | MAY-APPLY | D | A | none | reconcile | `UNKNOWN` |
| `400` | ANSWERED | B | D | none | correct payload or state | `FAILED` |
| `401` / `403` | ANSWERED | B | D | none | fix credentials, role or scope | `FAILED` |
| `404` | ANSWERED | B | D | none | fix routing or identity | `FAILED` |
| `409` | ANSWERED | B | D | none | reconcile identity | `FAILED` |
| `412` | ANSWERED | B | D | none | reread and reassess | `FAILED` |
| `413` | ANSWERED | B | D | none | reduce request | `FAILED` |
| `429` | ANSWERED | C | D | **eligible, bounded** | investigate if exhausted | `PENDING` |
| `500` | ANSWERED | D | A | none | reconcile | `UNKNOWN` |
| `502` / `503` | ANSWERED | C | D | **eligible, bounded** | investigate upstream | `PENDING` |
| `504` | MAY-APPLY | D | A | none | reconcile | `UNKNOWN` |
| Malformed payload built by CAP | **NOT-SENT** | A | D | n/a — never dispatched | fix the decision data | row untouched, `PayloadError` |
| Duplicate response, same `responseId`, same content | ANSWERED | — | D | n/a — **success** | none | `DELIVERED` |
| Duplicate response, same `responseId`, different content | ANSWERED | B | D | none | **never replay** — source defect | `FAILED` |
| Concurrent flush runners | — | — | A | n/a | none | compare-and-set decides |

### Inbound — current behaviour, intended behaviour, evidence

| Condition | Current implementation | Intended Phase 7 | Evidence level | Runtime proof missing |
| --- | --- | --- | --- | --- |
| Any `2xx` | `DELIVERED` | unchanged | **runtime-verified** (6.5e, 6.5f) | — |
| DNS failure | `UNKNOWN` | **`PENDING`** via `error.cause.code` | **source-only** | the condition and the reclassification |
| Connection refused | `UNKNOWN` | **`PENDING`** via `ECONNREFUSED` | **source-only** | the condition and the reclassification |
| TLS handshake failure | `UNKNOWN` | **`PENDING`** via TLS cause codes | **source-only** | the condition and the reclassification |
| **CSRF fetch failure** | **`UNKNOWN`** — semantically wrong | **`PENDING`**, requires a CI change — see OQ-2 | **inference** — see the investigation below | **the external status CI returns** |
| Client timeout | `UNKNOWN` | unchanged — irreducibly ambiguous | **automated-test** | **the condition — this is 7.2** |
| Connection reset after transmission | `UNKNOWN` | unchanged — correct | **automated-test** | the condition |
| `400` | `FAILED` | unchanged | **runtime-verified** (6.5f, conflicting replay, `SABP_BEHV/100`) | — |
| `401` / `403` | `FAILED` | unchanged | **automated-test**; 6.5c proved auth positively only | the negative case |
| `404` | `FAILED` | unchanged | **automated-test** | the condition |
| `409` | `FAILED` | unchanged | **automated-test** | the condition |
| `412` | `FAILED` | unchanged | **automated-test** | the condition |
| `413` | `FAILED` | unchanged | **automated-test** | the condition |
| `429` | `PENDING`, no budget | `PENDING` + bounded budget | **automated-test** | the condition and the budget |
| `500` | `UNKNOWN` | unchanged | **automated-test** | the condition |
| `502` / `503` | `PENDING`, no budget | `PENDING` + bounded budget | **automated-test** | the condition and the budget |
| `504` | `UNKNOWN` | unchanged | **automated-test** | the condition |
| Malformed CAP payload | `PayloadError`, never dispatched | unchanged | **automated-test** | — |
| Duplicate, identical | `DELIVERED` — RAP answers `204`, `LastChangedAt` unmoved | unchanged | **runtime-verified** (6.5f) | — |
| Duplicate, conflicting | `FAILED` — RAP answers `400` | unchanged | **runtime-verified** (6.5f, after the ADR-039 hardening) | — |
| Concurrent runners | compare-and-set on bookkeeping only; **no claim** | **bounded lease/claim**, 7.5 | **automated-test** | **multi-runner runtime proof** |

Evidence levels are used strictly. **runtime-verified** means SAP or deployed-Cloud-Foundry execution evidence supplied by the operator. **automated-test** means the suite drives the case through a fake transport — real evidence about the code, and not evidence about the deployed transport. **source-only** means the behaviour is readable in the source and has never been executed in any form. **inference** means it is deduced from a committed artifact and could be wrong.

## The inbound CSRF case

Investigated from the committed runtime export `integration-suite/iflows/PIH_SupplierResponse_v1.zip` and the CAP source. **The iFlow was not changed.**

### What the artifact shows

The integration process is a single linear sequence with no gateway, no branch and **no subprocess of any kind**:

```
StartEvent_2
  → CallActivity_5    Capture Request Context
  → CallActivity_8    Prepare RAP Supplier Response
  → CallActivity_699  Prepare CSRF Fetch
  → ServiceTask_702   Fetch SAP CSRF Token      ── MessageFlow_705 (GET)
  → CallActivity_706  Capture SAP CSRF Token
  → CallActivity_722  Build SAP Session Cookie
  → CallActivity_720  Prepare RAP Action POST
  → ServiceTask_716   Apply Supplier Response   ── MessageFlow_719 (POST)
  → EndEvent_2
```

Every `bpmn2:sequenceFlow` in the file forms that one chain. The element inventory contains **no `bpmn2:subProcess`**, so the inbound flow has **no Exception Subprocess** — unlike the outbound `PIH_OrderDelivery_v1`, which has one.

`MessageFlow_705`, the CSRF `GET`, keeps `throwExceptionOnFailure = true`. `MessageFlow_719`, the action `POST`, has it `false` under ADR-039, so a deterministic RAP refusal passes through as itself. `retryOnException` is `false` on both.

### Is the POST definitely not executed?

**Yes, and this is established from the artifact rather than inferred.** `ServiceTask_716` is reachable only through the chain `ServiceTask_702 → CallActivity_706 → CallActivity_722 → CallActivity_720 → ServiceTask_716`. There is no alternative path and no gateway that could route around `ServiceTask_702`. With `throwExceptionOnFailure = true` on its message flow, a failed CSRF fetch raises, and with no Exception Subprocess to catch it the process terminates. **`applySupplierResponse` is never invoked, so SAP cannot have applied the supplier's commercial response.**

This is a category-A pre-send failure by the strictest reading: the business request provably never left Cloud Integration.

### How Cloud Integration surfaces it externally today

**Inference, not verified.** With the exception unhandled, Cloud Integration fails the message and the synchronous HTTPS sender returns a CI-generated error to CAP. The expected status for an unhandled integration-flow exception is `500`. **The exact status and body have never been observed for this path**, and no committed artifact states them.

The 6.5f history makes this worth stating carefully rather than assuming: that phase proved Cloud Integration converting a deterministic downstream `400` into an external `500`, which is what produced ADR-039. The failure mode is the same shape — a CI-generated `5xx` standing in for something that was not ambiguous — but the mechanism is different, and one does not prove the other.

### How CAP classifies it

If CI answers `500`, `classify` returns **`UNKNOWN`**: the receiver answered, and `500` is in the ambiguous branch.

### Is that semantically wrong?

**Yes.** The row is marked ambiguous when the artifact proves it is deterministic. Three consequences follow, and they are the reason this matters more than a mislabelled column:

1. The row is **never auto-retried**, which is correct for real ambiguity and wrong here — the condition is retry-eligible as soon as credentials or trust are fixed.
2. The operator is sent to `reconcile-supplier-response`, a command that **replays the response through the same broken transport**. It will fail the same way. The operator's actual task is to fix a credential, not to reconcile a business outcome.
3. It pollutes the `UNKNOWN` population, which Phase 7 is trying to make meaningful enough that a single `UNKNOWN` row is worth investigating.

**The fix cannot be made in CAP.** CAP receives `500` and has no way to tell a CSRF-failure `500` from a SAP-applied-then-failed `500`; the distinguishing knowledge exists only inside the iFlow. Any correction is a Cloud Integration change — recorded as open question **OQ-2** below, and **not made in 7.1**.

## Timeout reconciliation

Values read from the current source and the committed exports. **No constant was changed.**

| Layer | Documented | Actual | Source |
| --- | --- | --- | --- |
| CAP receiver (ingestion) | **15 s** | **not configured** — no receiver timeout exists in CAP | [API_CONTRACTS.md](../API_CONTRACTS.md#error-policy) vs CAP source |
| CI processing | **25 s** | **`transactionTimeout` = 30 s** on both iFlows | exported `.iflw` |
| CI → receiver HTTP call | not documented | **`httpRequestTimeout` = 60 000 ms** on every receiver in both iFlows | exported `.iflw` |
| CI pooled connection idle | not documented | `pooledConnectionIdleTimeout` = 300 000 ms | exported `.iflw` |
| SAP coordinator request | **35 s** | **not set** — `i_timeout` left at the API default, deliberately | `zjp_cl_outbound_transport` |
| CAP sender request | **not documented** | **`DEFAULT_TIMEOUT_MS` = 30 000 ms**, overridable by `PIH_CI_TIMEOUT_MS` | `ci-transport.ts` |

### Exact inconsistencies

**TI-1 — the inner deadline is longer than the outer, inverting the contract's own rule.** API_CONTRACTS states *"give inner calls shorter deadlines than their callers."* The CAP sender waits **30 s**; the Cloud Integration receiver call it triggers is allowed **60 s**. The caller abandons the exchange while the inner call is still legitimately running, and the POST to SAP may complete afterwards. **This configuration manufactures ambiguous `UNKNOWN` rows by design**, and it means the 7.2 test reproduces a genuinely reachable production condition rather than an artificial one.

**TI-2 — Cloud Integration is internally inconsistent.** `transactionTimeout` is **30 s** while a single receiver call may take **60 s**. The inbound flow makes **two** sequential HTTP calls, so its worst case is roughly 120 s of receiver waiting inside a 30 s transaction.

**TI-3 — the documented CI processing budget does not match the artifact.** 25 s documented, 30 s configured.

**TI-4 — the coordinator's 35 s budget is not implemented.** `i_timeout` is left at the API default with an explicit comment that the repository has chosen no timeout policy. The effective outbound timeout is a platform default that no document records.

**TI-5 — the CAP sender's 30 s appears in no budget table.** It is the single most operationally significant timeout on the inbound leg and it is undocumented.

**TI-6 — the CAP receiver's 15 s budget does not exist.** No receiver-side timeout is configured in CAP; the figure is aspirational.

All six are recorded for **7.4**, which will decide the coherent set and change the constants. Nothing is adjusted here.

## Frozen decisions

### Retry-policy terminology

There is **no scheduler in Phase 7**. Nothing executes an attempt by itself when an interval elapses. The vocabulary is therefore **retry eligibility**, and every document and code comment in Phase 7 must use it:

> A transient `PENDING` row becomes **eligible** for another attempt after its backoff interval. A runner invocation performs the attempt **only if it is due**. Invocations before the due time skip it. A future scheduler could invoke the same runner without changing this logic.

Wording such as "retries after 5 s, 30 s and 120 s" is **forbidden** in Phase 7 material: it claims autonomous wall-clock behaviour the system does not have. The permitted phrasing is "becomes eligible after…" or "eligible on the next runner invocation".

| State | Policy |
| --- | --- |
| `DELIVERED` | **Terminal.** Never retried, never reconciled, never replayed. |
| `FAILED` | **Never retried unchanged.** The operator fixes the cause first. A different business answer is a new decision at a new version, never an edit of this row. |
| `UNKNOWN` | **Never automatically retried.** Explicit operator reconciliation only, replaying the same business identity. |
| `PENDING`, transient (categories A and C) | **Retry-eligible** under a bounded budget, evaluated by the drain query at invocation time. |

A budget that runs out adds **no fifth state**: the row stays `PENDING` with `attempts` at the maximum, is excluded by the drain query, and is surfaced separately by monitoring as retry-exhausted.

### Attempt history

**CAP — a `SupplierResponseDeliveryAttempts` child entity.** Fields: `attemptNumber`, `correlationId`, `startedAt`, `durationMs`, `outcome`, `httpStatus` (null when unanswered), `errorCategory` (closed vocabulary), `errorSummary`. Written in the same transaction as the winning compare-and-set, and **only** when that compare-and-set wins — an attempt row written by a losing runner would record an outcome that was discarded.

`completedAt` and `transportDirection` are deliberately excluded: the first duplicates `startedAt + durationMs`, and the second can only ever hold one value in a table that is CAP-to-SAP by construction.

The parent's `attempts`, `lastAttemptAt`, `lastError` and `lastCorrelationId` are **retained** as a denormalised fast path. They are already written by runtime-verified code and every existing query depends on them.

**SAP — `attempt_count` on `zjp_po_dlv`, and nothing else in Phase 7.** It is the field the bounded budget requires and that the coordinator's own comment records as deferred; `last_correlation_id` already exists for the lookup that matters. A full outbound attempt-history child object is **not** built unless 7.9 produces runtime evidence that an outbound diagnosis is genuinely unreachable without it.

### Observability identities

| Identity | Means | Changes on retry |
| --- | --- | --- |
| `deliveryId` | one SAP → CAP business **delivery** | **never** |
| `responseId` | one supplier **decision** | **never** |
| `X-Correlation-ID` | one transport **attempt** | **every attempt** |

These are never overloaded. A correlation ID is not a business key and is never stored as one; a business identity is never regenerated because a network call failed.

The trace reads in one direction: a business identity finds the durable row, the row's attempt history gives the correlation IDs, and a correlation ID finds the Cloud Integration message log.

**Both iFlows will expose `X-Correlation-ID` as an SAP Message Processing Log custom header property in 7.7.** Verified in 7.1: neither export configures `SAP_MessageProcessingLogCustomHeaderProperty` today, so the correlation ID travels through Cloud Integration but is not indexed and cannot be searched in Monitor — an operator must narrow by time window instead. The approved change is observability-only: no payload semantics, no routing, no retry behaviour, no authentication, and `retryOnException` stays `false`. After that runtime change the iFlows must be freshly exported and the repository artifacts updated.

### Concurrency direction

**Outbound: the existing lease is retained and is not redesigned.** `ZJP_PO_DLV` already carries `lease_owner` and `lease_expires_at`, `find_eligible` reclaims an expired lease, and `claim` re-reads the committed row afterwards so a lost race is visible rather than silent. **What is missing is proof**: no multi-runner execution has ever been performed. 7.9 supplies it.

**Inbound: 7.5 adds a bounded lease/claim built on the guarded compare-and-set already deployed.** An `IN_FLIGHT` state, `leaseOwner` and `leaseExpiresAt`; the claim is `UPDATE … WHERE ID = ? AND state = 'PENDING'` winning on an affected count of 1; the drain query gains the expired-lease reclaim clause that `find_eligible` already has; `record()` expects `IN_FLIGHT`.

**No distributed lock, on either leg.** A lease that expires while the first runner's request is still in flight still permits a double send. That residual case is accepted because both receivers' idempotency is runtime-proven, and because closing it would require machinery out of proportion to the risk. The lease prevents **unnecessary** double-sending and prevents two runners corrupting each other's bookkeeping; it does not claim to prevent all double sending.

### Phase 7.6 — outbound recovery parity

An outbound `DeliveryIntent` in `UNKNOWN` currently has **no operator recovery path at all**. `find_eligible` returns only `PENDING` and expired-lease `IN_FLIGHT` rows; `claim` refuses `FAILED` and `UNKNOWN` as `state_final`; and `retryDelivery`, which the source comments defer to, has never been built. The inbound leg received `reconcile-supplier-response` in 6.5g and the outbound leg was never given the equivalent. **This is the largest operational gap carried out of Phase 6, and it stays in Phase 7.**

The frozen constraints on the future action:

- It **replays the existing durable `DeliveryIntent` snapshot** — the immutable `PayloadSnapshot` already committed — under the **same `deliveryId`**.
- It **must never mint a new `deliveryId`**, and must never call `sendToSupplier` in a way that creates a new `DeliveryIntent`. `sendToSupplier` requests a delivery; `retryDelivery` replays one. Confusing them would produce a second portal order for one approval.
- It is an **operator-controlled replay of an approved snapshot**, not a bulk retry over arbitrary `ERROR` orders, per the rule already stated in [domain-model.md](architecture/domain-model.md).
- It must not downgrade a terminal business result if a valid receipt or callback arrived in the meantime.
- `ZJP_CL_PO_EML_TEST` is updated with it, as every RAP behaviour change requires.

## Phase 7.2 — the real `UNKNOWN` test, and its mandatory safety gate

Phase 6 never induced a real `UNKNOWN` transport condition in production, so the `UNKNOWN → DELIVERED` transition has automated-test evidence only. 7.2 closes that, and it does so **without changing any code, deploying anything, or touching SAP or Cloud Integration**.

### Mechanism

`readCiConfig()` defaults its parameter to `process.env` and is called at run time by both scripts, and the client deadline comes from **`PIH_CI_TIMEOUT_MS`**, defaulting to 30 000 ms. A Cloud Foundry task command runs in a shell, so prefixing **one** invocation with a smaller value shortens that attempt's deadline and nothing else. The application's own environment, the droplet and every other runner are untouched.

The request is genuinely dispatched. The client abort fires while it is in flight, `fetch` throws, the catch returns `answered: false`, `classify` returns `UNKNOWN`, and the guarded write records a real `UNKNOWN` row with a real correlation ID. This is the actual "receiver may have committed" condition, not a simulation of one — and TI-1 shows it is a condition the production configuration already makes reachable, since Cloud Integration is allowed 60 s for a call the sender abandons at 30 s.

### The safety gate — mandatory, and the test aborts if it fails

A shortened `PIH_CI_TIMEOUT_MS` applies to **the whole task**, and `flushSupplierResponses` has no per-response filter: it drains every `PENDING` row it finds. **An unrelated supplier response caught in that run would be driven to `UNKNOWN` by a deliberately broken deadline, through no fault of its own, and would then require operator reconciliation.** That is an unacceptable side effect of a test.

**Therefore, before any shortened-timeout flush is executed, it must be proven that the only eligible `PENDING` row is the dedicated Phase 7 fixture.** The gate has two parts and both are read-only:

**Part A — a read-only query** over `SupplierResponseDeliveries` establishing that exactly one row is in `state = 'PENDING'`, and that its `responseId` is the fixture's.

**Part B — a dry run at the normal timeout**, using the deployed sender's own reporting: `flush-supplier-responses --dry-run --limit 1`. A dry run builds the payload and reports it **without sending anything**, and each outcome carries its `responseId`. The run must report `scanned: 1` and that one `responseId` must be the fixture's.

Part B exists because Part A alone proves what the database holds, while Part B proves what **the deployed code would actually select** — including the within-run version-ordering guard, which can hold a row back for reasons a raw query does not show.

**The test MUST abort, with nothing sent, if any of the following is true:**

- more than one `PENDING` row exists;
- any eligible row other than the fixture exists;
- the fixture cannot be uniquely identified by its `responseId`;
- Part A and Part B disagree about which row would be sent;
- the dry run reports anything other than `scanned: 1`.

**When the gate fails, the correct response is to wait or to investigate — never to clear the way.** Other `PENDING` rows must not be deleted, edited, drained at the normal timeout to get them out of the way, or moved to another state to make the fixture unique. Those are writes to committed business decisions performed for the convenience of a test, and the resulting evidence would be worth less than the state it disturbed.

`--limit 1` is then passed to the real run as a second barrier, not as the primary one: the gate is what makes the run safe, and the limit is what contains a gate that was wrong.

### Can 7.2 reuse the existing sender for exactly one `responseId`?

**No — and the limitation is the 6.5g guard working correctly, not a defect.**

The module exports exactly two entry points, and neither sends one nominated `PENDING` row:

| Export | Selects | Why it does not fit |
| --- | --- | --- |
| `flushSupplierResponses(options)` | `SELECT … where({ state: 'PENDING' }).orderBy('createdAt','version').limit(limit)` | `FlushOptions` is `{ transport, limit, dryRun, newCorrelationId, log }` — **there is no `responseId` filter**. `limit: 1` takes the *oldest* `PENDING` row, whichever that is |
| `reconcileSupplierResponse(options)` | one row by `responseId` | Refuses anything that is not `UNKNOWN`. For a `PENDING` row it returns `NOT_UNKNOWN` with the reason *"it is still queued and the normal flush will send it"* |

The one function that takes a single `responseId` is precisely the one that refuses `PENDING`, by design. `attempt()` and `record()` — which hold the payload build, the transport call, `classify`, `describe` and the guarded write — are **module-private and not exported**, so no task script can reach them without duplicating transport and classification logic, which is exactly what must not happen.

**A second and decisive reason:** 7.2 runs against the **already-deployed droplet**. Even a small addition such as a `responseId` filter on `FlushOptions` would exist only in the working tree until a rebuild and `cf deploy` — and 7.2 must not deploy. Any design requiring new code is therefore not a 7.2 design at all.

**Recommendation: keep the full flush, and make the read-only gate above mandatory.** The runtime shape is a single Cloud Foundry task that performs Part A, aborts on any gate failure, and only then runs `flushSupplierResponses` at the shortened deadline with `limit: 1`. The sender's own transport and classification logic is reused untouched, and no repository code is added.

### Sequence — design only, not executed

| | Step | Establishes |
| --- | --- | --- |
| 0 | Measure a known-good delivery's total processing time from its Cloud Integration message log; set the shortened deadline to roughly 40–60% of it | the value is measured, not invented (OQ-3) |
| 1 | Seed the labelled Phase 7 fixture order; capture the SAP header baseline: `SupplierResponse`, `EstimatedDeliveryDate`, `SupplierRespondedAt`, `LastResponseId`, `LastResponseVersion`, `LastChangedAt` | a clean before-state |
| 2 | Record the supplier decision through the deployed service; capture the `responseId` and the `PENDING` row | the decision committed normally |
| 3 | **Safety gate, Parts A and B.** Abort on any failure | exactly one eligible row, and it is the fixture |
| 4 | Shortened-deadline flush, `limit: 1` | **a real `UNKNOWN` row** with a real correlation ID, `attempts 1` |
| 5 | Read SAP — **observe only, do not act** | which branch of the ambiguity ran |
| 6 | `reconcile-supplier-response --response-id <same uuid>` at the **normal** deadline | `UNKNOWN → DELIVERED`, `attempts 2`, a **fresh** correlation ID, the **same** `responseId` |
| 7 | Read SAP a third time | `LastResponseVersion` never exceeded the response's version; `LastChangedAt` moved **at most once** across steps 1→7 |

### Why the test cannot fail unsafely

Once the gate has passed there are exactly two outcomes, and both are valid:

- **The abort lands after SAP applied.** Reconciliation replays the same `responseId`, RAP's runtime-proven idempotency answers `204` without writing, `LastChangedAt` does not move, the row reaches `DELIVERED`.
- **The abort lands before SAP applied.** Reconciliation replays, RAP applies it, `LastChangedAt` moves once, the row reaches `DELIVERED`.

Both end `DELIVERED` and both prove *applied at most once*; they differ only in which branch ran, and SAP's `LastChangedAt` reveals which afterwards. A badly chosen deadline changes the branch, never the safety. **The unsafe failure mode is not a mis-timed abort — it is a shortened deadline reaching a row that was never part of the test**, which is the single thing the gate exists to prevent.

## Phase 7 acceptance matrix

| Subphase | Runtime acceptance criterion | Blocked by |
| --- | --- | --- |
| **7.1** | Not runtime. **Gate: this document is frozen, every matrix row carries an evidence level, and no executable source changed.** | — |
| 7.2 | **The safety gate passed before anything was sent** — exactly one eligible `PENDING` row, proven to be the fixture by both a read-only query and a normal-deadline dry run; a genuine `UNKNOWN` row exists in HANA with a real correlation ID; reconciliation returns `DELIVERED` at `attempts 2` with the **same** `responseId` and a **fresh** correlation ID; SAP's `LastChangedAt` moved **at most once** end to end; **no unrelated supplier response changed state** | 7.1 |
| 7.3 | A deployed flush writes exactly one attempt row per attempt; a losing compare-and-set writes **none**; 7.2's sequence replayed yields two attempt rows with two distinct correlation IDs | 7.2 |
| 7.4 | A `PENDING` row is skipped before it is due and attempted after; an exhausted row is skipped indefinitely and appears as retry-exhausted; `UNKNOWN` is never auto-retried; a category-A failure lands in `PENDING`, not `UNKNOWN` | 7.3 |
| 7.5 | Two concurrent deployed flushes: one claims, one skips; no row sent twice unnecessarily; a killed runner's row is reclaimed after its lease and completes | 7.4 |
| 7.6 | An outbound `UNKNOWN` intent is replayed under its **original** `deliveryId`; CAP answers `200` with the **original** receipt; SAP reaches `SENT`; **no duplicate order exists in the portal** | 7.4 |
| 7.7 | Every monitoring view returns real deployed data; an operator locates 7.2's attempt in the Cloud Integration message log **by searching its correlation ID** | 7.3, 7.6 |
| 7.8 | Not runtime. Gate: every runbook branch cites an executed case or is explicitly marked untested | 7.2–7.7 |
| 7.9 | Highest-value untested matrix rows executed; full suite green; every row's evidence at its correct level; no claim promoted beyond what ran | all |

## Open questions

**OQ-1 — can `cx_web_http_client_error` be split?** The ABAP exception covers connect failure, TLS failure and timeout in one class, so the pre-send/ambiguous distinction cannot be made from the exception type alone. Whether a finer signal is available on this target — a subclass, a `T100` key, a message number — is unknown and needs an ADT probe. **Does not block 7.2.** If no split exists, outbound category A is limited to `cx_outbound_provider_http` and the limitation is recorded rather than worked around.

**OQ-2 — how should Cloud Integration surface a pre-send failure?** Correcting the CSRF misclassification requires the iFlow to answer with something CAP can distinguish, which means an Exception Subprocess on the inbound flow returning a status in the transient class (for example `503` with a distinguishing code) rather than an unhandled `500`. **This is a second Cloud Integration change and is not covered by the approved MPL custom-header ruling.** It needs its own decision. **Does not block 7.2**, and must be settled before 7.4 can claim category A is handled on the inbound leg.

**OQ-3 — what is the real round-trip latency?** 7.2 sets `PIH_CI_TIMEOUT_MS` below the normal round trip, and no committed artifact records what that round trip is. The value must be **measured** from a known-good 6.5f delivery's message-processing log before the test runs, not guessed. **This is a step inside 7.2, not a blocker of it.**

**Nothing blocks 7.2.** It requires no code change, no deployment, no SAP change and no Integration Suite change: `readCiConfig()` reads `PIH_CI_TIMEOUT_MS` from the process environment at call time, so a single task invocation can shorten that one attempt's client deadline without touching the application's own configuration.
