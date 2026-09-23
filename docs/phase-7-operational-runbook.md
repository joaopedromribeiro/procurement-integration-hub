# Phase 7 operational runbook

Status: Phase 7 CLOSED within its documented acceptance scope on 2026-09-23. ACTIVE SAP mirrors and both final deployed iFlow exports are synchronized; the complete unchanged CAP suite passed 231/231 tests in 44 suites.

Evidence labels are strict: **RUNTIME-VERIFIED** means already executed against deployed SAP, CAP/HANA or Cloud Integration; **LOCAL-AUTOMATED** means local code plus an in-memory database or fake transport; **SOURCE-PREPARED** means complete local source/export awaiting activation or deployment; **UNTESTED** means no result is claimed yet.

## Observe before acting

Run the CAP/HANA read-only report with:

```text
cf run-task cap-supplier-portal-srv --command "npm run operational-status:prod" --name pih-phase7-status
cf logs cap-supplier-portal-srv --recent
```

It reports state census, before-due, retry-exhausted, retry-window-blocked, live/stale leases, `UNKNOWN`, per-delivery history count and last correlation. **RUNTIME-VERIFIED** with `operational-status:prod`.

Run `ZJP_CL_DELIVERY_STATUS` in ADT for read-only SAP delivery state, `AttemptCount`, `NextAttemptAt`, `RetryWindowStartedAt`, lease status and `LastCorrelationId`. **RUNTIME-VERIFIED**.

In Cloud Integration Monitor, search custom header `X-Correlation-ID` using the durable row's last correlation. The SAP persisted `LastCorrelationId` for the 7.6 recovery matched the CAP request's `X-Correlation-ID` (`37FC3FA8EB2D1FD1ADDDABB98EC8F0E8`). Do not infer an indexed MPL search result beyond separately captured monitoring evidence.

## CAP inbound response branches

| Observation | Operator action | Evidence |
| --- | --- | --- |
| `PENDING`, eligible | Run one explicit `flush-supplier-responses.js --limit 1` task | Deployed race **RUNTIME-VERIFIED**: one owner, one skip, one attempt/history |
| `PENDING`, before due | Wait until `nextAttemptAt`, then run one flush | **LOCAL-AUTOMATED** |
| `PENDING`, retry-exhausted | Do not reset attempts; inspect history/correlation and correct the upstream cause | Classification **LOCAL-AUTOMATED**; recovery **UNTESTED** |
| `PENDING`, retry-window-blocked | Do not edit timestamps; retain the row as evidence and escalate | **LOCAL-AUTOMATED** |
| `IN_FLIGHT`, live lease | Do nothing; another runner owns it | **LOCAL-AUTOMATED** |
| `IN_FLIGHT`, stale lease | Run one explicit flush; it reclaims the same row and identity | **RUNTIME-VERIFIED**: abandoned lease expired, one real attempt, lease cleared |
| `UNKNOWN` | Run only `npm run reconcile-response -- --response-id <UUID>` after inspecting correlation | Lifecycle/idempotency **RUNTIME-VERIFIED** by 7.2/7.3 |
| `FAILED` | Do not replay unchanged content; correct the business or contract cause | Existing deterministic cases **RUNTIME-VERIFIED** |
| `DELIVERED` | No action | **RUNTIME-VERIFIED** |

Never use raw persistence updates to change a CAP response state. Dry-run remains write-free: `node scripts/flush-supplier-responses.js --dry-run`.

## SAP outbound delivery branches

| Observation | Operator action | Evidence |
| --- | --- | --- |
| `PENDING`, eligible | Run the existing single-delivery coordinator entry point once | Coordinator lifecycle **RUNTIME-VERIFIED** |
| `PENDING`, deferred/exhausted/window-blocked | Respect reported fields; never clear evidence manually | Phase 7.4c owner-reported **RUNTIME-VERIFIED**; ACTIVE ADT mirrors synchronized |
| `IN_FLIGHT`, live | Do nothing | Single-runner lease **RUNTIME-VERIFIED**; concurrent proof **UNTESTED** |
| `IN_FLIGHT`, stale | Let the coordinator reclaim the same `DeliveryUUID` | Single-runner reclaim **RUNTIME-VERIFIED**; deployed race **UNTESTED** |
| `UNKNOWN`, current header `ERROR/UNKNOWN` | Do **not** run the generic `ZJP_CL_DELIVERY_RECOVERY` with multiple UNKNOWN rows; it fails closed unless exactly one exists globally. Inspect the target and use only a separately reviewed, exact-identity operator procedure if recovery is authorized. Never mutate a snapshot to manufacture success. | Recovery mechanism **RUNTIME-VERIFIED** on one targeted intent; generic runner correctly ineligible with 21 UNKNOWN |
| `FAILED` | Diagnose the deterministic refusal; `retryDelivery` refuses it | ACTIVE source synchronized; negative guard not separately exercised in this acceptance |
| `DELIVERED` / `SENT` | No action; late retry is refused | ACTIVE source synchronized; negative guard not separately exercised in this acceptance |

`retryDelivery` never calls `sendToSupplier`, creates no intent, and writes only the existing intent to `PENDING` plus header `IntegrationStatus = PENDING`. The runner commits that preparation and calls the coordinator exactly once for the same `DeliveryUUID`.

## Timeout and OQ-2 policy

- CAP sender → inbound iFlow: 35,000 ms.
- Both iFlow transaction timeouts: 25 s.
- Outbound iFlow → CAP: 15,000 ms.
- Inbound iFlow → SAP CSRF GET and action POST: 10,000 ms each.
- Pooled connection idle timeout remains 300,000 ms.
- SAP coordinator → outbound iFlow keeps the platform default. `EXECUTE` exposes `I_TIMEOUT`, but its unit is not authoritative on this target. Never guess 35 seconds and never use `RETRY_EXECUTE`.

The inbound iFlow sets `PihFailureStage = CSRF_FETCH` before the GET and `AFTER_CSRF` only after the GET succeeds. Its Exception Subprocess returns HTTP 503 with JSON code `UPSTREAM_CSRF_UNAVAILABLE` and `retryable: true` only for `CSRF_FETCH`; every later exception is rethrown so a possibly applied POST is never flattened into safe non-delivery. `retryOnException` stays false. OQ-2 runtime acceptance was completed, the tenant flow restored, and the final deployed SupplierResponse export verified with its normal CSRF service root and no temporary override.

## Correlation and history

Business identity never changes across replay: outbound `DeliveryUUID`, inbound `responseId`. Correlation identity changes on every attempt. Business identity finds the durable row; its history/last fields provide the correlation ID; that ID finds the Message Processing Log. Two-attempt inbound history and at-most-once SAP application are **RUNTIME-VERIFIED** by 7.3. The 7.6 SAP `LastCorrelationId` matched the CAP request header; indexed MPL search must be cited from its own monitor evidence, not inferred from that match.

## Phase 7.9 final results and evidence limits

1. Phase 7.5 concurrent drainers **PASS**: one worker owned the claim, the competing runner skipped, and exactly one transport attempt/history entry persisted. Stale-lease reclaim **PASS**: an intentionally abandoned `IN_FLIGHT` lease expired, the next runner reclaimed it, made one real attempt and cleared the lease.
2. Phase 7.6 recovery mechanism **PASS**, not a delivered-success proof. The existing UNKNOWN intent `37FC3FA8EB2D1FE1ADD3A6790C9BD871` for order `37FC3FA8EB2D1FE1ADD3A6790C9A3871` was reused with no new intent; one `retryDelivery` preparation and one coordinator dispatch changed attempts 1 → 2. The answer was HTTP 400 `UNKNOWN_SUPPLIER`, `answered=true`, correctly persisted `FAILED`. Correlation `37FC3FA8EB2D1FD1ADDDABB98EC8F0E8` matched SAP `LastCorrelationId` and CAP `X-Correlation-ID`.
3. UNKNOWN → DELIVERED **not demonstrated**: all remaining UNKNOWN snapshots refer to SUP044, SUP074A or SUP074H, none active in the CAP portal. Neither supplier master data nor durable snapshots were changed. Do not retry the already-tested FAILED delivery.
4. Both status reporters **RUNTIME-VERIFIED**. Final SAP: PENDING=85, IN_FLIGHT=5, DELIVERED=24, FAILED=32, UNKNOWN=21, live leases=0, stale leases=5. The historical stale leases are out of scope. Final CAP: DELIVERED=5, UNKNOWN=1, PENDING=3, retryWindowBlocked=3, live leases=0, stale leases=0, historyCount=5. The historical Phase 7.2 UNKNOWN remains untouched.
5. ACTIVE ADT sources and both final deployed iFlow exports are synchronized. The restored SupplierResponse ZIP passed normal-CSRF-target, stage handling, timeout, correlation, ZIP/XML and no-fault-injection checks; OrderDelivery remains consistent. The complete unchanged CAP suite passed outside the Codex host: 231/231 tests, 44 suites, 0 failed/cancelled/skipped/todo, duration 6865.0322 ms. Typecheck, production CDS build and `git diff --check` passed. The earlier Windows `tsx`/`uv_os_get_passwd` ENOMEM prevented test startup only on the Codex host. No runtime mutation is authorized by this runbook entry.
