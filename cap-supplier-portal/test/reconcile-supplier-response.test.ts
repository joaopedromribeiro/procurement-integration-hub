import cds from '@sap/cds'
import assert from 'node:assert/strict'
import { randomUUID } from 'node:crypto'
import type { Server } from 'node:http'
import path from 'node:path'
import { after, before, beforeEach, describe, test } from 'node:test'
import { Orders, SupplierResponseDeliveries, SupplierResponseDeliveryAttempts } from '#cds-models/pih/portal'

import type { ResponseTransport } from '../srv/lib/ci-transport'
import { flushSupplierResponses, reconcileSupplierResponse } from '../srv/lib/response-sender'
import type { SupplierResponsePayload, TransportResult } from '../srv/lib/supplier-response'

/**
 * Phase 6.5g — operator reconciliation of an UNKNOWN delivery.
 *
 * Every fixture here is produced the way production produces one: a real
 * supplier decision over HTTP, then a real sender attempt whose transport
 * answered ambiguously. Nothing hand-inserts an UNKNOWN row, because the point
 * of these tests is that the reconciliation path agrees with the sender path —
 * and a fabricated row could agree with neither.
 */
const portal = cds.test(path.resolve(__dirname, '..'))

const SUPPLIER = '/rest/supplier/v1'
const ORDER_A = '22222222-2222-4222-8222-000000000001'
const ORDER_B = '22222222-2222-4222-8222-000000000002'
const asSupplier1 = { auth: { username: 'supplier1', password: 'supplier1' } }

let server: Server | undefined

before(async () => {
  await new Promise<void>(resolve => { portal.then(started => { server = started.server; resolve() }) })
})
beforeEach(() => portal.data.reset())
after(() => { server?.close() })

// ------------------------------------------------------------------ doubles

class FakeTransport implements ResponseTransport {
  readonly sent: { payload: SupplierResponsePayload; correlationId: string }[] = []
  constructor(private readonly answer: TransportResult) {}
  async send(payload: SupplierResponsePayload, correlationId: string) {
    this.sent.push({ payload, correlationId })
    return this.answer
  }
}

const ok204: TransportResult = { answered: true, status: 204 }
const timeout: TransportResult = { answered: false, detail: 'no answer within 30000 ms' }

const rowFor = (order: string) =>
  SELECT.one.from(SupplierResponseDeliveries).where({ order_ID: order })
const orderRow = (order: string) => SELECT.one.from(Orders).where({ ID: order })

async function accept(order: string, extra: any = {}) {
  await portal.POST(`${SUPPLIER}/Orders/${order}/accept`, {
    responseId: randomUUID(), expectedResponseVersion: 0, ...extra
  }, asSupplier1)
}

/** A genuinely UNKNOWN row: a real decision, then a real ambiguous attempt. */
async function stuckUnknown(order = ORDER_A, extra: any = {}) {
  await accept(order, extra)
  await flushSupplierResponses({ transport: new FakeTransport(timeout) })
  const row: any = await rowFor(order)
  assert.equal(row.state, 'UNKNOWN', 'fixture precondition')
  return row
}

/** Drives a row to a terminal state through the normal sender. */
async function stuckAt(state: string, answer: TransportResult, order = ORDER_A) {
  await accept(order)
  await flushSupplierResponses({ transport: new FakeTransport(answer) })
  const row: any = await rowFor(order)
  assert.equal(row.state, state, 'fixture precondition')
  return row
}

// ------------------------------------------------------------------- tests

describe('reconciliation refuses everything it should', () => {

  test('a missing responseId is refused before anything is sent', async () => {
    const transport = new FakeTransport(ok204)

    for (const responseId of ['', '   ', undefined as any]) {
      const result = await reconcileSupplierResponse({ responseId, transport })
      assert.equal(result.refused, 'MISSING_RESPONSE_ID')
    }
    assert.equal(transport.sent.length, 0, 'nothing reached the transport')
  })

  test('an unknown responseId is refused', async () => {
    const transport = new FakeTransport(ok204)
    const result = await reconcileSupplierResponse({ responseId: randomUUID(), transport })

    assert.equal(result.refused, 'NOT_FOUND')
    assert.equal(transport.sent.length, 0)
  })

  test('a DELIVERED row is refused and not resent', async () => {
    const row = await stuckAt('DELIVERED', ok204)

    const transport = new FakeTransport(ok204)
    const result = await reconcileSupplierResponse({ responseId: row.responseId, transport })

    assert.equal(result.refused, 'NOT_UNKNOWN')
    assert.match(result.message!, /DELIVERED/)
    assert.equal(transport.sent.length, 0, 'a delivered response is never duplicated')

    const after: any = await rowFor(ORDER_A)
    assert.equal(after.attempts, 1, 'the refusal did not count as an attempt')
  })

  test('a FAILED row is refused, because a replay would be refused identically', async () => {
    const row = await stuckAt('FAILED', { answered: true, status: 409, detail: 'conflict' })

    const transport = new FakeTransport(ok204)
    const result = await reconcileSupplierResponse({ responseId: row.responseId, transport })

    assert.equal(result.refused, 'NOT_UNKNOWN')
    assert.match(result.message!, /FAILED/)
    assert.equal(transport.sent.length, 0)
  })

  test('a PENDING row is refused, because the normal flush owns it', async () => {
    const row = await stuckAt('PENDING', { answered: true, status: 503 })

    const transport = new FakeTransport(ok204)
    const result = await reconcileSupplierResponse({ responseId: row.responseId, transport })

    assert.equal(result.refused, 'NOT_UNKNOWN')
    assert.match(result.message!, /PENDING/)
    assert.equal(transport.sent.length, 0)
  })
})

describe('reconciliation classifies exactly like the sender', () => {

  const cases: { label: string; answer: TransportResult; expected: string }[] = [
    { label: '204 resolves it', answer: ok204, expected: 'DELIVERED' },
    { label: '200 resolves it too', answer: { answered: true, status: 200 }, expected: 'DELIVERED' },
    { label: '400 is deterministic', answer: { answered: true, status: 400, detail: 'bad' }, expected: 'FAILED' },
    { label: '429 returns it to the queue', answer: { answered: true, status: 429 }, expected: 'PENDING' },
    { label: '500 stays ambiguous', answer: { answered: true, status: 500 }, expected: 'UNKNOWN' },
    { label: 'no answer stays ambiguous', answer: timeout, expected: 'UNKNOWN' }
  ]

  for (const { label, answer, expected } of cases) {
    test(`${label} — UNKNOWN becomes ${expected}`, async () => {
      const row = await stuckUnknown()

      const transport = new FakeTransport(answer)
      const result = await reconcileSupplierResponse({ responseId: row.responseId, transport })

      assert.equal(result.refused, undefined, 'the reconciliation ran')
      assert.equal(result.outcome!.state, expected)
      assert.equal(transport.sent.length, 1, 'exactly one attempt, never a loop')

      const after: any = await rowFor(ORDER_A)
      assert.equal(after.state, expected)
    })
  }

  test('the replayed payload is byte-identical to the original attempt', async () => {
    await accept(ORDER_A, { estimatedDeliveryDate: '2026-11-15' })
    const first = new FakeTransport(timeout)
    await flushSupplierResponses({ transport: first })

    const row: any = await rowFor(ORDER_A)
    const replay = new FakeTransport(ok204)
    await reconcileSupplierResponse({ responseId: row.responseId, transport: replay })

    assert.deepEqual(replay.sent[0].payload, first.sent[0].payload)
    assert.equal(replay.sent[0].payload.responseId, row.responseId, 'never a new responseId')
  })
})

describe('reconciliation bookkeeping matches a normal attempt', () => {

  test('attempts increments exactly once and the correlation ID is fresh', async () => {
    const before = await stuckUnknown()
    assert.equal(before.attempts, 1)

    const transport = new FakeTransport(ok204)
    await reconcileSupplierResponse({ responseId: before.responseId, transport })

    const after: any = await rowFor(ORDER_A)
    assert.equal(after.attempts, 2, 'exactly one more attempt')
    assert.equal(after.lastCorrelationId, transport.sent[0].correlationId, 'the fresh attempt id')
    assert.notEqual(after.lastCorrelationId, before.lastCorrelationId, 'not the previous one')
    assert.notEqual(after.lastCorrelationId, after.responseId, 'transport metadata, not identity')
    assert.ok(after.lastAttemptAt, 'the attempt is timestamped')
    assert.equal(after.lastError, null, 'a success clears the error')
  })

  test('lastError reflects the latest transport result', async () => {
    const row = await stuckUnknown()

    await reconcileSupplierResponse({
      responseId: row.responseId,
      transport: new FakeTransport({ answered: true, status: 400, detail: 'payload rejected' })
    })

    const after: any = await rowFor(ORDER_A)
    assert.match(after.lastError, /^HTTP 400/)
  })

  test('the committed supplier response is untouched in every field', async () => {
    const before = await stuckUnknown(ORDER_A, { estimatedDeliveryDate: '2026-11-15' })

    await reconcileSupplierResponse({
      responseId: before.responseId, transport: new FakeTransport(ok204)
    })

    const after: any = await rowFor(ORDER_A)
    for (const field of ['responseId', 'version', 'decision', 'estimatedDeliveryDate', 'reason', 'respondedAt']) {
      assert.deepEqual(after[field], before[field], `${field} is immutable`)
    }
  })

  test('Orders is never modified by a reconciliation', async () => {
    const row = await stuckUnknown(ORDER_A, { estimatedDeliveryDate: '2026-11-15' })
    const before: any = await orderRow(ORDER_A)

    for (const answer of [ok204, { answered: true, status: 400 } as TransportResult, timeout]) {
      await UPDATE(SupplierResponseDeliveries).set({ state: 'UNKNOWN' } as any).where({ order_ID: ORDER_A })
      await reconcileSupplierResponse({ responseId: row.responseId, transport: new FakeTransport(answer) })
      assert.deepEqual(await orderRow(ORDER_A), before, 'the order never moves')
    }

    const final: any = await orderRow(ORDER_A)
    assert.equal(final.status, 'ACCEPTED')
    assert.equal(final.responseVersion, 1)
  })

  test('reconciling one row leaves other rows alone', async () => {
    const a = await stuckUnknown(ORDER_A)
    await accept(ORDER_B)

    await reconcileSupplierResponse({ responseId: a.responseId, transport: new FakeTransport(ok204) })

    const other: any = await rowFor(ORDER_B)
    assert.equal(other.state, 'PENDING', 'untouched')
    assert.equal(other.attempts, 0)
  })
})

describe('the guarded write stops a lost update', () => {

  test('a row that leaves UNKNOWN mid-attempt is not overwritten', async () => {
    const row = await stuckUnknown()

    // A transport that moves the row while the request is "in flight" — exactly
    // what a concurrent flush or a second operator would do.
    const racing: ResponseTransport = {
      async send() {
        await UPDATE(SupplierResponseDeliveries)
          .set({ state: 'DELIVERED', lastError: null } as any)
          .where({ ID: row.ID })
        return { answered: false, certainty: 'NOT_SENT', detail: 'request not sent' }
      }
    }

    const result = await reconcileSupplierResponse({ responseId: row.responseId, transport: racing })

    assert.equal(result.refused, 'STATE_CHANGED')
    assert.equal(result.outcome!.conflicted, true)

    const after: any = await rowFor(ORDER_A)
    assert.equal(after.state, 'DELIVERED', 'the concurrent write stands')
    assert.equal(after.attempts, 1, 'the losing attempt did not inflate the count')
    assert.equal(after.responseId, row.responseId, 'identity intact, so a later replay is still safe')
  })
})

describe('attempt history across reconciliation', () => {

  const historyFor = (delivery: string) =>
    SELECT.from(SupplierResponseDeliveryAttempts).where({ delivery_ID: delivery }).orderBy('attemptNumber')

  test('two attempts on one response produce exactly two rows, numbered 1 and 2', async () => {
    // Attempt 1: the real sender, answered ambiguously.
    const row = await stuckUnknown()
    const first: any[] = await historyFor(row.ID)
    assert.equal(first.length, 1, 'the ambiguous attempt recorded itself')
    const correlationA = first[0].correlationId
    assert.equal(first[0].outcome, 'UNKNOWN')
    assert.equal(first[0].errorCategory, 'NO_ANSWER')

    // Attempt 2: the SAME responseId through the operator command.
    const transport = new FakeTransport(ok204)
    const result = await reconcileSupplierResponse({ responseId: row.responseId, transport })

    assert.equal(result.outcome!.state, 'DELIVERED')
    assert.equal(transport.sent.length, 1, 'exactly one replay')
    assert.equal(transport.sent[0].payload.responseId, row.responseId, 'the same business identity')

    const correlationB = transport.sent[0].correlationId
    assert.notEqual(correlationB, correlationA, 'a fresh correlation id for the new attempt')

    const parent: any = await rowFor(ORDER_A)
    assert.equal(parent.state, 'DELIVERED')
    assert.equal(parent.attempts, 2)
    assert.equal(parent.lastCorrelationId, correlationB)

    const history: any[] = await historyFor(row.ID)
    assert.equal(history.length, 2, 'exactly two rows, no duplicates')
    assert.deepEqual(history.map(h => h.attemptNumber), [1, 2], 'contiguous and ordered')
    assert.deepEqual(history.map(h => h.correlationId), [correlationA, correlationB])
    assert.deepEqual(history.map(h => h.outcome), ['UNKNOWN', 'DELIVERED'])
    assert.deepEqual(history.map(h => h.httpStatus), [null, 204])
    assert.deepEqual(history.map(h => h.errorCategory), ['NO_ANSWER', 'NONE'])
    assert.equal(history[1].errorSummary, null, 'the successful replay stores no diagnosis')
  })

  test('a refused reconciliation records no attempt at all', async () => {
    const row = await stuckAt('DELIVERED', ok204)
    const before: any[] = await historyFor(row.ID)
    assert.equal(before.length, 1, 'only the attempt that actually happened')

    const transport = new FakeTransport(ok204)
    const result = await reconcileSupplierResponse({ responseId: row.responseId, transport })

    assert.equal(result.refused, 'NOT_UNKNOWN')
    assert.equal(transport.sent.length, 0)

    const after: any[] = await historyFor(row.ID)
    assert.equal(after.length, 1, 'a refusal is not an attempt and writes no history')
    assert.equal((await rowFor(ORDER_A) as any).attempts, 1)
  })

  test('a true compare-and-set loser writes no history row', async () => {
    const row = await stuckUnknown()
    const beforeCount = (await historyFor(row.ID)).length
    assert.equal(beforeCount, 1, 'the ambiguous attempt is the only history so far')

    await UPDATE(SupplierResponseDeliveries).set({
      attempts: 3,
      lastAttemptAt: '2026-09-21T10:00:00.000Z',
      lastError: 'recognizable pre-race error',
      lastCorrelationId: '11111111-2222-4333-8444-555555555555',
      nextAttemptAt: '2026-09-21T10:05:00.000Z',
      retryWindowStartedAt: '2026-09-21T09:55:00.000Z'
    } as any).where({ ID: row.ID })
    const before: any = await rowFor(ORDER_A)
    const protectedFields = [
      'attempts', 'lastAttemptAt', 'lastError', 'lastCorrelationId',
      'nextAttemptAt', 'retryWindowStartedAt'
    ]
    for (const field of protectedFields) assert.notEqual(before[field], null, `${field} is seeded`)

    // The row leaves UNKNOWN while this attempt is in flight, so the guarded
    // write matches nothing: affected rows = 0. A TRUE loser, not a same-state
    // self-transition — the state genuinely changes to DELIVERED underneath.
    const racing: ResponseTransport = {
      async send() {
        await UPDATE(SupplierResponseDeliveries)
          .set({ state: 'DELIVERED' } as any)
          .where({ ID: row.ID })
        return {
          answered: false,
          certainty: 'NOT_SENT',
          detail: 'request not sent',
          retryAfter: '120'
        }
      }
    }

    const result = await reconcileSupplierResponse({ responseId: row.responseId, transport: racing })

    assert.equal(result.refused, 'STATE_CHANGED')
    assert.equal(result.outcome!.conflicted, true)

    const after: any = await rowFor(ORDER_A)
    assert.equal(after.state, 'DELIVERED', 'the concurrent write stands')
    for (const field of protectedFields) {
      assert.deepEqual(after[field], before[field], `${field} survives the losing attempt unchanged`)
    }

    // The concurrent mutation above bypassed the sender, so it legitimately has
    // no history of its own. What matters is that the LOSER added none: the
    // count is unchanged from before the losing attempt ran.
    const history: any[] = await historyFor(row.ID)
    assert.equal(history.length, beforeCount, 'the loser wrote zero history rows')
    assert.deepEqual(history.map(h => h.attemptNumber), [1], 'no attemptNumber 2 was invented')
  })
})
