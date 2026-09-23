/**
 * Phase 6.5e — the supplier-response sender.
 *
 * ARCHITECTURE.md fixes the shape: *"A CAP development command can similarly
 * flush a committed response. Automatic scheduling is a later enhancement."*
 * So this drains the durable outbox when it is explicitly run, and nothing here
 * is a timer, a queue worker or an HTTP endpoint.
 *
 * The rule the whole file exists to keep: a transport outcome must never touch
 * the supplier's committed business decision. The supplier action already wrote
 * the order and its response row in one transaction; this code writes the
 * transport columns of `SupplierResponseDeliveries` and reads everything else.
 * `Orders` is never updated here — not on success, not on a refusal, not on a
 * conflict. A failed delivery means SAP has not heard about a decision, not
 * that the decision is any less made.
 */

import cds from '@sap/cds'
import { randomUUID } from 'node:crypto'
import {
  Orders as PortalOrders,
  SupplierResponseDeliveries,
  SupplierResponseDeliveryAttempts,
  Suppliers
} from '#cds-models/pih/portal'
import type { ResponseTransport } from './ci-transport'
import {
  calculateRetryTiming,
  parseRetryAfter,
  retryEligibility,
  type JitterSelector
} from './retry-policy'
import {
  buildSupplierResponsePayload,
  categorise,
  classify,
  describe,
  PayloadError,
  type AttemptErrorCategory,
  type DeliveryState,
  type ResponseOrder,
  type ResponseRow,
  type SupplierResponsePayload
} from './supplier-response'

/**
 * Phase 7.3 — what one committed attempt is recorded as, beyond the durable
 * state the parent already carries. Passed as one object rather than six more
 * positional arguments, because `record` already takes five and a seventh
 * unnamed string is how the wrong value ends up in the wrong column.
 *
 * `attemptNumber` is deliberately absent: it is derived inside the transaction
 * from the same expression that writes the parent's `attempts`, so the two
 * cannot disagree.
 */
interface AttemptFacts {
  startedAt: string
  completedAt: string
  durationMs: number
  httpStatus: number | null
  errorCategory: AttemptErrorCategory
  correlationId: string | null
  jitter?: JitterSelector
  retryAfterDue?: Date | null
}

/** Wall clock for the record, monotonic clock for the elapsed time. */
function elapsedMs(from: number): number {
  return Math.max(0, Math.round(performance.now() - from))
}

/** What one row's attempt did, for the command's report and for the tests. */
export interface AttemptOutcome {
  responseId: string
  portalOrderId: string
  version: number
  decision: string
  /** Fresh for every attempt. Absent when the row was skipped or not sent. */
  correlationId?: string
  state: DeliveryState | 'SKIPPED'
  status?: number
  error?: string | null
  /** Present on a dry run, so an operator can read the exact bytes first. */
  payload?: SupplierResponsePayload
  /** The guarded write matched nothing: someone else moved the row mid-attempt. */
  conflicted?: boolean
}

export interface FlushSummary {
  scanned: number
  delivered: number
  failed: number
  pending: number
  unknown: number
  skipped: number
  beforeDue: number
  retryExhausted: number
  retryWindowBlocked: number
  outcomes: AttemptOutcome[]
}

export interface FlushOptions {
  transport: ResponseTransport
  /** Maximum rows to attempt in one run. */
  limit?: number
  /** Builds the payload and reports it without sending anything. */
  dryRun?: boolean
  /** Injected so tests can assert a fresh correlation ID per attempt. */
  newCorrelationId?: () => string
  /** Invocation and persistence clock, injected for boundary tests. */
  now?: () => Date
  /** Positive jitter selector, injected so tests never depend on randomness. */
  jitter?: JitterSelector
  /** Stable owner for every claim made by this invocation. */
  leaseOwner?: string
  /** Bounded claim lifetime. Injected by tests; no scheduler is implied. */
  leaseMs?: number
  log?: (line: string) => void
}

export const DEFAULT_LIMIT = 50
export const DEFAULT_LEASE_MS = 60_000

/**
 * Drains PENDING supplier responses.
 *
 * PENDING means both "never attempted" and "attempted and retryable", which is
 * the same vocabulary the ABAP coordinator uses on the outbound leg. DELIVERED,
 * FAILED and UNKNOWN rows are never picked up: a delivered row must not be
 * resent, and a failed or ambiguous one needs reconciliation rather than a
 * blind replay. Returning either to PENDING is a deliberate operator act and
 * this command does not do it by itself.
 */
export async function flushSupplierResponses(options: FlushOptions): Promise<FlushSummary> {
  const {
    transport,
    limit = DEFAULT_LIMIT,
    dryRun = false,
    newCorrelationId = randomUUID,
    now = () => new Date(),
    jitter,
    leaseOwner = randomUUID(),
    leaseMs = DEFAULT_LEASE_MS,
    log = () => {}
  } = options

  if (!Number.isInteger(leaseMs) || leaseMs <= 0) {
    throw new Error('leaseMs must be a positive whole number of milliseconds.')
  }

  const summary: FlushSummary = {
    scanned: 0, delivered: 0, failed: 0, pending: 0, unknown: 0, skipped: 0,
    beforeDue: 0, retryExhausted: 0, retryWindowBlocked: 0, outcomes: []
  }

  // Oldest first, and within one order by version ascending. An acceptance must
  // reach SAP before the date update that supersedes it, and `createdAt` alone
  // would rely on two rows never sharing a timestamp.
  const selected = (await SELECT
    .from(SupplierResponseDeliveries)
    .where({ state: { in: ['PENDING', 'IN_FLIGHT'] } })
    .orderBy('createdAt', 'version')) as unknown as ResponseRow[]

  const invokedAt = now()
  // Keep live leases in the ordered set even though they cannot be claimed: an
  // earlier live version must still block a later response for the same order.
  const rows = selected

  if (!rows.length) {
    log('No PENDING supplier responses.')
    return summary
  }

  // One invocation observes one instant. A row cannot move from before-due to
  // due merely because another row took time to send during this same drain.
  for (const row of rows) {
    if (row.state === 'IN_FLIGHT' && !leaseExpired(row, invokedAt)) continue
    const eligibility = candidateEligibility(row, invokedAt)
    if (eligibility === 'BEFORE_DUE') summary.beforeDue++
    else if (eligibility === 'RETRY_EXHAUSTED') summary.retryExhausted++
    else if (eligibility === 'RETRY_WINDOW_BLOCKED') summary.retryWindowBlocked++
  }

  const orders = await readOrders(rows)

  // Once a response for an order does not reach SAP, every later response for
  // that same order is held back. Sending version 2 while version 1 is still
  // PENDING would make SAP refuse version 1 on the next run as stale, leaving a
  // row permanently FAILED for a decision that was in fact superseded rather
  // than rejected — a bookkeeping lie the outbox would never recover from.
  //
  // THIS GUARD IS WITHIN ONE RUN ONLY, and the scope is worth being exact
  // about. If version 1 ends FAILED or UNKNOWN it leaves the PENDING set
  // entirely, so a later run sees version 2 with nothing in front of it and
  // sends it. That is deliberate and contract-permitted — API_CONTRACTS.md
  // states that a newer response "contains the complete current supplier
  // response, so version gaps can be applied after validating the allowed
  // state" — and blocking it would instead strand the order behind a failure
  // that the newer response already supersedes. What it is NOT is a guarantee
  // that SAP sees every version in order; reconciling a FAILED or UNKNOWN row
  // against what SAP actually holds is a Phase 6.5f obligation.
  const blocked = new Set<string>()
  let attempted = 0

  for (const row of rows) {
    if (row.state === 'IN_FLIGHT' && !leaseExpired(row, invokedAt)) {
      blocked.add(row.order_ID)
      log(`WAIT  ${row.responseId} v${row.version} — another runner holds a live lease.`)
      continue
    }

    const eligibility = candidateEligibility(row, invokedAt)

    if (blocked.has(row.order_ID)) {
      if (eligibility === 'ELIGIBLE' && attempted < limit) {
        summary.skipped++
        summary.scanned++
        summary.outcomes.push({
          responseId: row.responseId,
          portalOrderId: row.order_ID,
          version: row.version,
          decision: row.decision,
          state: 'SKIPPED',
          error: 'An earlier response for this order has not reached SAP yet.'
        })
        log(`SKIP  ${row.responseId} v${row.version} — an earlier response for this order is still pending.`)
      }
      continue
    }

    if (eligibility !== 'ELIGIBLE') {
      blocked.add(row.order_ID)
      const reason: Record<string, string> = {
        BEFORE_DUE: 'its retry eligibility time has not arrived',
        RETRY_EXHAUSTED: 'its four-attempt budget is exhausted',
        RETRY_WINDOW_BLOCKED: 'its 15-minute retry window is exhausted'
      }
      log(`WAIT  ${row.responseId} v${row.version} — ${reason[eligibility]}.`)
      continue
    }

    if (attempted >= limit) continue
    attempted++
    summary.scanned++

    if (!dryRun) {
      const claimed = await claim(row, leaseOwner, invokedAt, leaseMs)
      if (!claimed) {
        summary.skipped++
        summary.outcomes.push({
          responseId: row.responseId,
          portalOrderId: row.order_ID,
          version: row.version,
          decision: row.decision,
          state: 'SKIPPED',
          error: 'another runner owns the delivery claim'
        })
        log(`SKIP  ${row.responseId} v${row.version} — another runner owns the claim.`)
        blocked.add(row.order_ID)
        continue
      }
    }

    const outcome = await attempt(row, orders.get(row.order_ID), {
      transport, dryRun, newCorrelationId, now, jitter, log,
      expectedState: dryRun ? String(row.state) as DeliveryState : 'IN_FLIGHT',
      leaseOwner: dryRun ? undefined : leaseOwner
    })

    summary.outcomes.push(outcome)

    if (outcome.state === 'DELIVERED') summary.delivered++
    else if (outcome.state === 'FAILED') { summary.failed++; blocked.add(row.order_ID) }
    else if (outcome.state === 'PENDING') { summary.pending++; blocked.add(row.order_ID) }
    else if (outcome.state === 'UNKNOWN') { summary.unknown++; blocked.add(row.order_ID) }
    else summary.skipped++
  }

  if (summary.scanned === 0) {
    log(
      `No eligible PENDING supplier responses` +
      ` (before-due ${summary.beforeDue}, retry-exhausted ${summary.retryExhausted}, ` +
      `retry-window-blocked ${summary.retryWindowBlocked}).`
    )
  }

  return summary
}

function leaseExpired(row: ResponseRow, now: Date): boolean {
  if (!row.leaseExpiresAt) return false
  const expires = row.leaseExpiresAt instanceof Date ? row.leaseExpiresAt : new Date(row.leaseExpiresAt)
  return !Number.isNaN(expires.getTime()) && expires.getTime() <= now.getTime()
}

function candidateEligibility(row: ResponseRow, now: Date) {
  return retryEligibility({ ...row, state: 'PENDING' }, now)
}

/** Atomic PENDING claim or expired-IN_FLIGHT reclaim. */
async function claim(row: ResponseRow, owner: string, now: Date, leaseMs: number): Promise<boolean> {
  const leaseExpiresAt = new Date(now.getTime() + leaseMs).toISOString()
  let update = UPDATE(SupplierResponseDeliveries).set({
    state: 'IN_FLIGHT', leaseOwner: owner, leaseExpiresAt
  } as any).where({ ID: row.ID, state: row.state })

  if (row.state === 'IN_FLIGHT') {
    update = update.and({ leaseExpiresAt: { '<=': now.toISOString() } })
  }

  return Number(await update) === 1
}

/** Resolves each row's order and the order's supplier code, in two queries. */
async function readOrders(rows: ResponseRow[]): Promise<Map<string, ResponseOrder>> {
  const orderIds = [...new Set(rows.map(row => row.order_ID))]

  const orders = await SELECT
    .from(PortalOrders)
    .columns('ID', 'sourceSystem', 'sourceOrderId', 'sourceRevision', 'deliveryId', 'supplier_ID')
    .where({ ID: { in: orderIds } })

  const supplierIds = [...new Set(orders.map((order: any) => order.supplier_ID).filter(Boolean))]
  const suppliers = supplierIds.length
    ? await SELECT.from(Suppliers).columns('ID', 'supplierCode').where({ ID: { in: supplierIds } })
    : []

  const codeById = new Map(suppliers.map((supplier: any) => [supplier.ID, supplier.supplierCode]))

  return new Map(orders.map((order: any) => [order.ID, {
    ID: order.ID,
    sourceSystem: order.sourceSystem,
    sourceOrderId: order.sourceOrderId,
    sourceRevision: order.sourceRevision,
    deliveryId: order.deliveryId,
    supplierCode: codeById.get(order.supplier_ID)
  } as ResponseOrder]))
}

/**
 * One row: build, send, classify, record.
 *
 * Shared by the normal flush and by operator reconciliation, which differ only
 * in which state they expect the row to be in. Everything that decides what a
 * transport outcome means lives here and is never duplicated: the payload, the
 * fresh correlation ID, `classify`, `describe` and the guarded write.
 */
async function attempt(
  row: ResponseRow,
  order: ResponseOrder | undefined,
  context: Required<Pick<FlushOptions, 'transport' | 'dryRun' | 'newCorrelationId' | 'log'>>
    & Pick<FlushOptions, 'jitter'>
    & { expectedState: DeliveryState; leaseOwner?: string; now: () => Date }
): Promise<AttemptOutcome> {
  const base = {
    responseId: row.responseId,
    portalOrderId: row.order_ID,
    version: row.version,
    decision: row.decision
  }

  // The attempt starts HERE, before the payload is built, so a payload that
  // cannot be built has a real measured duration rather than a manufactured
  // zero. An attempt is a delivery attempt, not only its socket time.
  const startedAt = context.now().toISOString()
  const startedMonotonic = performance.now()

  // A row that cannot be turned into a payload is a deterministic failure. It
  // is recorded as FAILED with the reason and never as PENDING, because no
  // amount of retrying makes a missing supplier code appear, and never as
  // DELIVERED, because nothing was sent.
  let payload: SupplierResponsePayload
  try {
    payload = buildSupplierResponsePayload(row, order as ResponseOrder)
  } catch (error: any) {
    const reason = error instanceof PayloadError ? `${error.code}: ${error.message}` : String(error?.message ?? error)

    // A dry run inspects; it does not decide. Without this guard a malformed
    // payload would be the one path on which `--dry-run` writes to the database
    // — driving the row terminal and consuming an attempt number that no
    // operator asked to spend. The payload is still BUILT above, because
    // reporting that it cannot be built is exactly what a dry run is for.
    //
    // `FAILED` here is the REPORT, not the durable state: it keeps the command's
    // summary counter and its non-zero exit for malformed data, while the
    // persisted row stays untouched. Nothing below this line runs.
    if (context.dryRun) {
      context.log(`DRY   ${row.responseId} v${row.version} — payload invalid, not sent and not recorded: ${reason}`)
      return { ...base, state: 'FAILED', error: reason }
    }

    // Nothing was sent, so a lost race here costs nothing but the bookkeeping.
    // PAYLOAD is supplied directly rather than through `categorise`, because
    // there is no TransportResult to categorise: the attempt ended before one
    // could exist.
    await record(row, 'FAILED', reason.slice(0, 255), null, context.expectedState, context.leaseOwner, {
      startedAt,
      completedAt: context.now().toISOString(),
      durationMs: elapsedMs(startedMonotonic),
      httpStatus: null,
      errorCategory: 'PAYLOAD',
      correlationId: null,
      jitter: context.jitter,
      retryAfterDue: null
    })
    context.log(`FAIL  ${row.responseId} v${row.version} — ${reason}`)
    return { ...base, state: 'FAILED', error: reason }
  }

  if (context.dryRun) {
    context.log(`DRY   ${row.responseId} v${row.version} ${row.decision} — not sent.`)
    return { ...base, state: 'SKIPPED', payload, error: 'dry run' }
  }

  // One attempt, one fresh correlation ID. It identifies this attempt in the
  // Cloud Integration message log and nothing else; `responseId` is unchanged
  // and is what makes the replay idempotent at the RAP end.
  const correlationId = context.newCorrelationId()

  const result = await context.transport.send(payload, correlationId)
  const completedAt = context.now().toISOString()
  const state = classify(result)
  const error = describe(result)
  const retryAfterDue = result.answered === true && state === 'PENDING'
    ? parseRetryAfter(result.retryAfter, new Date(completedAt))
    : null

  // The parent's state and the history row's outcome are the SAME classified
  // value, passed once. They cannot drift because there is only one `state`.
  const written = await record(row, state, error, correlationId, context.expectedState, context.leaseOwner, {
    startedAt,
    completedAt,
    durationMs: elapsedMs(startedMonotonic),
    httpStatus: result.answered && result.status !== undefined ? result.status : null,
    errorCategory: categorise(result),
    correlationId,
    jitter: context.jitter,
    retryAfterDue
  })

  if (!written) {
    // The request went out and somebody else owns the row now. Do NOT force the
    // write: whatever moved it did so with knowledge this call no longer has.
    // The row keeps its `responseId`, so nothing is lost that a later replay
    // cannot recover, and RAP answers a duplicate with ALREADY_APPLIED.
    const note =
      `the row left ${context.expectedState} while this attempt was in flight; ` +
      `its result (${state}, correlation ${correlationId}) was NOT written`
    context.log(`RACE  ${row.responseId} v${row.version} — ${note}`)
    return { ...base, correlationId, state, status: result.status, error, conflicted: true }
  }

  context.log(
    `${state.padEnd(5)} ${row.responseId} v${row.version} ${row.decision}` +
    ` — ${result.answered ? `HTTP ${result.status}` : 'no answer'} (correlation ${correlationId})`
  )

  return { ...base, correlationId, state, status: result.status, error }
}

// ------------------------------------------------------- operator reconciliation

/** Why a reconciliation was refused before anything was sent. */
export type ReconcileRefusal =
  | 'MISSING_RESPONSE_ID'
  | 'NOT_FOUND'
  | 'NOT_UNKNOWN'
  | 'ORDER_UNREADABLE'
  | 'STATE_CHANGED'

export interface ReconcileOptions {
  /** The durable response to replay. Never generated, always supplied. */
  responseId: string
  transport: ResponseTransport
  newCorrelationId?: () => string
  log?: (line: string) => void
}

export interface ReconcileResult {
  refused?: ReconcileRefusal
  message?: string
  outcome?: AttemptOutcome
}

/**
 * Resolves ONE `UNKNOWN` delivery, by replaying it.
 *
 * `UNKNOWN` means the receiver may or may not have committed, and the sender
 * refuses to guess — so nothing drains it automatically and this is the only
 * way it moves. It is an operator action by design.
 *
 * **It does not ask SAP anything.** CAP has no direct dependency on SAP and
 * gains none here; Cloud Integration stays the only mediation layer. The
 * question "did SAP already get this?" is answered by SENDING IT AGAIN rather
 * than by reading SAP, which is sound because RAP's idempotency is
 * runtime-proven: the same `responseId` with the same content returned HTTP 204
 * with `LastChangedAt` unmoved. So if the original landed, the replay is a
 * no-op; if it never landed, the replay applies it; and if the answer is
 * ambiguous again, the row simply stays `UNKNOWN` and nothing has been lost.
 *
 * Nothing about the supplier's decision is re-made. The payload is rebuilt from
 * the same durable row, under the same `responseId`, at the same version, and
 * `Orders` is never touched. Only the transport columns move.
 */
export async function reconcileSupplierResponse(options: ReconcileOptions): Promise<ReconcileResult> {
  const { responseId, transport, newCorrelationId = randomUUID, log = () => {} } = options

  if (!responseId || !responseId.trim()) {
    return { refused: 'MISSING_RESPONSE_ID', message: 'A responseId must be supplied explicitly.' }
  }

  const row = (await SELECT.one
    .from(SupplierResponseDeliveries)
    .where({ responseId: responseId.trim() })) as unknown as ResponseRow | null

  if (!row) {
    return { refused: 'NOT_FOUND', message: `No supplier response exists with responseId ${responseId}.` }
  }

  // Only UNKNOWN is reconcilable, and each refusal says why in its own terms.
  if (row.state !== 'UNKNOWN') {
    const because: Record<string, string> = {
      DELIVERED: 'it already reached SAP; replaying it would be a pointless duplicate',
      FAILED: 'SAP refused it deterministically, so a replay would be refused identically — ' +
              'the payload or the order state has to change first, which is a business decision, not a transport one',
      PENDING: 'it is still queued and the normal flush will send it'
    }
    return {
      refused: 'NOT_UNKNOWN',
      message:
        `Response ${responseId} is ${row.state}, not UNKNOWN: ` +
        `${because[String(row.state)] ?? 'only an UNKNOWN delivery can be reconciled'}.`
    }
  }

  const order = (await readOrders([row])).get(row.order_ID)
  if (!order) {
    return { refused: 'ORDER_UNREADABLE', message: `Response ${responseId} points at no readable order.` }
  }

  log(`Replaying ${responseId} v${row.version} ${row.decision} (attempt ${(row.attempts ?? 0) + 1}).`)

  const outcome = await attempt(row, order, {
    transport,
    dryRun: false,
    newCorrelationId,
    now: () => new Date(),
    jitter: undefined,
    log,
    // The compare-and-set guard: this write lands only if the row is still the
    // UNKNOWN one that was read a moment ago.
    expectedState: 'UNKNOWN'
  })

  if (outcome.conflicted) {
    return { refused: 'STATE_CHANGED', message: outcome.error ?? 'the row changed during the attempt', outcome }
  }

  return { outcome }
}

/**
 * Persists the transport outcome for one row, and only the transport outcome.
 *
 * Each row commits in its own transaction, so a crash part-way through a flush
 * keeps every result already recorded. The window this cannot close is the one
 * between SAP applying a response and this update committing — and that is
 * precisely why the row keeps its `responseId`: the next run replays the same
 * identity and RAP answers ALREADY_APPLIED, which is runtime-proven.
 *
 * `responseId`, `version`, `decision`, `estimatedDeliveryDate`, `reason` and
 * `respondedAt` are absent from this statement on purpose. They are the
 * supplier's committed answer and transport has no business editing them.
 */
/**
 * Persists the transport outcome for one row, and only the transport outcome.
 *
 * Each row commits in its own transaction, so a crash part-way through a flush
 * keeps every result already recorded. The window this cannot close is the one
 * between SAP applying a response and this update committing — and that is
 * precisely why the row keeps its `responseId`: the next run replays the same
 * identity and RAP answers ALREADY_APPLIED, which is runtime-proven.
 *
 * `responseId`, `version`, `decision`, `estimatedDeliveryDate`, `reason` and
 * `respondedAt` are absent from this statement on purpose. They are the
 * supplier's committed answer and transport has no business editing them.
 *
 * THE UPDATE IS GUARDED ON THE STATE WE READ. `expectedState` is part of the
 * WHERE clause, so this is a compare-and-set: a writer that moved the row AWAY
 * from `expectedState` — a concurrent flush that delivered it, or an operator
 * reconciling by hand — makes this statement match nothing, return 0 and write
 * nothing.
 *
 * Phase 7.5 closes the same-state race for automatic work: a flush first owns
 * an `IN_FLIGHT` lease and this predicate also requires its `leaseOwner`.
 * Explicit UNKNOWN reconciliation remains guarded by UNKNOWN state and is
 * operator-controlled rather than part of the automatic drain.
 *
 * PHASE 7.3: the attempt-history row is inserted INSIDE this transaction and
 * only after the guarded update matched. A loser returns before the INSERT is
 * reached, so it writes nothing; and because both statements share one
 * `cds.tx`, the parent can never commit without its history row. If the INSERT
 * fails the whole transaction rolls back, taking the parent update with it —
 * that is deliberate, and a unique-constraint violation is never suppressed.
 *
 * Returns true when the row was ours to write.
 */
async function record(
  row: ResponseRow,
  state: DeliveryState,
  error: string | null,
  correlationId: string | null,
  expectedState: DeliveryState,
  leaseOwner: string | undefined,
  facts: AttemptFacts
): Promise<boolean> {
  return await cds.tx(async () => {
    // One expression, used twice: the parent's counter and the child's ordinal
    // are the same number by construction and cannot drift.
    const attemptNumber = (row.attempts ?? 0) + 1
    const retryTiming = state === 'PENDING'
      ? calculateRetryTiming({
          attempts: attemptNumber,
          completedAt: new Date(facts.completedAt),
          retryWindowStartedAt: row.retryWindowStartedAt,
          jitter: facts.jitter,
          retryAfterDue: facts.retryAfterDue
        })
      : { nextAttemptAt: null, retryWindowStartedAt: null }

    const affected = await UPDATE(SupplierResponseDeliveries)
      .set({
        state,
        attempts: attemptNumber,
        lastAttemptAt: facts.completedAt,
        nextAttemptAt: retryTiming.nextAttemptAt,
        retryWindowStartedAt: retryTiming.retryWindowStartedAt,
        lastError: error,
        lastCorrelationId: correlationId,
        leaseOwner: null,
        leaseExpiresAt: null
      } as any)
      .where({
        ID: row.ID,
        state: expectedState,
        ...(leaseOwner ? { leaseOwner } : {})
      })

    // The loser stops here. Nothing below runs, so no history is written for an
    // outcome the durable state machine discarded.
    if (Number(affected) !== 1) return false

    await INSERT.into(SupplierResponseDeliveryAttempts).entries({
      delivery_ID: row.ID,
      attemptNumber,
      correlationId: facts.correlationId,
      startedAt: facts.startedAt,
      durationMs: facts.durationMs,
      outcome: state,
      httpStatus: facts.httpStatus,
      errorCategory: facts.errorCategory,
      errorSummary: error
    } as any)

    return true
  })
}
