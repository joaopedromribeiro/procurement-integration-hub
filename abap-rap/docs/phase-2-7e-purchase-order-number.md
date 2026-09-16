# Phase 2.7E — PurchaseOrderNumber allocation on submit

Status: **SAP runtime-verified complete** for allocation on `DRAFT` → `SUBMITTED`, for the `PO` + 8-digit format, and for preservation of the allocated number across `approve`, `reject`, `cancel`, refused re-submission, refused commercial mutations and refused root `DELETE`. The same run also confirmed Phase 2.7D-2. Phase 2.1–2.7D-1 remain runtime-verified and were not rewritten to achieve this. This subphase closes open issue **OI-02** inside Phase 2, as an implementation rather than a deferment.

> The subphase label *2.7E* was chosen to continue the existing 2.7A–2.7D-2 sequence. The work itself is the approved Phase 2 `PurchaseOrderNumber` decision.

## Target baseline

SAP_BASIS 758 SP01 (SAPK-75801INSAPBASIS), S4CORE 108 SP01 (SAPK-10801INS4CORE), ADT Core 3.60.3 / Business Object Tools 1.209.0, Eclipse 4.40.0. Every statement below is target-specific and must not be generalized.

## Number range configuration (learner-supplied SAP evidence)

| Setting | Value |
| --- | --- |
| Number range object | `ZJP_PO` |
| Interval | `01` |
| Number-length domain | `ZJP_PO_NUMBER_RANGE`, `NUMC(8)` |
| Configured internal interval | `00000001` → `99999999` |
| Buffering | **No buffering** |

Isolated runtime probe on the target: level before `00000000000000000000`; `NUMBER_GET` returned `00000000000000000001`; return code initial/blank; returned quantity `00000000000000000001`; level after `00000000000000000001`.

**`CL_NUMBERRANGE_RUNTIME` returns `NRLEVEL` as a 20-digit value even though the configured business interval is 8 digits.** This is the single most important target fact in this subphase, and the formatting code exists because of it.

## The decision, and the conflict it resolves

**Approved architecture: `PurchaseOrderNumber` is allocated exactly when `DRAFT` → `SUBMITTED` succeeds.**

The repository previously held three different positions on the allocation point, which is why this had to be settled explicitly:

| Source | Previous statement | Resolution |
| --- | --- | --- |
| [domain-model.md](../../docs/architecture/domain-model.md) | "Allocate on first active creation/save as supported" | **Superseded.** Allocation is on submit |
| [ARCHITECTURE.md](../../ARCHITECTURE.md) | "Determinations … allocate display numbers at a documented lifecycle point" | **Superseded.** No determination is used |
| [Phase 2.7A guide](phase-2-7a-submit-action.md), [LEARNINGS.md](../../LEARNINGS.md) | "Submission is the intended/natural allocation point" | **Confirmed.** This is now the rule |

Why submit rather than save: a number drawn at creation is consumed by every abandoned order, and a draft that is never activated would still burn identity. Submission is the first point at which the order becomes a business document that other people refer to.

## Rules

| Property | Value |
| --- | --- |
| Type | `abap.char(20)`, unchanged |
| Consumer access | `field ( readonly )`, unchanged |
| While `Status` is `DRAFT` | initial |
| Allocation point | on a successful `submit` only |
| After allocation | immutable; every later state keeps the same number |
| Format | `PO` + 8 zero-padded digits — `PO00000001` … `PO99999999` |
| Uniqueness authority | the number range object; never `MAX + 1` |
| Gaps | acceptable |
| Reuse | never; a consumed number is never reset or reissued |
| Database unique index | **not** added in this step |
| RAP late numbering | not used |
| Determination | not used |

`PurchaseOrderUUID` remains the technical RAP key. `PurchaseOrderNumber` is only the human-readable display identifier and is never an integration key.

**A consequence worth stating: an order cancelled directly from `DRAFT` never carries a number.** `DRAFT` → `CANCELLED` does not pass through `submit`, so nothing is allocated. That is correct under this rule, not a gap, and the regression asserts it.

## Guard order in `submit`

The Phase 2.7A guards are unchanged in order and in message. Allocation is inserted between the item precondition and the update:

1. technical draft instance → `Submit is not allowed on a draft instance.`
2. root unreadable or not exactly one instance → `Order could not be read; submit not performed.`
3. `Status` is not `DRAFT` → `Only orders in status DRAFT can be submitted.`
4. no items → `Submit requires at least one item.`
5. **draw exactly one number from `ZJP_PO` interval `01`**
6. **build `PO` + 8 digits**
7. **one local-mode `UPDATE FIELDS ( Status PurchaseOrderNumber )`**
8. nested update failed → `Status update failed; rollback this request.`

New failure texts, all leaving the buffer untouched and failing the action:

| Condition | Text |
| --- | --- |
| `CX_NR_OBJECT_NOT_FOUND` | `Number range object ZJP_PO is missing.` |
| `CX_NUMBER_RANGES` | `No purchase order number could be drawn.` |
| Number returned initial | `Number range returned no number; not submitted.` |
| Value wider than the configured 8 digits | `Allocated number is wider than eight digits.` |

Only the two exception classes proven on the target are caught. `CX_NR_OBJECT_NOT_FOUND` is listed before `CX_NUMBER_RANGES` so the more specific case wins.

## Formatting: explicit, not implicit

`NRLEVEL` is 20 digits; the configured interval is 8. The code refuses to let a wider value become a wrong number:

```abap
        IF allocated_number+0(12) <> '000000000000'.
          error_text = 'Allocated number is wider than eight digits.'.
          EXIT.
        ENDIF.
        DATA(order_number) = |PO{ allocated_number+12(8) }|.
```

The leading-zero check is what makes the truncation non-silent: a level outside the configured interval fails the action instead of being silently reduced to its last eight digits. Under the configured `00000001`–`99999999` interval this branch is unreachable, which is exactly why it is cheap to keep.

## Why no precheck or BDEF change was needed

`PurchaseOrderNumber` is already `field ( readonly )` and already mapped, so consumers still cannot write it and no behavior definition line changed. The Phase 2.7B root update precheck filters on `%control` for the five commercial fields only, so the action's own write of `Status` and `PurchaseOrderNumber` passes untouched — the same mechanism that already lets `submit` write `Status` and lets the determinations write `TotalAmount`.

## Test strategy

The number is environmental: the interval's current level depends on every previous run, and gaps are valid. **No test asserts a literal such as `PO00000002`.** Instead each test captures what this run actually drew and compares later lifecycle states against that captured value.

- `read_order_number( uuid )` — read-only `SELECT SINGLE` of the persisted number.
- `check_number_format( number )` — structural check only: `PO` in the first two characters, eight digits in the next eight, blanks after.
- `check_submit_database` and `check_decision_database` gained an optional `expected_number`. An initial value means *the row must still carry no number*, which is the correct expectation for any order that has not been through a successful submit — so every `DRAFT`-stage call site kept working unchanged.

Coverage added:

| Case | Assertion |
| --- | --- |
| `DRAFT` fixtures | number still initial |
| Successful `submit` | number non-initial and `PO` + 8 digits |
| Refused re-`submit` | number unchanged |
| Rejected commercial mutations on `SUBMITTED` | number unchanged |
| `approve`, `reject`, `cancel` | number identical to the one captured at submit |
| Refused root `DELETE` on terminal fixtures | number unchanged |
| `DRAFT` → `CANCELLED` | number still initial — never submitted |
| Final lifecycle summary | prints real numbers instead of `-` |

`ZJP_CL_PO_DRAFT_PROBE` is unchanged: it contains no reference to `PurchaseOrderNumber` and no assertion there depends on it.

## Exact ADT objects and activation order

1. The number range object **`ZJP_PO`** with interval **`01`** and domain **`ZJP_PO_NUMBER_RANGE`** must already exist on the target. It is maintained in SAP configuration, not in this repository, and there is no repository artifact for it.
2. Update **Behavior Implementation class ZBP_I_PURCHASEORDER**, Local Types, from [zbp_i_purchaseorder.clas.locals_imp.abap](../classes/zbp_i_purchaseorder.clas.locals_imp.abap): `METHOD submit` only. No other method, and no behavior definition change.
3. Update and activate **ZJP_CL_PO_EML_TEST** in the same round.
4. Run the active test, then the draft test.

No BDEF, CDS, table, service or projection change is required.

## Runtime evidence

The learner ran both console classes on the recorded target and reported the following. No independent SAP execution is claimed here.

**Regression:** zero `STOP` markers in either class. The Phase 2.3–2.7D-2 regression stayed green.

**Allocation and immutability, `ZJP_CL_PO_EML_TEST`:**

| Case | Result |
| --- | --- |
| Successful `submit` | Allocated a number in format `PO` + 8 digits |
| First integrated number observed | `PO00000002` — `PO00000001` had already been consumed by the isolated number-range probe |
| Refused re-`submit` | Original number kept |
| Rejected commercial mutations on `SUBMITTED` | Original number kept |
| `APPROVED` | Number preserved |
| `REJECTED` | Number preserved |
| `SUBMITTED` → `CANCELLED` | Number preserved |
| `APPROVED` → `CANCELLED` | Number preserved |
| `DRAFT` → `CANCELLED` | **Remained without a number** |

Final lifecycle summary from that run:

```text
SUP010 APPROVED  PO00000004
SUP011 REJECTED  PO00000005
SUP012 CANCELLED <initial>
SUP013 CANCELLED PO00000006
SUP014 CANCELLED PO00000007
SUP015 REJECTED  PO00000008
```

`SUP012` is the fixture cancelled directly from `DRAFT`. Its blank number is the rule working, not a defect. The gap between `PO00000002` and `PO00000004` is the accepted consequence of drawing before the buffer update.

**Technical draft, `ZJP_CL_PO_DRAFT_PROBE`:** its submitted fixture received `PO00000009`, and a technical draft created from that `SUBMITTED` active order carried `PurchaseOrderNumber = PO00000009`, `Status = SUBMITTED` and `TotalAmount = 1500`. Draft commercial immutability stayed green. This extends the Phase 2.7B finding: a draft taken from a submitted order inherits the business identity as well as the business status.

Runtime-verified markers:

```text
PASS: submit allocated PurchaseOrderNumber as PO + 8 digits.
PASS: a refused re-submit kept the original PO number.
PASS: rejected mutations left the PO number untouched.
PASS: a cancelled DRAFT carries no PurchaseOrderNumber.
PASS: PurchaseOrderNumber is allocated on submit only.
PASS: Phase 2.7B draft immutability verified.
PASS: Phase 2.7D-2 SUBMITTED root DELETE rejected; row kept.
```

## Questions answered by the run, and those still open

**Answered.** The call compiles and executes with `number` as its single importing parameter. A number-range draw inside a RAP action handler is tolerated on this target: both console classes completed with committed persistence and no dump, and no `COMMIT` or `ROLLBACK` was written in the handler. Offset/length on `NRLEVEL` behaved as the 20-digit probe predicted, and the formatting produced the approved `PO` + 8-digit values end to end.

**Still open, and not claimed.**

- **`returncode` and `returned_quantity` are deliberately not requested.** The isolated run returned a blank code; interpreting non-blank values has no evidence here, and treating a near-exhaustion warning as a failure would wrongly refuse a valid number. Hard failures surface as `CX_NUMBER_RANGES`. The two exception paths and the wider-than-8-digits guard were never triggered by this run, so they are compiler-accepted and reasoned, not runtime-exercised.
- **Uniqueness is unenforced at the database level.** There is no index and no unique constraint on `purchase_order_number`; the number range object is the sole uniqueness authority. No index was added in Phase 2.
- **Number consumption per run.** Each full run consumes roughly eight numbers, more if a run fails partway. Gaps are expected and accepted.
- **No multi-user or concurrency coverage is claimed**, including two sessions submitting at once. The number range is concurrency-safe by construction; that property was not tested here.
