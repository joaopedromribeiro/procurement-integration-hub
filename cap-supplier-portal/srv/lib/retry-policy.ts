/** Phase 7.4a — durable retry eligibility for transient PENDING responses. */

export const MAX_ATTEMPTS = 4
export const MAX_RETRY_WINDOW_MS = 15 * 60 * 1000
export const RETRY_BASE_DELAYS_MS = [5_000, 30_000, 120_000] as const
export const JITTER_PERCENT = 20

export type JitterSelector = (maximumMs: number) => number

/** Uniform whole-millisecond jitter in the inclusive range 0..20% of base. */
export const uniformPositiveJitter: JitterSelector = maximumMs =>
  Math.floor(Math.random() * (maximumMs + 1))

export interface RetryTiming {
  retryWindowStartedAt: string
  nextAttemptAt: string | null
  retryWindowBlocked: boolean
}

export interface RetryTimingOptions {
  attempts: number
  completedAt: Date
  retryWindowStartedAt?: string | Date | null
  jitter?: JitterSelector
  /** Phase 7.4b can supply a parsed Retry-After due time here. */
  retryAfterDue?: string | Date | null
}

function asDate(value: string | Date): Date {
  const date = value instanceof Date ? value : new Date(value)
  if (Number.isNaN(date.getTime())) throw new Error(`Invalid retry-policy timestamp: ${String(value)}`)
  return date
}

function timestamp(value: string | Date | null | undefined): number | null {
  return value == null ? null : asDate(value).getTime()
}

/**
 * Chooses and freezes the next due time after a transient outcome.
 *
 * The caller persists both returned timestamps in the same transaction as the
 * attempt counter and history row. A due time beyond the window is retained as
 * diagnostic evidence but is never eligible.
 */
export function calculateRetryTiming(options: RetryTimingOptions): RetryTiming {
  const completedMs = options.completedAt.getTime()
  if (Number.isNaN(completedMs)) throw new Error('completedAt must be a valid Date.')

  const windowStartMs = timestamp(options.retryWindowStartedAt) ?? completedMs
  const retryWindowStartedAt = new Date(windowStartMs).toISOString()

  if (options.attempts >= MAX_ATTEMPTS) {
    return { retryWindowStartedAt, nextAttemptAt: null, retryWindowBlocked: false }
  }

  const baseDelay = RETRY_BASE_DELAYS_MS[options.attempts - 1]
  if (baseDelay === undefined) {
    throw new Error(`No retry delay exists after attempt ${options.attempts}.`)
  }

  const maximumJitter = Math.floor(baseDelay * JITTER_PERCENT / 100)
  const jitter = (options.jitter ?? uniformPositiveJitter)(maximumJitter)
  if (!Number.isInteger(jitter) || jitter < 0 || jitter > maximumJitter) {
    throw new Error(`Jitter must be a whole number from 0 through ${maximumJitter} ms.`)
  }

  const normalDueMs = completedMs + baseDelay + jitter
  const retryAfterMs = timestamp(options.retryAfterDue)
  const selectedDueMs = retryAfterMs == null ? normalDueMs : Math.max(normalDueMs, retryAfterMs)
  const boundaryMs = windowStartMs + MAX_RETRY_WINDOW_MS

  return {
    retryWindowStartedAt,
    nextAttemptAt: new Date(selectedDueMs).toISOString(),
    retryWindowBlocked: selectedDueMs > boundaryMs
  }
}

export type EligibilityReason =
  | 'ELIGIBLE'
  | 'BEFORE_DUE'
  | 'RETRY_EXHAUSTED'
  | 'RETRY_WINDOW_BLOCKED'
  | 'NOT_PENDING'

export interface RetryEligibilityRow {
  state?: string | null
  attempts?: number | null
  nextAttemptAt?: string | Date | null
  retryWindowStartedAt?: string | Date | null
}

/** Pure invocation-time eligibility. Attempt history is deliberately irrelevant. */
export function retryEligibility(row: RetryEligibilityRow, now: Date): EligibilityReason {
  if (row.state !== 'PENDING') return 'NOT_PENDING'

  const attempts = row.attempts ?? 0
  if (attempts >= MAX_ATTEMPTS) return 'RETRY_EXHAUSTED'

  const nowMs = now.getTime()
  if (Number.isNaN(nowMs)) throw new Error('now must be a valid Date.')

  const windowStartMs = timestamp(row.retryWindowStartedAt)
  const nextAttemptMs = timestamp(row.nextAttemptAt)
  if (windowStartMs != null) {
    const boundaryMs = windowStartMs + MAX_RETRY_WINDOW_MS
    if (nowMs > boundaryMs || (nextAttemptMs != null && nextAttemptMs > boundaryMs)) {
      return 'RETRY_WINDOW_BLOCKED'
    }
  }

  if (nextAttemptMs == null || nextAttemptMs <= nowMs) return 'ELIGIBLE'
  return 'BEFORE_DUE'
}
