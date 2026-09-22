import assert from 'node:assert/strict'
import { describe, test } from 'node:test'
import {
  calculateRetryTiming,
  MAX_RETRY_WINDOW_MS,
  retryEligibility
} from '../srv/lib/retry-policy'

const T0 = new Date('2026-09-21T12:00:00.000Z')
const isoAfter = (milliseconds: number) => new Date(T0.getTime() + milliseconds).toISOString()

describe('retry eligibility', () => {
  test('a fresh PENDING row is immediately eligible', () => {
    assert.equal(retryEligibility({ state: 'PENDING', attempts: 0, nextAttemptAt: null }, T0), 'ELIGIBLE')
  })

  test('a future due time waits, while exactly-now and earlier are eligible', () => {
    assert.equal(retryEligibility({ state: 'PENDING', attempts: 1, nextAttemptAt: isoAfter(1) }, T0), 'BEFORE_DUE')
    assert.equal(retryEligibility({ state: 'PENDING', attempts: 1, nextAttemptAt: T0 }, T0), 'ELIGIBLE')
    assert.equal(retryEligibility({ state: 'PENDING', attempts: 1, nextAttemptAt: isoAfter(-1) }, T0), 'ELIGIBLE')
  })

  test('legacy retryable rows with no due time remain immediately eligible', () => {
    for (const attempts of [1, 2, 3]) {
      assert.equal(retryEligibility({ state: 'PENDING', attempts, nextAttemptAt: null }, T0), 'ELIGIBLE')
    }
  })

  test('four attempts is exhausted regardless of a due timestamp', () => {
    assert.equal(retryEligibility({ state: 'PENDING', attempts: 4, nextAttemptAt: null }, T0), 'RETRY_EXHAUSTED')
    assert.equal(retryEligibility({ state: 'PENDING', attempts: 8, nextAttemptAt: isoAfter(-1) }, T0), 'RETRY_EXHAUSTED')
  })

  test('UNKNOWN, FAILED and DELIVERED are never eligible', () => {
    for (const state of ['UNKNOWN', 'FAILED', 'DELIVERED']) {
      assert.equal(retryEligibility({ state, attempts: 0, nextAttemptAt: null }, T0), 'NOT_PENDING')
    }
  })

  test('a due time outside the window and an expired window are both blocked', () => {
    const row = { state: 'PENDING', attempts: 1, retryWindowStartedAt: T0 }
    assert.equal(
      retryEligibility({ ...row, nextAttemptAt: isoAfter(MAX_RETRY_WINDOW_MS + 1) }, T0),
      'RETRY_WINDOW_BLOCKED'
    )
    assert.equal(
      retryEligibility({ ...row, nextAttemptAt: isoAfter(5_000) }, new Date(T0.getTime() + MAX_RETRY_WINDOW_MS + 1)),
      'RETRY_WINDOW_BLOCKED'
    )
    assert.equal(
      retryEligibility({ ...row, nextAttemptAt: isoAfter(MAX_RETRY_WINDOW_MS) }, new Date(T0.getTime() + MAX_RETRY_WINDOW_MS)),
      'ELIGIBLE',
      'the exact 15-minute boundary is inclusive'
    )
  })
})

describe('durable retry timing', () => {
  test('attempt one uses the 5-second base at the jitter lower boundary', () => {
    const timing = calculateRetryTiming({ attempts: 1, completedAt: T0, jitter: () => 0 })
    assert.equal(timing.retryWindowStartedAt, T0.toISOString())
    assert.equal(timing.nextAttemptAt, isoAfter(5_000))
    assert.equal(timing.retryWindowBlocked, false)
  })

  test('attempts one through three use the inclusive 20% upper boundary', () => {
    const cases = [
      { attempts: 1, maximum: 1_000, due: 6_000 },
      { attempts: 2, maximum: 6_000, due: 36_000 },
      { attempts: 3, maximum: 24_000, due: 144_000 }
    ]

    for (const expected of cases) {
      const timing = calculateRetryTiming({
        attempts: expected.attempts,
        completedAt: T0,
        jitter: maximum => {
          assert.equal(maximum, expected.maximum)
          return maximum
        }
      })
      assert.equal(timing.nextAttemptAt, isoAfter(expected.due))
    }
  })

  test('jitter can never be negative or exceed the frozen maximum', () => {
    assert.throws(() => calculateRetryTiming({ attempts: 1, completedAt: T0, jitter: () => -1 }), /Jitter/)
    assert.throws(() => calculateRetryTiming({ attempts: 1, completedAt: T0, jitter: () => 1_001 }), /Jitter/)
    assert.throws(() => calculateRetryTiming({ attempts: 1, completedAt: T0, jitter: () => 0.5 }), /Jitter/)
  })

  test('the original retry-window timestamp is preserved', () => {
    const original = isoAfter(-60_000)
    const timing = calculateRetryTiming({
      attempts: 2, completedAt: T0, retryWindowStartedAt: original, jitter: () => 0
    })
    assert.equal(timing.retryWindowStartedAt, original)
    assert.equal(timing.nextAttemptAt, isoAfter(30_000))
  })

  test('attempt four is exhausted and has no deferred due time', () => {
    const timing = calculateRetryTiming({ attempts: 4, completedAt: T0, jitter: () => { throw new Error('unused') } })
    assert.equal(timing.retryWindowStartedAt, T0.toISOString())
    assert.equal(timing.nextAttemptAt, null)
  })

  test('a candidate beyond 15 minutes is retained as blocked diagnostic evidence', () => {
    const oldWindow = new Date(T0.getTime() - MAX_RETRY_WINDOW_MS + 4_999).toISOString()
    const timing = calculateRetryTiming({
      attempts: 1, completedAt: T0, retryWindowStartedAt: oldWindow, jitter: () => 0
    })
    assert.equal(timing.nextAttemptAt, isoAfter(5_000))
    assert.equal(timing.retryWindowBlocked, true)
    assert.equal(retryEligibility({
      state: 'PENDING', attempts: 1,
      retryWindowStartedAt: timing.retryWindowStartedAt,
      nextAttemptAt: timing.nextAttemptAt
    }, T0), 'RETRY_WINDOW_BLOCKED')
  })

  test('a candidate exactly at the 15-minute window end is accepted', () => {
    const retryWindowStartedAt = new Date(T0.getTime() - MAX_RETRY_WINDOW_MS + 5_000)
    const windowEnd = new Date(retryWindowStartedAt.getTime() + MAX_RETRY_WINDOW_MS)
    const timing = calculateRetryTiming({
      attempts: 1, completedAt: T0, retryWindowStartedAt, jitter: () => 0
    })

    assert.equal(timing.nextAttemptAt, windowEnd.toISOString())
    assert.equal(timing.retryWindowBlocked, false)
  })

  test('a future Retry-After input can only postpone the normal due time', () => {
    const earlier = calculateRetryTiming({
      attempts: 1, completedAt: T0, jitter: () => 1_000, retryAfterDue: isoAfter(1_000)
    })
    assert.equal(earlier.nextAttemptAt, isoAfter(6_000))

    const later = calculateRetryTiming({
      attempts: 1, completedAt: T0, jitter: () => 0, retryAfterDue: isoAfter(8_000)
    })
    assert.equal(later.nextAttemptAt, isoAfter(8_000))
  })

  test('the injected selector makes the calculation deterministic', () => {
    const options = { attempts: 3, completedAt: T0, jitter: () => 12_345 }
    assert.deepEqual(calculateRetryTiming(options), calculateRetryTiming(options))
  })
})
