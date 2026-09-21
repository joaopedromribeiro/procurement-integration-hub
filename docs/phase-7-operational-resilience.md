# Phase 7 — Error Handling, Monitoring & Operational Resilience

Phase 7 makes the bidirectional integration proven in Phase 6 operationally robust under real failure conditions. It adds no new integration product, no new architectural layer and no new authentication model: Event Mesh remains Phase 9 and API Management remains Phase 10, per the committed roadmap in [README.md](../README.md#project-roadmap). Every Phase 6 durable flow stays exactly as it is and is hardened in place.

**Subphase 7.1 is frozen design. No executable source was changed by it.** This document is that freeze: the fault model, the four failure categories, the CSRF investigation, the timeout reconciliation, and the terminology and direction decisions that subphases 7.2 through 7.9 must hold to.

**Subphase 7.2 is COMPLETE and runtime-verified**, executed 2026-09-21 against the deployed droplet, the deployed `PIH_SupplierResponse_v1` and the real SAP system, with all nine acceptance criteria satisfied and no repository code changed. Its result and evidence are recorded in the Phase 7.2 section below. **Subphase 7.3, attempt history, is next and has not started.**

| Subphase | Objective | State |
| --- | --- | --- |
| **7.1** | Fault model and acceptance criteria | **frozen — this document** |
| **7.2** | Runtime-proven `UNKNOWN` and reconciliation, via a deterministic injected state-machine-facing unanswered observation over a real send | **COMPLETE — runtime-verified 2026-09-21** |
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
| Client timeout | `UNKNOWN` | unchanged — irreducibly ambiguous | **automated-test** | **the condition — this is 7.9, not 7.2.** Phase 7.2 injects the unanswered observation at the `ResponseTransport` seam and never produces a real timeout, so it leaves this row untouched |
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

## Phase 7.2 — runtime-proven `UNKNOWN` and reconciliation

The claim this subphase is permitted to make, in full and without paraphrase:

> **Runtime-proven `UNKNOWN` and reconciliation via a deterministic injected state-machine-facing unanswered observation over a real CAP → Cloud Integration → SAP send.**

The injection point is the `ResponseTransport` seam, and nowhere else. Stated as three layers, because the middle one is the only thing that changes:

| Layer | Behaviour |
| --- | --- |
| **The real HTTP client** | continues waiting normally and receives the actual result |
| **The `ResponseTransport` seam** | presents `answered = false` to the delivery state machine |
| **The delivery state machine** | classifies that presented result as `UNKNOWN` |

Nothing is injected *at the HTTP client*.

It must **not** be described as a real `UNKNOWN` transport condition, a real socket failure, a real `AbortSignal` timeout, a caller disconnect, a lost HTTP response, client abandonment, request cancellation, the HTTP client stopping its wait, or proof of Cloud Integration's behaviour after its caller disconnects. Those are genuine transport-failure scenarios and they remain **Phase 7.9** work.

### The distinction a future reader must not miss

Two things happen concurrently, and **only one of them is artificial**:

| | What it does |
| --- | --- |
| **The delivery state machine** | observes `answered = false` **immediately**, because the composite hands it that value. This observation is **injected and artificial**. |
| **The real HTTP transport** | **continues waiting normally**, on an open socket, at the normal 30-second deadline. Its promise is retained separately and must later resolve `answered = true` with `HTTP 204`. Nothing about it is artificial, interrupted or cancelled. |

Nothing stops waiting. Nothing is abandoned, cancelled or disconnected. **The real client waits out the full exchange and receives the real answer**; what is injected is a *state-machine-facing unanswered observation over a concurrently retained real transport send*. The retained result is not discarded — it is checked, and the mandatory real-send gate below refuses to let the experiment continue unless it settled `204`.

### A. What Phase 7.2 proves

A real supplier response leaves real CAP through the **deployed** transport under a real correlation ID, reaches Cloud Integration and SAP, and is really applied. The deployed classifier and the deployed guarded compare-and-set persist a real `UNKNOWN` row in real HANA with `attempts 1`. An operator reconciliation then replays the same `responseId` with a fresh correlation ID, RAP answers idempotently, the row reaches `DELIVERED` at `attempts 2`, and SAP's commercial response is applied **at most once** with `LastChangedAt` moving at most once.

The production payload builder, classifier, description logic, guarded record path and reconciliation implementation are reused unchanged, and the real HTTP send is performed by the deployed `HttpResponseTransport`. **The only injected value is the unanswered transport observation presented to the delivery state machine.** The boundary is exact:

| | |
| --- | --- |
| **Real** | payload construction (`buildSupplierResponsePayload`); the `HttpResponseTransport` send; the Cloud Integration execution; SAP `applySupplierResponse`; the `classify` implementation; the guarded `record` implementation; the HANA row; the reconciliation command; RAP idempotency |
| **Injected** | the state-machine-facing transport result — **`answered = false`**, and nothing else |

Everything in the first row runs in the deployed droplet against the bound HDI container, the deployed iFlow and the real SAP system.

### B. What Phase 7.2 does not prove

That any genuine transport failure occurred. The socket stays open, the real HTTP client waits normally, and it receives `HTTP 204`. The unanswered condition exists **only in what the delivery state machine is told**: the composite returns `answered = false` to the sender while the real transport send continues concurrently. The real answer is **not** discarded — it is retained and must later settle `204`, which the mandatory real-send gate enforces.

**The Phase 6 gap is therefore split, not closed.** Phase 6 recorded that no deliberately induced `UNKNOWN` had been executed in production. Phase 7.2 closes the **lifecycle** half of that gap — `UNKNOWN` → operator reconciliation → `DELIVERED`, with at-most-once application, against real systems. The **transport-condition** half remains uninduced and is listed in G.

### C. Why the shortened-timeout mechanism was retired

The original 7.1 design shortened `PIH_CI_TIMEOUT_MS` for one task so the client deadline would expire after the `applySupplierResponse` POST had been dispatched but before the answer returned. Three real Cloud Integration message-processing logs, captured under temporary Trace on `PIH_SupplierResponse_v1`, retired it on evidence.

`T0` is the Cloud Integration message start, `T1` the CSRF `GET` end, `T2` the `applySupplierResponse` POST start, `T3` its end, `T4` the message end. The measured offsets, **as observed inside Cloud Integration and nothing more**:

| Probe | `T2 − T0` | `T3 − T0` | `T4 − T0` | Matched CAP-side elapsed |
| --- | --- | --- | --- | --- |
| **A** (fast) | 468 ms | 854 ms | 869 ms | **963 ms** |
| **B** (slow) | 1789 ms | 2917 ms | 2943 ms | not measured |
| **C** | 1171 ms | 2107 ms | 2122 ms | not measured |

**Only Probe A has a matched CAP-side elapsed measurement**, and the proof below uses it directly rather than deriving anything from `T4`. Its outside-MPL overhead, `963 − 869 = 94 ms`, is recorded as **Δ_total_A = 94 ms** and kept as a measured diagnostic fact; **it is not used in the argument**, and **A's value must never be carried across to B or C** — the outbound overhead is a per-run quantity that varies with TLS handshake and connection reuse.

The argument needs **no assumption about the outbound overhead of B or C**. Write `δout_i` for the outbound CAP → CI overhead of run *i*, so that a CAP-relative deadline of `timeout` reaches Cloud Integration's `Tx` when `timeout = δout_i + (Tx − T0)`.

**From Probe A — the measured CAP response deadline.** CAP observed a successful `HTTP 204` after **963 ms**. For that same observed run to have become unanswered at the CAP caller instead, a shortened deadline would have to satisfy

```
timeout  <  963 ms
```

This is a direct statement about what CAP actually measured. **No `T4`-derived bound is used**, and none would be correct: `T4` is the end of the Cloud Integration message, not the instant the answer arrives at CAP, and a deadline falling between the two would still be a valid unanswered condition.

**From Probe B — a lower bound, using only `δout ≥ 0`.** The CAP-relative instant at which B's POST starts is `δout_B + 1789 ≥ 1789 ms`, because an overhead cannot be negative. Any timeout **guaranteed** to fire after the SAP POST has started in B must satisfy

```
timeout  >  1789 ms
```

**These two requirements are contradictory.** The contradiction rests on one directly measured quantity — A's 963 ms CAP-observed round trip — and one inequality that needs no measurement at all, `δout_B ≥ 0`.

**Probe C reproduces the contradiction independently.** Its POST starts no earlier than `δout_C + 1171 ≥ 1171 ms`, so a guaranteed post-`T2` timeout for C requires `timeout > 1171 ms`, which is likewise incompatible with A's `timeout < 963 ms`.

The shape of the argument is therefore: **A supplies the measured CAP response deadline; B and C supply conservative lower bounds on when the SAP POST can begin.** Nothing else is needed.

**More sampling cannot repair this.** The contradiction between A and B is already fixed by observations that have been made; adding further runs cannot make a single fixed timeout satisfy runs that are *already* mutually incompatible. A new sample can only add further constraints, never withdraw an existing one.

One further limitation is recorded for accuracy, and it does not affect the proof above. **The two clocks are demonstrably unaligned:** Probe A's CAP `endIso` of `12:55:55.501` precedes Cloud Integration's `T4` of `12:55:55.507`, and CAP cannot receive an answer before it was sent. `Δ_total_A` survives this, being the difference of two *durations* each measured on its own clock, but **absolute cross-system timestamp comparisons do not** and none is relied on here.

### D. Why the `ResponseTransport` seam is acceptable

`ResponseTransport` is a one-method interface that `flushSupplierResponses` takes as a **required** option, and `attempt()` calls it exactly once per row. `ci-transport.ts` states the design intent in its own words: the sender *"is written against the `ResponseTransport` interface below and never learns whether it is talking to a tenant or to a test double, which is what lets the whole delivery state machine be proven without a live iFlow."* The automated suite already substitutes it.

Phase 7.2 does **not** substitute a fake. It injects a **composite** that delegates to the real deployed `HttpResponseTransport` and lets that send run to completion, so no transport, payload or classification logic is duplicated anywhere and no real request is cut short. What the composite changes is **only the value handed back to the state machine**, not the behaviour of the HTTP client underneath it. The composite lives only in a one-off scratch Cloud Foundry task, base64-encoded into `--command`, exactly as every Phase 6 and Phase 7 task has. **No repository code is added, nothing is deployed, and no SAP or Integration Suite artifact changes.**

### E. Why the real request must still reach Cloud Integration and SAP

The point of the subphase is that the business path completes while the state machine deliberately retains `UNKNOWN`. If the real request did not reach SAP, the reconciliation would exercise a fresh application rather than RAP's `ALREADY_APPLIED` path, and the at-most-once proof would be about a different thing.

Therefore the composite delegates to the real transport at the **normal** 30-second deadline. **`PIH_CI_TIMEOUT_MS` must not be set by this task at all**; a shortened value could let the real send time out and destroy the guarantee. The task asserts the resolved `timeoutMs` before sending.

### F. Why the scratch task must outlive `flushSupplierResponses`

`scripts/flush-supplier-responses.ts` ends with `main().then(code => process.exit(code))`. **`process.exit()` terminates immediately and abandons in-flight sockets**, so a task copying that shape would kill the real request at an arbitrary point — reintroducing precisely the non-determinism that retired the timeout mechanism. Awaiting the retained promise **is** the determinism guarantee, not a refinement of it.

### G. Phase 7.9 carry-over — unresolved by Phase 7.2

These remain open runtime-resilience items and **Phase 7.2 must not be described as closing any of them**:

- a genuine `AbortSignal` timeout;
- a genuine socket abort;
- a caller disconnect;
- the caller process disappearing while Cloud Integration is still processing;
- Cloud Integration's behaviour after its caller disconnects;
- proof that a real transport-level lost response produces the intended `UNKNOWN` semantics.

### The composite transport — required control flow

1. The deployed sender generates correlation ID **A** and passes it to `transport.send(payload, A)`. The composite **passes A straight through** and never generates one of its own — the entire after-the-fact proof rests on the persisted `lastCorrelationId` equalling the message log's `X-Correlation-ID`.
2. The composite calls the real `HttpResponseTransport.send(payload, A)` **exactly once**.
3. It retains that promise at task scope.
4. It attaches a rejection handler **synchronously, in the same tick the promise is created**, so there is never an unhandled-rejection window while `flushSupplierResponses` is still running. `send` is documented to resolve for every outcome and reject for none, but the `Buffer.from(clientId:clientSecret)` authorization line sits **outside** its `try`, so a malformed configuration could reject; under Node's fatal-unhandled-rejection default that would kill the process mid-flight, which is the exact failure being prevented.

   **That handler does not make step 8 safe on its own.** `p.catch(...)` returns a *new* promise; the retained original still rejects, and `await`-ing it would throw. The two concerns are separate and both must be handled: the synchronous handler closes the unhandled-rejection window, and step 8 needs its own protection.
5. It returns `answered: false` to `flushSupplierResponses` immediately, without awaiting the real promise. **This is the only artificial step.** The real transport send is not cancelled, aborted or shortened by it; the real HTTP client goes on waiting on its open socket for the genuine answer.
6. The deployed sender performs its normal `classify` → `UNKNOWN` and its normal guarded `record` into HANA. Expected row: `state UNKNOWN`, `attempts 1`, `lastCorrelationId A`.
7. The task **stays alive**. It must not use the flush CLI's `process.exit` pattern.
8. It awaits the **same retained promise inside an explicit `try`/`catch`** — or normalises its settlement into a result object — so that a rejection becomes a value the task can act on rather than an exception that ends it. `HttpResponseTransport.send` is **never** called a second time.
9. It re-reads the row after the real send settles. The row must still be `state UNKNOWN`, `attempts 1`, `lastCorrelationId A`.

The three settlement outcomes are distinguished explicitly, and **an uncaught rejection must never terminate the task before the post-attempt diagnostics have run**:

| Retained promise settles | Outcome |
| --- | --- |
| resolves `answered = true`, `status = 204` | **the real-send gate passes** |
| resolves with **any other** result | **controlled STOP** |
| **rejects** | **controlled STOP** — caught, normalised, reported as a `REAL_SEND_GATE` failure |

On either STOP the task logs only a **safe summary** — never a response body, a header or a credential — and then stops. **Do not reconcile. Do not send again. Do not create another response. Do not consume another fixture.** Investigate the experiment instead. The `UNKNOWN` row keeps its identity and remains replayable, so nothing is lost by stopping.

The retained `HttpResponseTransport` execution has **no direct database access** and does not directly update `SupplierResponseDeliveries`: `ci-transport.ts` imports no `@sap/cds` runtime API — its only import is a *type* — and performs no `SELECT` or `UPDATE`. The delivery-state write in this execution is performed by `record()`, using the result presented to `attempt()`.

Three consequences follow, and they are what the design relies on: the background real-send promise **does not independently call `record()`**; it **has no direct HANA write path**; and therefore the eventual `HTTP 204` **cannot silently convert the already-persisted `UNKNOWN` row to `DELIVERED`**. Only the reconciliation command, run deliberately and later, moves that row.

### The safety gate — carried over from 7.1, unchanged

Before anything is sent, it must be proven that the only eligible `PENDING` row is the dedicated Phase 7 fixture: **Part A**, a read-only query showing exactly one row in `state = 'PENDING'` whose `responseId` is the fixture's; and **Part B**, a normal-deadline `--dry-run --limit 1` reporting `scanned: 1` for that same `responseId`. The run aborts if more than one `PENDING` row exists, if any other eligible row exists, if the fixture is not uniquely identifiable, if the two parts disagree, or if the dry run reports anything else. **When the gate fails the correct response is to wait or investigate, never to clear the way** — no other row is deleted, edited, drained or moved to make the fixture unique. `limit: 1` is a second barrier, not the primary one.

### The mandatory real-send gate

**Before reconciliation is permitted, the retained real result must prove `answered = true` and `HTTP status = 204`.**

If it is anything else — `answered = false`, a timeout, an `AbortError`, an HTTP error status, a rejected promise, a missing retained result, or an unexpected status — then **STOP**. Do not reconcile, do not send again, do not create another response, and do not consume another fixture. Investigate the experiment instead.

This gate is what makes the subphase's claim true: Phase 7.2 must prove that the real CAP → Cloud Integration → SAP path **completed successfully** while the state machine deliberately retained `UNKNOWN`. Without the `204` the experiment proves only that a row can be written.

### Correlated Cloud Integration evidence

After the real send succeeds, Cloud Integration evidence must confirm that **the execution produced by the task reached the normal `applySupplierResponse` path**. Under **Tier 2**, temporary Trace additionally proves that this execution carried correlation **A**. Under **Tier 1**, the execution is associated with the task only by uniqueness of the task window and `COMPLETED` status, and **that association remains inference** — correlation **A** is not observed at all.

**Do not claim that `UNKNOWN` was persisted after SAP received the POST.** The ordering is very likely the reverse: the row reaches `UNKNOWN` while the real transport send is still progressing through Cloud Integration, because the state machine was handed its unanswered observation immediately while the real client kept waiting. That ordering is expected and acceptable, and it is why the proof is after-the-fact correlation rather than a claim about sequence.

The proof is an **after-the-fact evidence chain** across four independent observations. Only under Tier 2 may it be called **direct correlation**; under Tier 1 its third link is an association by uniqueness, not an observation of **A**:

- the HANA `UNKNOWN` row carries correlation **A**;
- the retained real transport send for correlation **A** settled `HTTP 204`;
- Cloud Integration evidence shows the task's execution reaching `applySupplierResponse` — **carrying A** under Tier 2, **associated by window uniqueness** under Tier 1;
- SAP holds the expected commercial response.

#### How correlation A is actually located, before Phase 7.7 exists

**Correlation-ID search does not exist yet and must not be assumed.** Phase 7.1 verified from both committed exports that **neither iFlow configures `SAP_MessageProcessingLogCustomHeaderProperty`**, so `X-Correlation-ID` travels through Cloud Integration but is **not indexed** and **cannot be searched** in Monitor. Adding it is Phase 7.7 work and **must not be pulled forward into 7.2.**

**At Info level the incoming `X-Correlation-ID` is not exposed in the message processing log at all.** Without the custom-header property, request headers and exchange properties are captured only under **Trace**. So at Info the log can say *which* execution ran and *that* it completed, but not *which correlation ID it carried*.

That leaves two tiers of evidence, and the difference between them must be recorded honestly.

**Tier 1 — Info level, uniqueness by window. Available with no Trace and no change of any kind.**

1. Record the exact UTC start and end of the Cloud Foundry task.
2. In Monitor, filter to iFlow `PIH_SupplierResponse_v1` over that window.
3. **Exactly one message must appear, with status `COMPLETED`.** If more than one appears, **STOP** — the correspondence is no longer unique and nothing may be concluded from it.
4. `COMPLETED` on this artifact implies the `applySupplierResponse` POST executed, because the committed export is a single linear sequence with no gateway and **no Exception Subprocess**, so `EndEvent_2` is reachable only through `ServiceTask_716`.

This establishes that the one request the task sent reached `applySupplierResponse` — **by uniqueness and by the artifact's shape, not by reading correlation A.** Step 4 is an **inference from a committed artifact**, and the whole tier is weaker than direct evidence. It must be labelled that way and never written up as "the log showed correlation A".

**Tier 2 — a temporary Trace capture for this one controlled execution. Recommended.**

Trace is the only existing mechanism that exposes the incoming `X-Correlation-ID` before 7.7, and it is already an approved, already-exercised tool from the timing probe. For one shot it converts Tier 1's inference into direct evidence — the log shows the request carrying **A**, and the equality with the persisted `lastCorrelationId` is then observed rather than deduced. The conditions are absolute:

- it is **diagnostic evidence collection only** and **changes no iFlow semantics** — no payload, routing, retry, authentication or `throwExceptionOnFailure` change, and no redeployment;
- **restore the log level to Info immediately after the run**, without waiting for the automatic expiry;
- **never copy an `Authorization` header, a `Cookie`, a `set-cookie`, an `X-CSRF-Token`, a service key, a client secret or any other credential** out of a Trace panel — not into the repository, not into a report, not into chat. Trace captures headers and payloads, which is exactly why it is switched off again at once;
- capture only the minimum: the correlation ID, the step names and the status.

**If Trace is declined for this run, the limitation stands and the gate is weakened rather than quietly satisfied.** The procedural gate then reads "Cloud Integration evidence confirms, by uniqueness of window and `COMPLETED` status, that the single execution the task produced reached `applySupplierResponse`", carrying **inference** as its evidence level — and the write-up must not claim that correlation A was observed in Cloud Integration.

**One independent corroboration exists either way**, and it is worth recording because it comes from a third system: after the experiment SAP holds `LastResponseId` equal to the fixture's `responseId`. That proves the response itself reached SAP. It does not identify which correlation ID carried it, so it strengthens the chain without substituting for Tier 2.

### Reconciliation and the at-most-once proof

Only after the real-send `204` gate **and** the post-send HANA re-read have both passed may the deployed reconciliation command run, with the same `responseId`, the normal `HttpResponseTransport`, the normal 30-second deadline and a fresh correlation **B**. Expected: `B ≠ A`, `attempts 2`, `state DELIVERED`.

SAP is read three times: **L0** the baseline before the experiment, **L1** after the first real send has completed and **before** reconciliation, **L2** after reconciliation. For `LastChangedAt` the valid result is

```
L0 ≠ L1   AND   L1 == L2
```

**`LastChangedAt` alone is not the whole proof, and the response-identity invariant is checked alongside it.** These are **procedural SAP proofs supporting criteria 8 and 9**, not a tenth business-state acceptance criterion.

| Reading | Must show |
| --- | --- |
| **L1** — after the first real send | the expected commercial response applied; `LastResponseId` = the fixture's `responseId`; **`LastResponseVersion` = 1**, because this is the first supplier response version for an untouched fixture; `LastChangedAt` moved from L0 |
| **L2** — after reconciliation | the **same** `LastResponseId`; **`LastResponseVersion` still 1**; `LastChangedAt` **unchanged** from L1 |

**The reconciliation replay must never produce `LastResponseVersion > 1`.** A replay of one response cannot create a second version, and if it does, the receiver treated an idempotent replay as a new decision.

**STOP** if any of the following holds: `LastResponseId` differs from the fixture's `responseId`; `LastResponseVersion` is not `1` after the successful first real send; `LastResponseVersion` increases during reconciliation; or `LastChangedAt` changes again during reconciliation.

The expected strong branch is that SAP was already applied during the first real send, so reconciliation must be idempotent. A second `LastChangedAt` movement, or any version increase, violates the at-most-once acceptance condition and is **the most important negative finding this experiment could produce** — it must be reported, not worked around.

### Acceptance criteria

The nine business-state criteria are unchanged from the 7.1 freeze:

1. a real `SupplierResponseDeliveries` row reaches `UNKNOWN`;
2. `attempts = 1`;
3. correlation **A** stored;
4. the same `responseId` is reconciled;
5. correlation **B ≠ A**;
6. `attempts = 2`;
7. final state `DELIVERED`;
8. the SAP commercial response is applied **at most once**;
9. `LastChangedAt` moves **at most once**.

The following are **procedural gates, not business-state criteria**, and must not be presented as new acceptance conditions:

- exactly one intended `PENDING` row exists before the experiment;
- the real send is initiated exactly once;
- the retained real send settles `answered = true` with `HTTP 204`;
- the row remains `UNKNOWN` / `attempts 1` / correlation **A** after the real send settles;
- Cloud Integration evidence confirms that the execution the task produced reached `applySupplierResponse` — **at Tier 2** (temporary Trace, correlation **A** read directly) or, if Trace is declined, **at Tier 1** (uniqueness of window plus `COMPLETED`, recorded as **inference**);
- reconciliation is forbidden until every one of those gates has passed.

### Phase 7.2 runtime result — COMPLETE

**Executed 2026-09-21 against the deployed droplet, the deployed `PIH_SupplierResponse_v1` and the real SAP system.** No repository code was changed, nothing was deployed, and no SAP, CAP or Integration Suite artifact was modified to make it pass.

The claim this run earns, and nothing wider:

> **Runtime-proven `UNKNOWN` and reconciliation via a deterministic injected state-machine-facing unanswered observation over a real CAP → Cloud Integration → SAP send.**

#### The fixture

| | |
| --- | --- |
| External order | `PO00000123` |
| CAP `portalOrderId` | `ed267da7-83e2-4a38-8cb3-dfe095f7a5fc` |
| SAP order UUID | `37FC3FA8-EB2D-1FD1-ACF8-86475DCE323D` |
| Delivery UUID | `37FC3FA8-EB2D-1FD1-ACF8-86475DCFD23D` |
| Supplier | `RTTEST001` |
| Decision | `ACCEPTED`, `2026-12-15` |
| `responseId` | `a1bd862a-573f-461e-b337-5e39aa595a61` |

**`PO00000123` was used only after its CAP and SAP identity and baseline were independently revalidated** — see the abandoned `PO00000121` diagnostic below for why that revalidation was not a formality. CAP precheck: `status RECEIVED`, `responseVersion 0`, `supplierCode RTTEST001`, `supplierActive true`, `responseRows 0`, and **`PENDING_TOTAL 0`**. The SAP `ZJP_PO_DLV` intent was checked directly and its `PORTAL_ORDER_UUID` `ED267DA783E24A388CB3DFE095F7A5FC` matches the CAP `portalOrderId` exactly under canonical formatting, with `DISPATCH_STATE DELIVERED`.

SAP baseline before the decision: `Status SENT`, `SupplierResponse ""`, `EstimatedDeliveryDate null`, `SupplierRespondedAt null`, `LastResponseId 00000000-0000-0000-0000-000000000000`, `LastResponseVersion 0`.

```
L0 = 2026-09-19T00:51:08.288116Z
```

#### The decision and the safety gate

The decision committed through the deployed `SupplierService`: `status ACCEPTED`, `responseVersion 1`, `respondedAt 2026-09-21T16:04:53.736Z`, `responseDeliveryStatus PENDING`. The durable row was `state PENDING`, `attempts 0`, `lastCorrelationId null`, `v1`, `dec ACCEPTED`, with `PENDING_TOTAL 1`.

Both parts of the 7.1 safety gate passed. Part B — the normal-deadline dry run — selected **exactly** `a1bd862a-…` and reported `scanned 1 … skipped 1`, exit `0`.

#### The single real send, and the injected observation

`PIH_CI_TIMEOUT_MS` was **unset for the task process only**; no application environment was mutated, and `readCiConfig` resolved the normal deadline. The task reported `CONFIG timeoutMs=30000 path=/http/pih/v1/supplier-responses`.

| Observation | Value |
| --- | --- |
| Correlation **A** | `d57bf9b0-9f22-46b8-818e-87234115c75e` |
| Flush result | `scanned=1 delivered=0 failed=0 pending=0 unknown=1 skipped=0` **`sends=1`** |
| Row immediately after `record()` | `state UNKNOWN`, `attempts 1`, `corr A` |
| **Retained real transport settlement** | **`answered=true`, `status=204`** |
| Row re-read after that settlement | `state UNKNOWN`, `attempts 1`, `corr A` — **unchanged** |
| Gate | `REAL_SEND_GATE PASS`, exit `0` |

`sends=1` is the machine-checked proof that the real `HttpResponseTransport.send` was invoked **exactly once**. The row remaining `UNKNOWN` after the `204` settled is the proof that the eventual success could not, and did not, move the durable state by itself — the only writer is `record()`, driven by the value the composite returned.

#### Cloud Integration evidence — Tier 1

Exactly one relevant `PIH_SupplierResponse_v1` message existed in the execution window:

| Field | Value |
| --- | --- |
| `StartTime` | `Mon Sep 21 16:09:04.230 UTC 2026` |
| `StopTime` | `Mon Sep 21 16:09:05.642 UTC 2026` |
| `OverallStatus` | `COMPLETED` |
| `MessageGuid` | `AGqxVqAxtbJ2F-jLgG_R2m19ILXd` |
| `ContextName` | `PIH_SupplierResponse_v1` |
| `TransactionId` | `3b7800a537f8404996dc50778f90a578` |
| `IntermediateError` | `false` |
| `LogLevel` | **`INFO`** |

**This is Tier-1 execution-window evidence, and its limits are stated rather than glossed.** The message carries a Cloud Integration `CorrelationId` of `AGqxVqA416DICAQJfhQtlzAAGf7F`. **That is a CPI-internal identifier and it is NOT equal to the application `X-Correlation-ID`, correlation A.** No claim of equality is made anywhere. Custom correlation indexing is Phase 7.7 work and has not happened.

**Trace was not enabled and was not required for this run.** `LogLevel INFO` above records that. Tier 2 was therefore not used, and the association between correlation **A** and this message rests on the execution window, the correct iFlow, exactly one relevant execution, `COMPLETED` status, and the real transport's own `HTTP 204` — an evidence chain, not a direct correlation read.

#### SAP after the first real send

`Status SENT`, `SupplierResponse ACCEPTED`, `EstimatedDeliveryDate 2026-12-15`, `SupplierRespondedAt 2026-09-21T16:04:53Z`, `LastResponseId a1bd862a-573f-461e-b337-5e39aa595a61`, **`LastResponseVersion 1`**.

```
L1 = 2026-09-21T16:09:00.120564Z        L0 → L1 changed
```

The first real delivery applied the business response, which is the strong branch the design aimed for.

#### Reconciliation

The **deployed** reconciliation command replayed the same durable `responseId` at the normal deadline: *"Replaying `a1bd862a-…` v1 ACCEPTED (attempt 2)"* → `DELIVERED`, `HTTP 204`, *"Resolved: SAP holds this response."*, exit `0`.

```
A = d57bf9b0-9f22-46b8-818e-87234115c75e
B = e4159f7c-1007-49b5-93b3-0fb9a6febefa        A ≠ B
```

#### SAP idempotency — the at-most-once proof

Final SAP read: `Status SENT`, `SupplierResponse ACCEPTED`, `EstimatedDeliveryDate 2026-12-15`, `SupplierRespondedAt 2026-09-21T16:04:53Z`, `LastResponseId a1bd862a-573f-461e-b337-5e39aa595a61`, **`LastResponseVersion 1`**.

```
L0 = 2026-09-19T00:51:08.288116Z
L1 = 2026-09-21T16:09:00.120564Z        L0 ≠ L1
L2 = 2026-09-21T16:09:00.120564Z        L1 == L2
```

`LastResponseVersion` stayed exactly **1** and `LastResponseId` stayed exactly the same. **The reconciliation replay did not apply the supplier response a second time.** This is the runtime at-most-once evidence Phase 7.2 required, and it comes from SAP rather than from CAP's own bookkeeping.

#### Final CAP state

```
responseId a1bd862a-573f-461e-b337-5e39aa595a61
state DELIVERED   attempts 2   lastCorrelationId e4159f7c-…   version 1
decision ACCEPTED   estimatedDeliveryDate 2026-12-15
PENDING_TOTAL 0
ALL_STATES { "DELIVERED": 4, "UNKNOWN": 1 }
```

The remaining `UNKNOWN` is the unrelated `PO00000121` diagnostic below. **It is left in place deliberately** as honest runtime evidence and is not hidden, deleted or reinterpreted.

#### The nine acceptance criteria

| # | Criterion | Result |
| --- | --- | --- |
| 1 | a real `SupplierResponseDeliveries` row reaches `UNKNOWN` | **PASS** |
| 2 | `attempts = 1` | **PASS** |
| 3 | correlation **A** stored | **PASS** — `d57bf9b0-9f22-46b8-818e-87234115c75e` |
| 4 | the same `responseId` is reconciled | **PASS** — `a1bd862a-573f-461e-b337-5e39aa595a61` |
| 5 | correlation **B ≠ A** | **PASS** — `e4159f7c-1007-49b5-93b3-0fb9a6febefa` |
| 6 | `attempts = 2` | **PASS** |
| 7 | final state `DELIVERED` | **PASS** |
| 8 | SAP response applied **at most once** | **PASS** — `LastResponseVersion` stayed `1`, same `LastResponseId` |
| 9 | `LastChangedAt` moves **at most once** | **PASS** — `L0 ≠ L1`, `L1 == L2` |

Procedural gates: one `PENDING` row before the run; `sends=1`; retained send settled `answered=true` / `204`; row still `UNKNOWN` / `attempts 1` / correlation **A** afterwards; Tier-1 Cloud Integration evidence; reconciliation run only after all of those passed. **All satisfied.**

#### What this run did NOT prove

Unchanged from §B and §G, and worth restating beside the result so no later reader over-reads it. The socket stayed open, the real HTTP client waited normally and received `HTTP 204`. **No genuine socket timeout, `AbortSignal` timeout, caller disconnect, client abandonment or lost HTTP response was produced, and Cloud Integration's behaviour after a vanished caller was not observed.** Those remain **Phase 7.9**. The Phase 6 gap is closed on its lifecycle half only.

**The successful proof did not depend on a shortened `PIH_CI_TIMEOUT_MS`.** The retired fixed-timeout strategy played no part in it and must not be restored.

### The abandoned `PO00000121` diagnostic — not an acceptance run

Phase 7.2 was first attempted against `PO00000121`. **That attempt is not the Phase 7.2 proof and is not counted as one.** It is recorded because it is honest runtime evidence and because it uncovered a real defect in legacy persisted data.

The deterministic state-machine injection itself worked exactly as designed: `responseId e0ae42d3-7aef-4299-9d82-80ff7e30b2e7`, correlation **A** `4bb7a6a2-4f4c-4459-995a-1acadd332487`, row `state UNKNOWN`, `attempts 1`. But the retained real transport settled `answered=true`, **`status=400`**, so the mandatory real-send gate returned **`FAIL_HTTP_400`**.

**The gate did its job. Reconciliation was correctly NOT performed, SAP was NOT manually repaired, and no second fixture was consumed on that row.** SAP remained at its original business baseline throughout. A `400` is a deterministic refusal — category **B** in the fault model — and **not** an `UNKNOWN` transport ambiguity; the row's `UNKNOWN` state reflects the injected observation, not the receiver's answer.

The SAP OData error was runtime-proven through `/IWFND/ERROR_LOG`: *"Response belongs to a different portal order."* The Integration Suite transaction ID for that failed send matched the Gateway error-log transaction ID.

**Root cause: legacy delivery-intent identity corruption in `ZJP_PO_DLV`**, not a Phase 7 regression.

| Order | Correct CAP `portalOrderId` | Persisted `PORTAL_ORDER_UUID` |
| --- | --- | --- |
| `PO00000121` | `533572B10BED4083804EE81C917E995A` | `53357200000000000000000000000000` |
| `PO00000122` | `93933DD0AAD349FFBC925DE9787A55C2` | `93933000000000000000000000000000` |
| `PO00000123` | `ED267DA783E24A388CB3DFE095F7A5FC` | **complete** |
| `PO00000132` | `9EFEB59803CF44F881E524C68BCBC176` | **complete** |

Each corrupted value stops at the first lowercase hexadecimal letter of the canonical UUID. The current dispatch-coordinator source already documents the cause: on this SAP target `CL_SYSTEM_UUID=>CONVERT_UUID_C36_STATIC` accepted lowercase canonical input, raised no exception, and could silently return a truncated X16.

**The current coordinator already protects this boundary** — it copies the receipt `portal_order_id` to `SYSUUID_C36`, translates to upper case, converts C36 → X16 and back to C36, and rejects or clears the result if the round trip differs. **No fix is introduced in Phase 7.2**; the defect lives in rows persisted before that guard existed, and the `PO00000121` attempt merely exposed them.

**The `PO00000121` `UNKNOWN` row is left untouched on purpose.** It is why the final census reads `DELIVERED 4, UNKNOWN 1`. Its existence does not affect the isolated `PO00000123` proof, which ran with `PENDING_TOTAL 0` beforehand and `PENDING_TOTAL 0` afterwards.

## Phase 7 acceptance matrix

| Subphase | Runtime acceptance criterion | Blocked by |
| --- | --- | --- |
| **7.1** | Not runtime. **Gate: this document is frozen, every matrix row carries an evidence level, and no executable source changed.** | — |
| 7.2 | **The safety gate passed before anything was sent** — exactly one eligible `PENDING` row, proven to be the fixture by both a read-only query and a normal-deadline dry run. A real `UNKNOWN` row exists in HANA at `attempts 1` carrying correlation **A**; **the retained real send settled `answered = true` with `HTTP 204`** and the row was still `UNKNOWN` afterwards; Cloud Integration evidence confirms that the single execution in the task's window reached `applySupplierResponse`, with correlation **A** read directly under temporary Trace or, if Trace is declined, established by uniqueness and recorded as inference; reconciliation then returns `DELIVERED` at `attempts 2` with the **same** `responseId` and a **fresh** correlation **B ≠ A**; `L0 ≠ L1` and `L1 == L2`, so SAP's `LastChangedAt` moved **at most once** end to end; **no unrelated supplier response changed state**. The unanswered observation is injected at the `ResponseTransport` seam, not at the HTTP client, which waits normally and receives the real result — a real timeout, socket abort, caller disconnect or client abandonment is **not** claimed here and stays in 7.9. **ACHIEVED 2026-09-21** on fixture `PO00000123` / `responseId a1bd862a-573f-461e-b337-5e39aa595a61`: `sends=1`, correlation **A** `d57bf9b0-…`, retained real send `answered=true status=204`, row still `UNKNOWN`/`attempts 1` afterwards, **Cloud Integration evidence taken at Tier 1** (`LogLevel INFO`, Trace not enabled and not required), reconciliation `DELIVERED`/`attempts 2` under **B** `e4159f7c-…`, `LastResponseVersion` stayed `1`, `L0 ≠ L1` and `L1 == L2`, `PENDING_TOTAL 0` | 7.1 |
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

**OQ-3 — what is the real round-trip latency? RESOLVED BY MEASUREMENT, AND IT RETIRED THE MECHANISM THAT ASKED IT.** Three real message-processing logs were captured under temporary Trace, **one of them (Probe A) matched against a CAP-side elapsed measurement**; B and C have Cloud Integration timings only. `T2 − T0` spans 468–1789 ms and `T4 − T0` spans 869–2943 ms. A conservative cross-run argument — using A's **directly measured 963 ms CAP-observed round trip** and nothing but `δout ≥ 0` for B and C — shows that a guaranteed-post-`T2` timeout for B requires `timeout > 1789 ms` while making A's run unanswered requires `timeout < 963 ms`. **No fixed value satisfies both**, and the shortened-`PIH_CI_TIMEOUT_MS` mechanism is therefore **retired**. The derivation is in §C of the Phase 7.2 section; it uses no `T4`-derived bound and makes **no assumption that A's overhead applies to B or C**. `Δ_total_A = 94 ms` is retained there as a measured diagnostic fact only. The question is closed and nothing further needs measuring for 7.2.

**7.2 is complete, and the design held.** It required no code change, no deployment, no SAP change and no Integration Suite change. `ResponseTransport` is a required injectable option on `flushSupplierResponses`, so the one-off scratch task composed the deployed `HttpResponseTransport` behind a state-machine-facing unanswered observation — reusing the deployed payload builder, transport, classifier and guarded write without duplicating any of them. The real transport send was **not** interrupted: it ran concurrently to completion and its retained result settled `HTTP 204`. `PIH_CI_TIMEOUT_MS` was **not** set by that task, and the real send used the normal 30-second deadline. **Next: 7.3, attempt history, not started.**
