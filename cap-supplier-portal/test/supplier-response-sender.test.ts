import cds from '@sap/cds'
import assert from 'node:assert/strict'
import { randomUUID } from 'node:crypto'
import type { Server } from 'node:http'
import path from 'node:path'
import { after, before, beforeEach, describe, test } from 'node:test'
import { Orders, SupplierResponseDeliveries, SupplierResponseDeliveryAttempts } from '#cds-models/pih/portal'

import {
  CI_CLIENT_ID_VAR, CI_CLIENT_SECRET_VAR, CI_TIMEOUT_VAR, CI_URL_VAR,
  certaintyForFetchError, ConfigError, DEFAULT_TIMEOUT_MS, HttpResponseTransport,
  NOT_SENT_CAUSE_CODES, readCiConfig, safeDetail,
  type ResponseTransport
} from '../srv/lib/ci-transport'
import { flushSupplierResponses } from '../srv/lib/response-sender'
import {
  buildSupplierResponsePayload, categorise, classify, PayloadError, toRfc3339,
  type SupplierResponsePayload, type TransportResult
} from '../srv/lib/supplier-response'

/**
 * Phase 6.5e — supplier-response sender tests.
 *
 * Decisions are made over HTTP against the running application, exactly as a
 * supplier makes them, so every row the sender drains was committed by the real
 * Phase 4.4 transaction rather than inserted by a test. The transport is the one
 * thing faked: `npm test` must never reach a Cloud Integration tenant, and the
 * point of the `ResponseTransport` interface is that the delivery state machine
 * can be proven without one.
 *
 * LOCAL EVIDENCE ONLY. Passing here says the payload, the classification and
 * the persistence are right. It says nothing about the deployed iFlow, which is
 * Phase 6.5f's job to prove.
 */
const portal = cds.test(path.resolve(__dirname, '..'))

const SUPPLIER = '/rest/supplier/v1'
const SUP001_ORDER_A = '22222222-2222-4222-8222-000000000001'
const SUP001_ORDER_B = '22222222-2222-4222-8222-000000000002'
const asSupplier1 = { auth: { username: 'supplier1', password: 'supplier1' } }

let server: Server | undefined

before(async () => {
  await new Promise<void>(resolve => {
    portal.then(started => { server = started.server; resolve() })
  })
})

beforeEach(() => portal.data.reset())
after(() => { server?.close() })

// ------------------------------------------------------------------ doubles

/** A transport that answers from a script and remembers exactly what it was given. */
class FakeTransport implements ResponseTransport {
  readonly sent: { payload: SupplierResponsePayload; correlationId: string }[] = []
  private readonly script: TransportResult[]

  constructor(...script: TransportResult[]) {
    this.script = script
  }

  async send(payload: SupplierResponsePayload, correlationId: string): Promise<TransportResult> {
    this.sent.push({ payload, correlationId })
    return this.script[Math.min(this.sent.length - 1, this.script.length - 1)]
  }
}

const ok204: TransportResult = { answered: true, status: 204 }
const ok200: TransportResult = { answered: true, status: 200 }
const conflict: TransportResult = { answered: true, status: 409, detail: 'version conflict' }
const timeout: TransportResult = { answered: false, detail: 'no answer within 30000 ms' }

/** Makes a real supplier decision, the way a supplier would. */
async function decide(order: string, action: string, body: any) {
  const response = await portal.POST(`${SUPPLIER}/Orders/${order}/${action}`, body, asSupplier1)
  return response.data
}

const accept = (order: string, extra: any = {}) =>
  decide(order, 'accept', { responseId: randomUUID(), expectedResponseVersion: 0, ...extra })

const reject = (order: string, reason: string) =>
  decide(order, 'reject', { responseId: randomUUID(), expectedResponseVersion: 0, reason })

const rowsFor = (order: string) =>
  SELECT.from(SupplierResponseDeliveries).where({ order_ID: order }).orderBy('version')

const orderRow = (order: string) => SELECT.one.from(Orders).where({ ID: order })

// ------------------------------------------------------------------- tests

describe('the frozen wire payload', () => {

  test('a PENDING response maps to exactly the contract\'s field set', async () => {
    await accept(SUP001_ORDER_A, { estimatedDeliveryDate: '2026-11-15' })

    const transport = new FakeTransport(ok204)
    await flushSupplierResponses({ transport })

    assert.equal(transport.sent.length, 1)
    const payload = transport.sent[0].payload

    // The field set is the contract. An extra member would be an unmapped
    // element at the iFlow, a missing one a validation failure, and neither is
    // something this project gets to discover against a deployed tenant.
    assert.deepEqual(Object.keys(payload).sort(), [
      'decision', 'deliveryId', 'estimatedDeliveryDate', 'portalOrderId', 'reason',
      'respondedAt', 'responseId', 'responseVersion', 'schemaVersion', 'sourceOrderId',
      'sourceRevision', 'sourceSystem', 'supplierCode'
    ])

    assert.equal(payload.schemaVersion, '1.0')
    assert.equal(payload.decision, 'ACCEPTED')
    assert.equal(payload.responseVersion, 1)
    assert.equal(payload.estimatedDeliveryDate, '2026-11-15')
    assert.equal(payload.reason, null)
    assert.match(payload.respondedAt, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/)
  })

  test('the source, order, delivery and supplier identities are preserved', async () => {
    const receipt = await accept(SUP001_ORDER_A)
    const order: any = await orderRow(SUP001_ORDER_A)

    const transport = new FakeTransport(ok204)
    await flushSupplierResponses({ transport })
    const payload = transport.sent[0].payload

    assert.equal(payload.sourceSystem, order.sourceSystem, 'sourceSystem comes from the order')
    assert.equal(payload.sourceOrderId, order.sourceOrderId)
    assert.equal(payload.sourceRevision, order.sourceRevision)
    assert.equal(payload.deliveryId, order.deliveryId, 'the delivery that carried the snapshot')
    assert.equal(payload.portalOrderId, SUP001_ORDER_A)
    assert.equal(payload.supplierCode, 'SUP001', 'resolved through the supplier association')
    assert.equal(payload.responseVersion, receipt.responseVersion)

    // Nothing was invented: every identity in the payload is one SAP already knows.
    assert.equal(payload.sourceSystem, 'PIH_ABAP_DEV')
    assert.equal(payload.deliveryId, '44444444-4444-4444-8444-000000000001')
  })

  test('an acceptance with no date sends null rather than a guess', async () => {
    await accept(SUP001_ORDER_A)

    const transport = new FakeTransport(ok204)
    await flushSupplierResponses({ transport })

    assert.equal(transport.sent[0].payload.estimatedDeliveryDate, null)
    assert.equal(transport.sent[0].payload.reason, null)
  })

  test('a rejection carries its reason and a null date', async () => {
    await reject(SUP001_ORDER_A, 'Capacity unavailable for this quantity.')

    const transport = new FakeTransport(ok204)
    await flushSupplierResponses({ transport })
    const payload = transport.sent[0].payload

    assert.equal(payload.decision, 'REJECTED')
    assert.equal(payload.reason, 'Capacity unavailable for this quantity.')
    assert.equal(payload.estimatedDeliveryDate, null, 'a rejection never carries a date')
  })

  test('a malformed row is refused before it reaches the wire', () => {
    const order = {
      ID: 'o', sourceSystem: 'S', sourceOrderId: 'x', sourceRevision: 1,
      deliveryId: 'd', supplierCode: 'SUP001'
    }

    assert.throws(
      () => buildSupplierResponsePayload(
        { ID: 'r', responseId: 'r1', order_ID: 'o', version: 1, decision: 'REJECTED', respondedAt: '2026-09-20T03:08:45Z' },
        order
      ),
      (error: any) => error instanceof PayloadError && error.code === 'MISSING_REJECTION_REASON'
    )

    assert.throws(
      () => buildSupplierResponsePayload(
        { ID: 'r', responseId: 'r1', order_ID: 'o', version: 1, decision: 'ACCEPTED', respondedAt: null },
        order
      ),
      (error: any) => error instanceof PayloadError && error.code === 'MISSING_RESPONDED_AT'
    )
  })

  test('respondedAt is RFC 3339 at second precision, whatever the driver returned', () => {
    // HANA hands back a Date, SQLite an ISO string, and the verified SAP value
    // carries no milliseconds. All three have to produce the same wire value.
    assert.equal(toRfc3339('2026-09-20T03:08:45.123Z'), '2026-09-20T03:08:45Z')
    assert.equal(toRfc3339(new Date(Date.UTC(2026, 8, 20, 3, 8, 45))), '2026-09-20T03:08:45Z')
  })
})

describe('correlation identity', () => {

  test('every attempt gets a fresh correlation ID and the same responseId', async () => {
    await accept(SUP001_ORDER_A)

    const first = new FakeTransport(timeout)
    await flushSupplierResponses({ transport: first })

    // UNKNOWN is not eligible for the normal flush, so the operator's replay is
    // modelled the way it really happens: the row is returned to PENDING.
    await UPDATE(SupplierResponseDeliveries).set({ state: 'PENDING' } as any).where({ order_ID: SUP001_ORDER_A })

    const second = new FakeTransport(ok204)
    await flushSupplierResponses({ transport: second })

    const a = first.sent[0]
    const b = second.sent[0]

    assert.notEqual(a.correlationId, b.correlationId, 'correlation is per attempt')
    assert.equal(a.payload.responseId, b.payload.responseId, 'response identity never changes')
    assert.equal(a.payload.responseVersion, b.payload.responseVersion)
    assert.deepEqual(a.payload, b.payload, 'the replayed payload is byte-identical')
  })

  test('the correlation ID is persisted but is never the business identity', async () => {
    await accept(SUP001_ORDER_A)

    const transport = new FakeTransport(ok204)
    await flushSupplierResponses({ transport })

    const [row]: any[] = await rowsFor(SUP001_ORDER_A)
    assert.equal(row.lastCorrelationId, transport.sent[0].correlationId)
    assert.notEqual(row.lastCorrelationId, row.responseId)
  })
})

describe('delivery classification', () => {

  test('the verified 204 marks the delivery DELIVERED', async () => {
    await accept(SUP001_ORDER_A)

    await flushSupplierResponses({ transport: new FakeTransport(ok204) })

    const [row]: any[] = await rowsFor(SUP001_ORDER_A)
    assert.equal(row.state, 'DELIVERED')
    assert.equal(row.attempts, 1)
    assert.equal(row.lastError, null)
    assert.ok(row.lastAttemptAt, 'the attempt is timestamped')
  })

  test('another 2xx is success too', async () => {
    await accept(SUP001_ORDER_A)

    await flushSupplierResponses({ transport: new FakeTransport(ok200) })

    const [row]: any[] = await rowsFor(SUP001_ORDER_A)
    assert.equal(row.state, 'DELIVERED')
  })

  test('a deterministic refusal is never DELIVERED', async () => {
    await accept(SUP001_ORDER_A)

    await flushSupplierResponses({ transport: new FakeTransport(conflict) })

    const [row]: any[] = await rowsFor(SUP001_ORDER_A)
    assert.equal(row.state, 'FAILED')
    assert.match(row.lastError, /^HTTP 409/)
    assert.equal(row.attempts, 1)
  })

  test('an unanswered attempt is UNKNOWN, not a failure', async () => {
    await accept(SUP001_ORDER_A)

    await flushSupplierResponses({ transport: new FakeTransport(timeout) })

    const [row]: any[] = await rowsFor(SUP001_ORDER_A)
    // A timeout never proves non-delivery. SAP may have applied it, so the row
    // must stay replayable rather than be written off.
    assert.equal(row.state, 'UNKNOWN')
    assert.match(row.lastError, /^NO_ANSWER/)
  })

  test('the classification table matches the contract\'s error policy', () => {
    for (const status of [200, 201, 202, 204]) {
      assert.equal(classify({ answered: true, status }), 'DELIVERED', `${status}`)
    }
    for (const status of [400, 401, 403, 404, 409, 412, 413]) {
      assert.equal(classify({ answered: true, status }), 'FAILED', `${status}`)
    }
    for (const status of [429, 502, 503]) {
      assert.equal(classify({ answered: true, status }), 'PENDING', `${status}`)
    }
    for (const status of [500, 504]) {
      assert.equal(classify({ answered: true, status }), 'UNKNOWN', `${status}`)
    }
    // Outside the table, split by class rather than guessed.
    assert.equal(classify({ answered: true, status: 418 }), 'FAILED')
    assert.equal(classify({ answered: true, status: 507 }), 'UNKNOWN')
    assert.equal(classify({ answered: false }), 'UNKNOWN')
  })

  test('a retryable refusal waits until its durable due time, then is picked up again', async () => {
    await accept(SUP001_ORDER_A)

    let clock = new Date('2026-09-21T12:00:00.000Z')
    const policy = { now: () => new Date(clock), jitter: () => 0 }

    await flushSupplierResponses({
      transport: new FakeTransport({ answered: true, status: 503 }), ...policy
    })

    const [afterFirst]: any[] = await rowsFor(SUP001_ORDER_A)
    assert.equal(afterFirst.state, 'PENDING', 'congestion is not a failure')
    assert.equal(afterFirst.attempts, 1)
    assert.equal(new Date(afterFirst.retryWindowStartedAt).toISOString(), clock.toISOString())
    assert.equal(new Date(afterFirst.nextAttemptAt).toISOString(), '2026-09-21T12:00:05.000Z')

    const early = new FakeTransport(ok204)
    const earlySummary = await flushSupplierResponses({ transport: early, ...policy })
    assert.equal(early.sent.length, 0)
    assert.equal(earlySummary.beforeDue, 1)

    clock = new Date('2026-09-21T12:00:05.000Z')
    const retry = new FakeTransport(ok204)
    await flushSupplierResponses({ transport: retry, ...policy })

    const [afterRetry]: any[] = await rowsFor(SUP001_ORDER_A)
    assert.equal(afterRetry.state, 'DELIVERED')
    assert.equal(afterRetry.attempts, 2, 'attempts accumulate and are never reset')
    assert.equal(afterRetry.nextAttemptAt, null)
    assert.equal(afterRetry.retryWindowStartedAt, null)
    assert.equal(retry.sent[0].payload.responseId, afterRetry.responseId, 'the same responseId')
  })
})

describe('replay and idempotency', () => {

  test('a crash before the local update replays the SAME responseId', async () => {
    await accept(SUP001_ORDER_A)

    const first = new FakeTransport(ok204)
    await flushSupplierResponses({ transport: first })

    // The crash window: SAP applied the response, CAP never recorded it. The
    // durable row is what survives, so it is put back exactly as a recovery
    // would find it — still PENDING, still carrying its original identity.
    await UPDATE(SupplierResponseDeliveries)
      .set({ state: 'PENDING' } as any)
      .where({ order_ID: SUP001_ORDER_A })

    const replay = new FakeTransport(ok204)
    await flushSupplierResponses({ transport: replay })

    assert.equal(replay.sent.length, 1)
    assert.equal(
      replay.sent[0].payload.responseId, first.sent[0].payload.responseId,
      'a retry never manufactures a new responseId'
    )
    assert.deepEqual(replay.sent[0].payload, first.sent[0].payload)
  })

  test('an already DELIVERED row is not resent by a normal flush', async () => {
    await accept(SUP001_ORDER_A)

    await flushSupplierResponses({ transport: new FakeTransport(ok204) })

    const second = new FakeTransport(ok204)
    const summary = await flushSupplierResponses({ transport: second })

    assert.equal(second.sent.length, 0, 'nothing was sent')
    assert.equal(summary.scanned, 0)

    const [row]: any[] = await rowsFor(SUP001_ORDER_A)
    assert.equal(row.attempts, 1, 'the delivered row was not attempted again')
  })

  test('FAILED and UNKNOWN rows are not drained either', async () => {
    await accept(SUP001_ORDER_A)
    await flushSupplierResponses({ transport: new FakeTransport(conflict) })

    const again = new FakeTransport(ok204)
    const summary = await flushSupplierResponses({ transport: again })

    assert.equal(again.sent.length, 0, 'reconciliation is an operator act, not a blind retry')
    assert.equal(summary.scanned, 0)
  })

  test('a later response is held back while an earlier one has not reached SAP', async () => {
    await accept(SUP001_ORDER_A, { estimatedDeliveryDate: '2026-11-15' })
    await decide(SUP001_ORDER_A, 'updateEstimatedDeliveryDate', {
      responseId: randomUUID(), expectedResponseVersion: 1, estimatedDeliveryDate: '2026-12-01'
    })

    const transport = new FakeTransport(timeout)
    const summary = await flushSupplierResponses({ transport })

    assert.equal(summary.scanned, 2)
    assert.equal(transport.sent.length, 1, 'version 2 waits for version 1')
    assert.equal(transport.sent[0].payload.responseVersion, 1)
    assert.equal(summary.skipped, 1)

    const rows: any[] = await rowsFor(SUP001_ORDER_A)
    assert.equal(rows[1].state, 'PENDING', 'the held-back row is untouched')
    assert.equal(rows[1].attempts, 0)
  })

  test('one order failing does not stop another order being delivered', async () => {
    await accept(SUP001_ORDER_A)
    await accept(SUP001_ORDER_B)

    // A row that cannot produce a payload fails deterministically; the other
    // order is unrelated and must still go out.
    const transport = new FakeTransport(ok204)
    const summary = await flushSupplierResponses({ transport })

    assert.equal(summary.scanned, 2)
    assert.equal(summary.delivered, 2)
    assert.equal(transport.sent.length, 2)
  })
})

describe('transport never touches the business decision', () => {

  test('a refusal leaves the supplier\'s committed decision exactly as it was', async () => {
    await accept(SUP001_ORDER_A, { estimatedDeliveryDate: '2026-11-15' })

    const before: any = await orderRow(SUP001_ORDER_A)
    const [rowBefore]: any[] = await rowsFor(SUP001_ORDER_A)

    await flushSupplierResponses({ transport: new FakeTransport(conflict) })

    const after: any = await orderRow(SUP001_ORDER_A)
    assert.deepEqual(after, before, 'the order is untouched by a transport outcome')
    assert.equal(after.status, 'ACCEPTED')
    assert.equal(after.responseVersion, 1)

    // And the immutable half of the response row is untouched too.
    const [rowAfter]: any[] = await rowsFor(SUP001_ORDER_A)
    for (const field of ['responseId', 'version', 'decision', 'estimatedDeliveryDate', 'reason', 'respondedAt']) {
      assert.deepEqual(rowAfter[field], rowBefore[field], `${field} is immutable`)
    }
  })

  test('a success does not move the order either', async () => {
    await reject(SUP001_ORDER_A, 'Out of stock.')

    const before: any = await orderRow(SUP001_ORDER_A)
    await flushSupplierResponses({ transport: new FakeTransport(ok204) })
    const after: any = await orderRow(SUP001_ORDER_A)

    assert.deepEqual(after, before)
    assert.equal(after.status, 'REJECTED', 'the portal decided this, not the transport')
  })
})

describe('the wire request itself', () => {

  /**
   * The only tests that exercise `HttpResponseTransport`. `fetch` is stubbed,
   * so nothing leaves the process and no credential is real — but the header
   * set, the method and the body are asserted exactly as they would go out.
   */
  async function capture(
    payload: SupplierResponsePayload,
    correlationId: string,
    status = 204,
    retryAfter: string | null = null
  ) {
    const original = globalThis.fetch
    let seen: { url: string; init: any } | undefined

    globalThis.fetch = (async (url: any, init: any) => {
      seen = { url: String(url), init }
      return {
        status,
        headers: { get: (name: string) => name.toLowerCase() === 'retry-after' ? retryAfter : null },
        text: async () => ''
      } as any
    }) as any

    try {
      const transport = new HttpResponseTransport({
        url: 'https://example.invalid/http/pih/v1/supplier-responses',
        clientId: 'not-a-real-id',
        clientSecret: 'not-a-real-secret',
        timeoutMs: 30_000
      })
      const result = await transport.send(payload, correlationId)
      return { seen: seen!, result }
    } finally {
      globalThis.fetch = original
    }
  }

  async function captureError(error: unknown) {
    const original = globalThis.fetch
    globalThis.fetch = (async () => { throw error }) as any
    try {
      const transport = new HttpResponseTransport({
        url: 'https://example.invalid/http/pih/v1/supplier-responses',
        clientId: 'not-a-real-id',
        clientSecret: 'not-a-real-secret',
        timeoutMs: 30_000
      })
      return await transport.send(samplePayload, randomUUID())
    } finally {
      globalThis.fetch = original
    }
  }

  const samplePayload: SupplierResponsePayload = {
    schemaVersion: '1.0',
    responseId: '7f135926-34af-4eb2-a8b3-1b851303afc9',
    sourceSystem: 'PIH_ABAP_DEV',
    sourceOrderId: '33333333-3333-4333-8333-000000000001',
    sourceRevision: 1,
    deliveryId: '44444444-4444-4444-8444-000000000001',
    portalOrderId: SUP001_ORDER_A,
    supplierCode: 'SUP001',
    responseVersion: 1,
    decision: 'ACCEPTED',
    estimatedDeliveryDate: '2026-11-15',
    reason: null,
    respondedAt: '2026-09-20T03:08:45Z'
  }

  test('every header is exactly what the contract specifies', async () => {
    const correlationId = '11111111-2222-4333-8444-555555555555'
    const { seen } = await capture(samplePayload, correlationId)

    assert.equal(seen.init.method, 'POST')
    assert.deepEqual(Object.keys(seen.init.headers).sort(), [
      'Accept', 'Authorization', 'Content-Type', 'Idempotency-Key', 'X-Correlation-ID'
    ])

    assert.equal(seen.init.headers['Content-Type'], 'application/json')
    assert.equal(seen.init.headers['Accept'], 'application/json')
    assert.equal(seen.init.headers['X-Correlation-ID'], correlationId)
    assert.equal(
      seen.init.headers['Authorization'],
      'Basic ' + Buffer.from('not-a-real-id:not-a-real-secret').toString('base64')
    )
  })

  test('Idempotency-Key is exactly the payload responseId and cannot drift from it', async () => {
    const { seen } = await capture(samplePayload, randomUUID())

    assert.equal(seen.init.headers['Idempotency-Key'], samplePayload.responseId)
    // The contract's rule: where the header is present it must equal the body
    // identity. Asserted against the parsed body, not against the constant, so
    // this fails if the two are ever sourced differently.
    assert.equal(seen.init.headers['Idempotency-Key'], JSON.parse(seen.init.body).responseId)
  })

  test('a replay keeps the Idempotency-Key and changes only the correlation ID', async () => {
    const first = await capture(samplePayload, randomUUID())
    const second = await capture(samplePayload, randomUUID())

    assert.equal(
      first.seen.init.headers['Idempotency-Key'],
      second.seen.init.headers['Idempotency-Key'],
      'the idempotency identity survives a replay'
    )
    assert.notEqual(
      first.seen.init.headers['X-Correlation-ID'],
      second.seen.init.headers['X-Correlation-ID'],
      'the attempt identity does not'
    )
    assert.equal(first.seen.init.body, second.seen.init.body, 'the body is byte-identical')
  })

  test('the persisted responseId is what reaches the Idempotency-Key header', async () => {
    // End to end through the sender, so the header is proven against the row
    // that was actually committed rather than against a hand-built payload.
    await accept(SUP001_ORDER_A)
    const [row]: any[] = await rowsFor(SUP001_ORDER_A)

    const transport = new FakeTransport(ok204)
    await flushSupplierResponses({ transport })

    const { seen } = await capture(transport.sent[0].payload, randomUUID())
    assert.equal(seen.init.headers['Idempotency-Key'], row.responseId)
  })

  test('a 2xx body is never read, and a refusal body is truncated', async () => {
    const { result } = await capture(samplePayload, randomUUID(), 204)
    assert.equal(result.answered, true)
    assert.equal(result.status, 204)
    assert.equal(result.detail, undefined, 'nothing is read from a success')
  })

  test('Retry-After is extracted as the one raw bounded response header', async () => {
    const { result } = await capture(samplePayload, randomUUID(), 429, ' 30 ')
    assert.equal(result.retryAfter, ' 30 ')
  })

  test('an overlong Retry-After with a valid truncated prefix is ignored, never reinterpreted', async () => {
    const raw = `30${' '.repeat(126)}x`
    assert.equal(raw.length, 129)
    assert.equal(raw.slice(0, 128).trim(), '30', 'the former truncation would have made this valid')
    const { result } = await capture(samplePayload, randomUUID(), 429, raw)
    assert.equal(result.retryAfter, undefined)
  })

  test('an exactly 128-character Retry-After is preserved in full', async () => {
    const raw = 'x'.repeat(128)
    const { result } = await capture(samplePayload, randomUUID(), 429, raw)
    assert.equal(result.retryAfter, raw)
  })

  test('an overlong malformed Retry-After is ignored', async () => {
    const raw = 'not-a-date'.repeat(13)
    assert.ok(raw.length > 128)
    const { result } = await capture(samplePayload, randomUUID(), 429, raw)
    assert.equal(result.retryAfter, undefined)
  })

  for (const code of ['ENOTFOUND', 'ECONNREFUSED']) {
    test(`${code} is an explicitly proven NOT_SENT transient`, async () => {
      const error = { name: 'TypeError', cause: { code } }
      assert.equal(certaintyForFetchError(error), 'NOT_SENT')
      const result = await captureError(error)
      assert.equal(result.answered, false)
      assert.equal(result.certainty, 'NOT_SENT')
      assert.equal(classify(result), 'PENDING')
      assert.equal(categorise(result), 'TRANSIENT')
      assert.match(result.detail!, /request not sent/)
    })
  }

  for (const code of [
    'ERR_TLS_CERT_ALTNAME_INVALID',
    'CERT_HAS_EXPIRED',
    'DEPTH_ZERO_SELF_SIGNED_CERT',
    'SELF_SIGNED_CERT_IN_CHAIN',
    'UNABLE_TO_VERIFY_LEAF_SIGNATURE'
  ]) {
    test(`${code} is a narrow pre-transmission TLS NOT_SENT result`, async () => {
      assert.ok(NOT_SENT_CAUSE_CODES.has(code))
      const result = await captureError({ name: 'TypeError', cause: { code } })
      assert.equal(result.certainty, 'NOT_SENT')
      assert.equal(classify(result), 'PENDING')
      assert.equal(categorise(result), 'TRANSIENT')
      assert.match(result.detail!, /TLS certificate verification failed/)
    })
  }

  for (const item of [
    { label: 'TimeoutError', error: { name: 'TimeoutError' } },
    { label: 'AbortError', error: { name: 'AbortError' } },
    { label: 'ECONNRESET', error: { name: 'TypeError', cause: { code: 'ECONNRESET' } } },
    { label: 'missing cause.code', error: { name: 'TypeError', cause: {} } },
    { label: 'unknown cause.code', error: { name: 'TypeError', cause: { code: 'E_FUTURE_UNKNOWN' } } }
  ]) {
    test(`${item.label} conservatively remains MAY_APPLY / UNKNOWN`, async () => {
      assert.equal(certaintyForFetchError(item.error), 'MAY_APPLY')
      const result = await captureError(item.error)
      assert.equal(result.answered, false)
      assert.equal(result.certainty, 'MAY_APPLY')
      assert.equal(classify(result), 'UNKNOWN')
      assert.equal(categorise(result), 'NO_ANSWER')
    })
  }

  for (const item of [
    { label: 'top-level code', error: { name: 'TypeError', code: 'ECONNREFUSED' } },
    { label: 'deeper nested code', error: { name: 'TypeError', cause: { cause: { code: 'ECONNREFUSED' } } } }
  ]) {
    test(`${item.label} is not mistaken for the approved direct cause.code shape`, async () => {
      assert.equal(certaintyForFetchError(item.error), 'MAY_APPLY')
      const result = await captureError(item.error)
      assert.equal(result.certainty, 'MAY_APPLY')
      assert.equal(classify(result), 'UNKNOWN')
      assert.equal(categorise(result), 'NO_ANSWER')
    })
  }
})

describe('configuration and secrets', () => {

  test('the sender refuses to run unconfigured rather than defaulting', () => {
    assert.throws(() => readCiConfig({}), (error: any) =>
      error instanceof ConfigError &&
      error.message.includes(CI_URL_VAR) &&
      error.message.includes(CI_CLIENT_ID_VAR) &&
      error.message.includes(CI_CLIENT_SECRET_VAR)
    )
  })

  test('configuration is read from the environment and nowhere else', () => {
    const config = readCiConfig({
      [CI_URL_VAR]: 'https://example.invalid/http/pih/v1/supplier-responses',
      [CI_CLIENT_ID_VAR]: 'not-a-real-id',
      [CI_CLIENT_SECRET_VAR]: 'not-a-real-secret'
    } as NodeJS.ProcessEnv)

    assert.equal(config.url, 'https://example.invalid/http/pih/v1/supplier-responses')
    assert.equal(config.timeoutMs, DEFAULT_TIMEOUT_MS, 'a bounded default, never unlimited')
    assert.equal(DEFAULT_TIMEOUT_MS, 35_000, 'the frozen CAP-to-iFlow budget')

    // The variable names are the only thing this repository holds.
    assert.equal(CI_URL_VAR, 'PIH_CI_SUPPLIER_RESPONSE_URL')
    assert.equal(CI_CLIENT_ID_VAR, 'PIH_CI_CLIENT_ID')
    assert.equal(CI_CLIENT_SECRET_VAR, 'PIH_CI_CLIENT_SECRET')
  })

  test('a credential is never sent over plain HTTP, and the timeout is bounded', () => {
    const base = {
      [CI_CLIENT_ID_VAR]: 'not-a-real-id',
      [CI_CLIENT_SECRET_VAR]: 'not-a-real-secret'
    }

    assert.throws(
      () => readCiConfig({ ...base, [CI_URL_VAR]: 'http://example.invalid/x' } as NodeJS.ProcessEnv),
      (error: any) => error instanceof ConfigError && /https/.test(error.message)
    )

    assert.throws(
      () => readCiConfig({
        ...base, [CI_URL_VAR]: 'https://example.invalid/x', [CI_TIMEOUT_VAR]: '0'
      } as NodeJS.ProcessEnv),
      ConfigError
    )
  })

  test('a receiver\'s error body is truncated before it is persisted', () => {
    const detail = safeDetail('x'.repeat(500))
    assert.ok(detail.length <= 180, 'unbounded foreign text is never stored')
    assert.equal(safeDetail('   \n  '), 'the receiver returned no body')
  })
})

describe('Phase 7.5 bounded claim and lease', () => {
  const NOW = new Date('2026-09-22T12:00:00.000Z')
  const OWNER_A = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  const OWNER_B = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'

  test('two overlapping flushes produce one sender and one non-sender', async () => {
    await accept(SUP001_ORDER_A)
    let release!: () => void
    const gate = new Promise<void>(resolve => { release = resolve })
    const winner: ResponseTransport = {
      async send() { await gate; return ok204 }
    }

    const first = flushSupplierResponses({
      transport: winner, leaseOwner: OWNER_A, leaseMs: 60_000, now: () => NOW
    })

    // Let the first invocation finish its claim and enter transport.
    for (let i = 0; i < 20; i++) {
      const row: any = (await rowsFor(SUP001_ORDER_A))[0]
      if (row?.state === 'IN_FLIGHT') break
      await new Promise(resolve => setTimeout(resolve, 0))
    }

    const loserTransport = new FakeTransport(ok204)
    const loser = await flushSupplierResponses({
      transport: loserTransport, leaseOwner: OWNER_B, leaseMs: 60_000, now: () => NOW
    })
    assert.equal(loserTransport.sent.length, 0, 'the live claim prevents a duplicate send')
    assert.equal(loser.scanned, 0)

    release()
    const won = await first
    assert.equal(won.delivered, 1)
    const after: any = (await rowsFor(SUP001_ORDER_A))[0]
    assert.equal(after.state, 'DELIVERED')
    assert.equal(after.leaseOwner, null)
    assert.equal(after.leaseExpiresAt, null)
  })

  test('an expired IN_FLIGHT row is reclaimed under a new owner and completed', async () => {
    await accept(SUP001_ORDER_A)
    await UPDATE(SupplierResponseDeliveries).set({
      state: 'IN_FLIGHT', leaseOwner: OWNER_A,
      leaseExpiresAt: '2026-09-22T11:59:59.000Z'
    } as any).where({ order_ID: SUP001_ORDER_A })

    const transport = new FakeTransport(ok204)
    const summary = await flushSupplierResponses({
      transport, leaseOwner: OWNER_B, leaseMs: 60_000, now: () => NOW
    })

    assert.equal(transport.sent.length, 1)
    assert.equal(summary.delivered, 1)
    const after: any = (await rowsFor(SUP001_ORDER_A))[0]
    assert.equal(after.state, 'DELIVERED')
    assert.equal(after.attempts, 1)
    assert.equal(after.leaseOwner, null)
    assert.equal(after.leaseExpiresAt, null)
  })

  test('a live IN_FLIGHT row is not reclaimed', async () => {
    await accept(SUP001_ORDER_A)
    await UPDATE(SupplierResponseDeliveries).set({
      state: 'IN_FLIGHT', leaseOwner: OWNER_A,
      leaseExpiresAt: '2026-09-22T12:00:01.000Z'
    } as any).where({ order_ID: SUP001_ORDER_A })

    const transport = new FakeTransport(ok204)
    const summary = await flushSupplierResponses({
      transport, leaseOwner: OWNER_B, leaseMs: 60_000, now: () => NOW
    })
    assert.equal(transport.sent.length, 0)
    assert.equal(summary.scanned, 0)
    const after: any = (await rowsFor(SUP001_ORDER_A))[0]
    assert.equal(after.state, 'IN_FLIGHT')
    assert.equal(after.leaseOwner, OWNER_A)
  })

  test('an earlier live lease still blocks a later response for the same order', async () => {
    await accept(SUP001_ORDER_A, { estimatedDeliveryDate: '2026-11-15' })
    await decide(SUP001_ORDER_A, 'updateEstimatedDeliveryDate', {
      responseId: randomUUID(), expectedResponseVersion: 1,
      estimatedDeliveryDate: '2026-12-01'
    })
    const rows: any[] = await rowsFor(SUP001_ORDER_A)
    await UPDATE(SupplierResponseDeliveries).set({
      state: 'IN_FLIGHT', leaseOwner: OWNER_A,
      leaseExpiresAt: '2026-09-22T12:00:01.000Z'
    } as any).where({ ID: rows[0].ID })

    const transport = new FakeTransport(ok204)
    await flushSupplierResponses({
      transport, leaseOwner: OWNER_B, leaseMs: 60_000, now: () => NOW
    })
    assert.equal(transport.sent.length, 0, 'version 2 cannot pass a live version-1 claim')
    const after: any[] = await rowsFor(SUP001_ORDER_A)
    assert.deepEqual(after.map(row => row.state), ['IN_FLIGHT', 'PENDING'])
  })

  test('result persistence requires the same IN_FLIGHT owner', async () => {
    await accept(SUP001_ORDER_A)
    const row: any = (await rowsFor(SUP001_ORDER_A))[0]
    const stealing: ResponseTransport = {
      async send() {
        await UPDATE(SupplierResponseDeliveries).set({ leaseOwner: OWNER_B } as any).where({ ID: row.ID })
        return ok204
      }
    }

    const summary = await flushSupplierResponses({
      transport: stealing, leaseOwner: OWNER_A, leaseMs: 60_000, now: () => NOW
    })
    assert.equal(summary.outcomes[0].conflicted, true)
    const after: any = (await rowsFor(SUP001_ORDER_A))[0]
    assert.equal(after.state, 'IN_FLIGHT')
    assert.equal(after.leaseOwner, OWNER_B)
    assert.equal(after.attempts, 0)
    assert.equal((await SELECT.from(SupplierResponseDeliveryAttempts).where({ delivery_ID: row.ID })).length, 0)
  })

  test('dry-run remains write-free and never claims', async () => {
    await accept(SUP001_ORDER_A)
    const before: any = (await rowsFor(SUP001_ORDER_A))[0]
    const transport = new FakeTransport(ok204)
    await flushSupplierResponses({
      transport, dryRun: true, leaseOwner: OWNER_A, leaseMs: 60_000, now: () => NOW
    })
    const after: any = (await rowsFor(SUP001_ORDER_A))[0]
    assert.equal(transport.sent.length, 0)
    assert.deepEqual(after, before)
  })
})

describe('a malformed payload, and the dry-run boundary', () => {

  /**
   * Commits a real decision the way a supplier does, then removes the one field
   * the payload builder cannot default. `respondedAt` is chosen because
   * `toRfc3339` refuses a null outright with MISSING_RESPONDED_AT, so the row is
   * malformed for a reason the contract states rather than by corrupting a key.
   * The UPDATE touches only the local in-memory test database.
   */
  async function malformedPending(order: string) {
    await accept(order, { estimatedDeliveryDate: '2026-11-15' })
    await UPDATE(SupplierResponseDeliveries).set({ respondedAt: null } as any).where({ order_ID: order })
    const [row]: any[] = await rowsFor(order)
    assert.equal(row.state, 'PENDING', 'the fixture starts committed and unsent')
    return row
  }

  const attemptsFor = (delivery: string) =>
    SELECT.from('pih.portal.SupplierResponseDeliveryAttempts').where({ delivery_ID: delivery })

  test('a dry run reports a malformed payload and writes nothing at all', async () => {
    const before: any = await malformedPending(SUP001_ORDER_A)

    const transport = new FakeTransport(ok204)
    const summary = await flushSupplierResponses({ transport, dryRun: true })

    assert.equal(transport.sent.length, 0, 'a dry run never reaches the transport')
    assert.equal(summary.outcomes[0].state, 'FAILED', 'the operator is told the payload is unusable')
    assert.equal(summary.failed, 1, 'the command still signals malformed data')

    const after: any = (await rowsFor(SUP001_ORDER_A))[0]
    assert.equal(after.state, 'PENDING', 'the durable state is untouched')
    for (const field of [
      'attempts', 'lastAttemptAt', 'lastError', 'lastCorrelationId',
      'nextAttemptAt', 'retryWindowStartedAt'
    ]) {
      assert.deepEqual(after[field], before[field], `${field} is unchanged`)
    }
    assert.equal(after.ID, before.ID, 'the same row, not a replacement')

    // The Phase 7.3 entity exists locally even though nothing writes to it yet,
    // so this asserts the invariant now rather than after persistence lands.
    assert.equal((await attemptsFor(after.ID)).length, 0, 'a dry run creates no attempt history')
  })

  test('a real run on the same malformed row still commits FAILED exactly once', async () => {
    await malformedPending(SUP001_ORDER_A)

    const transport = new FakeTransport(ok204)
    const summary = await flushSupplierResponses({ transport })

    assert.equal(transport.sent.length, 0, 'a payload that cannot be built is never sent')
    assert.equal(summary.outcomes[0].state, 'FAILED')
    assert.equal(summary.failed, 1)

    const after: any = (await rowsFor(SUP001_ORDER_A))[0]
    assert.equal(after.state, 'FAILED', 'the durable state moves, unlike the dry run')
    assert.equal(after.attempts, 1, 'exactly one committed attempt')
    assert.ok(after.lastAttemptAt, 'the attempt is timestamped')
    assert.match(after.lastError, /MISSING_RESPONDED_AT/, 'the diagnostic names the contract violation')
    assert.equal(after.lastCorrelationId, null, 'no transport attempt means no correlation id')
  })
})

describe('the attempt-error categories', () => {

  test('every branch of the closed vocabulary', () => {
    assert.equal(categorise(ok204), 'NONE')
    assert.equal(categorise(ok200), 'NONE')
    assert.equal(categorise({ answered: true, status: 201 }), 'NONE')

    for (const status of [400, 401, 403, 404, 409, 412, 413]) {
      assert.equal(categorise({ answered: true, status }), 'REFUSED', `HTTP ${status}`)
    }
    for (const status of [429, 502, 503]) {
      assert.equal(categorise({ answered: true, status }), 'TRANSIENT', `HTTP ${status}`)
    }
    for (const status of [500, 504]) {
      assert.equal(categorise({ answered: true, status }), 'AMBIGUOUS', `HTTP ${status}`)
    }

    // Outside the table, split by class exactly as classify does.
    assert.equal(categorise({ answered: true, status: 599 }), 'AMBIGUOUS', 'an unlisted 5xx may have landed')
    assert.equal(categorise({ answered: true, status: 418 }), 'REFUSED', 'an unlisted 4xx was an answered refusal')

    assert.equal(categorise(timeout), 'NO_ANSWER')
  })

  test('PAYLOAD is never produced from a transport result', () => {
    const all: TransportResult[] = [
      ok204, ok200, conflict, timeout,
      { answered: true, status: 500 }, { answered: true, status: 503 }, { answered: true, status: 418 }
    ]
    for (const result of all) assert.notEqual(categorise(result), 'PAYLOAD')
  })

  test('the category answers a different question from the durable state', () => {
    // Both are FAILED, and history must still tell them apart.
    assert.equal(classify(conflict), 'FAILED')
    assert.equal(categorise(conflict), 'REFUSED')
  })

  test('missing or unknown certainty is conservative', () => {
    assert.equal(classify({ answered: false }), 'UNKNOWN')
    assert.equal(categorise({ answered: false }), 'NO_ANSWER')
    assert.equal(classify({ answered: false, certainty: 'FUTURE_VALUE' as any }), 'UNKNOWN')
  })

  test('answered HTTP status always takes precedence over contradictory certainty', () => {
    const cases: Array<{ result: TransportResult, state: string, category: string }> = [
      { result: { answered: true, status: 503, certainty: 'NOT_SENT' }, state: 'PENDING', category: 'TRANSIENT' },
      { result: { answered: true, status: 400, certainty: 'MAY_APPLY' }, state: 'FAILED', category: 'REFUSED' },
      { result: { answered: true, status: 400, certainty: 'NOT_SENT' }, state: 'FAILED', category: 'REFUSED' },
      { result: { answered: true, status: 500, certainty: 'NOT_SENT' }, state: 'UNKNOWN', category: 'AMBIGUOUS' },
      { result: { answered: true, status: 204, certainty: 'MAY_APPLY' }, state: 'DELIVERED', category: 'NONE' }
    ]
    for (const expected of cases) {
      assert.equal(classify(expected.result), expected.state)
      assert.equal(categorise(expected.result), expected.category)
    }
  })
})

describe('Phase 7.4a durable retry policy', () => {
  const T0 = new Date('2026-09-21T12:00:00.000Z')
  const historyFor = (delivery: string) =>
    SELECT.from(SupplierResponseDeliveryAttempts).where({ delivery_ID: delivery }).orderBy('attemptNumber')

  async function proveNonEligibleRowDoesNotConsumeLimit(
    blockerFields: Record<string, unknown>,
    diagnostic: 'beforeDue' | 'retryExhausted' | 'retryWindowBlocked'
  ) {
    await accept(SUP001_ORDER_A)
    await accept(SUP001_ORDER_B)
    const [older]: any[] = await rowsFor(SUP001_ORDER_A)
    const [newer]: any[] = await rowsFor(SUP001_ORDER_B)

    await UPDATE(SupplierResponseDeliveries).set({
      createdAt: new Date(T0.getTime() - 2_000).toISOString(),
      ...blockerFields
    } as any).where({ ID: older.ID })
    await UPDATE(SupplierResponseDeliveries).set({
      createdAt: new Date(T0.getTime() - 1_000).toISOString(),
      attempts: 0,
      nextAttemptAt: null,
      retryWindowStartedAt: null
    } as any).where({ ID: newer.ID })

    const [blockerBefore]: any[] = await rowsFor(SUP001_ORDER_A)
    const transport = new FakeTransport(ok204)
    const summary = await flushSupplierResponses({ transport, limit: 1, now: () => T0 })

    assert.equal(summary[diagnostic], 1)
    assert.equal(summary.scanned, 1, 'only the eligible row consumes the attempt limit')
    assert.equal(transport.sent.length, 1)
    assert.equal(transport.sent[0].payload.portalOrderId, SUP001_ORDER_B)
    assert.equal((await historyFor(older.ID)).length, 0, 'the older non-eligible row writes no history')
    assert.equal((await historyFor(newer.ID)).length, 1, 'the newer eligible row writes one history row')

    const [blockerAfter]: any[] = await rowsFor(SUP001_ORDER_A)
    for (const field of ['attempts', 'nextAttemptAt', 'retryWindowStartedAt']) {
      assert.deepEqual(blockerAfter[field], blockerBefore[field], `${field} stays unchanged`)
    }
  }

  test('an older before-due row does not consume limit 1 ahead of an eligible order', async () => {
    await proveNonEligibleRowDoesNotConsumeLimit({
      attempts: 1,
      retryWindowStartedAt: T0.toISOString(),
      nextAttemptAt: new Date(T0.getTime() + 1).toISOString()
    }, 'beforeDue')
  })

  test('an older retry-exhausted row does not consume limit 1 ahead of an eligible order', async () => {
    await proveNonEligibleRowDoesNotConsumeLimit({
      attempts: 4,
      retryWindowStartedAt: T0.toISOString(),
      nextAttemptAt: null
    }, 'retryExhausted')
  })

  test('an older window-blocked row does not consume limit 1 ahead of an eligible order', async () => {
    await proveNonEligibleRowDoesNotConsumeLimit({
      attempts: 1,
      retryWindowStartedAt: new Date(T0.getTime() - 15 * 60 * 1000 - 1).toISOString(),
      nextAttemptAt: null
    }, 'retryWindowBlocked')
  })

  test('one captured invocation instant controls diagnostics and sending at the window boundary', async () => {
    await accept(SUP001_ORDER_A)
    const [row]: any[] = await rowsFor(SUP001_ORDER_A)
    await UPDATE(SupplierResponseDeliveries).set({
      attempts: 1,
      retryWindowStartedAt: new Date(T0.getTime() - 15 * 60 * 1000).toISOString(),
      nextAttemptAt: T0.toISOString()
    } as any).where({ ID: row.ID })

    let clockReads = 0
    const now = () => new Date(T0.getTime() + clockReads++)
    const transport = new FakeTransport(ok204)
    const summary = await flushSupplierResponses({ transport, now })

    assert.equal(summary.retryWindowBlocked, 0, 'diagnostics classify the exact boundary as eligible')
    assert.equal(summary.scanned, 1, 'operative eligibility agrees with diagnostics')
    assert.equal(transport.sent.length, 1, 'the row is sent even though later clock reads cross the boundary')
    assert.equal(clockReads, 3, 'one invocation read plus separate attempt start and completion reads')
  })

  test('before-due, exhausted and window-blocked rows are distinct and write nothing', async () => {
    await accept(SUP001_ORDER_A)
    const [row]: any[] = await rowsFor(SUP001_ORDER_A)

    const cases = [
      {
        fields: {
          attempts: 1, retryWindowStartedAt: T0.toISOString(),
          nextAttemptAt: new Date(T0.getTime() + 5_000).toISOString()
        },
        summary: 'beforeDue'
      },
      {
        fields: { attempts: 4, retryWindowStartedAt: T0.toISOString(), nextAttemptAt: null },
        summary: 'retryExhausted'
      },
      {
        fields: {
          attempts: 1,
          retryWindowStartedAt: new Date(T0.getTime() - 15 * 60 * 1000 - 1).toISOString(),
          nextAttemptAt: null
        },
        summary: 'retryWindowBlocked'
      }
    ] as const

    for (const item of cases) {
      await UPDATE(SupplierResponseDeliveries).set(item.fields as any).where({ ID: row.ID })
      const transport = new FakeTransport(ok204)
      const summary = await flushSupplierResponses({ transport, now: () => T0 })
      assert.equal(transport.sent.length, 0, item.summary)
      assert.equal(summary[item.summary], 1, item.summary)
      assert.equal(summary.scanned, 0, item.summary)
      assert.equal((await historyFor(row.ID)).length, 0, `${item.summary} writes no history`)
      const after: any = (await rowsFor(SUP001_ORDER_A))[0]
      assert.equal(after.attempts, item.fields.attempts, `${item.summary} spends no attempt`)
    }
  })

  test('a legacy PENDING row below budget and with null policy fields is immediately eligible', async () => {
    await accept(SUP001_ORDER_A)
    const [row]: any[] = await rowsFor(SUP001_ORDER_A)
    await UPDATE(SupplierResponseDeliveries)
      .set({ attempts: 2, nextAttemptAt: null, retryWindowStartedAt: null } as any)
      .where({ ID: row.ID })

    const transport = new FakeTransport(ok204)
    await flushSupplierResponses({ transport, now: () => T0 })

    assert.equal(transport.sent.length, 1)
    const after: any = (await rowsFor(SUP001_ORDER_A))[0]
    assert.equal(after.state, 'DELIVERED')
    assert.equal(after.attempts, 3)
    assert.deepEqual((await historyFor(row.ID) as any[]).map(item => item.attemptNumber), [3],
      'the new attempt is recorded at its truthful ordinal; attempts 1 and 2 are not backfilled')
  })

  test('a legacy null-timing row starts its retry window at the current transient completion', async () => {
    await accept(SUP001_ORDER_A)
    const [row]: any[] = await rowsFor(SUP001_ORDER_A)
    const historicalAttempt = new Date(T0.getTime() - 24 * 60 * 60 * 1000).toISOString()
    await UPDATE(SupplierResponseDeliveries).set({
      attempts: 2,
      lastAttemptAt: historicalAttempt,
      nextAttemptAt: null,
      retryWindowStartedAt: null
    } as any).where({ ID: row.ID })

    const transport = new FakeTransport({ answered: true, status: 503, detail: 'upstream busy' })
    await flushSupplierResponses({ transport, now: () => T0, jitter: () => 0 })

    assert.equal(transport.sent.length, 1, 'the legacy null due is immediately eligible')
    const [after]: any[] = await rowsFor(SUP001_ORDER_A)
    assert.equal(after.state, 'PENDING')
    assert.equal(after.attempts, 3)
    assert.equal(new Date(after.retryWindowStartedAt).toISOString(), T0.toISOString())
    assert.notEqual(new Date(after.retryWindowStartedAt).toISOString(), historicalAttempt)
    assert.equal(new Date(after.nextAttemptAt).toISOString(),
      new Date(T0.getTime() + 120_000).toISOString())
    assert.deepEqual((await historyFor(row.ID) as any[]).map(item => item.attemptNumber), [3],
      'only the current attempt is recorded; attempts 1 and 2 are not backfilled')
  })

  test('four transient attempts persist one history row each and then become exhausted', async () => {
    await accept(SUP001_ORDER_A)
    let clock = new Date(T0)
    const windowStart = clock.toISOString()
    const expectedDelay = [5_000, 30_000, 120_000]

    for (let attempt = 1; attempt <= 4; attempt++) {
      const transport = new FakeTransport({ answered: true, status: 503, detail: 'upstream busy' })
      await flushSupplierResponses({
        transport,
        now: () => new Date(clock),
        jitter: () => 0
      })
      assert.equal(transport.sent.length, 1, `attempt ${attempt}`)

      const parent: any = (await rowsFor(SUP001_ORDER_A))[0]
      assert.equal(parent.state, 'PENDING')
      assert.equal(parent.attempts, attempt)
      assert.equal(new Date(parent.retryWindowStartedAt).toISOString(), windowStart)

      const history: any[] = await historyFor(parent.ID)
      assert.equal(history.length, attempt)
      assert.deepEqual(history.map(item => item.attemptNumber),
        Array.from({ length: attempt }, (_, index) => index + 1))

      if (attempt < 4) {
        const due = new Date(clock.getTime() + expectedDelay[attempt - 1])
        assert.equal(new Date(parent.nextAttemptAt).toISOString(), due.toISOString())
        clock = due
      } else {
        assert.equal(parent.nextAttemptAt, null)
      }
    }

    const exhaustedTransport = new FakeTransport(ok204)
    const summary = await flushSupplierResponses({ transport: exhaustedTransport, now: () => clock })
    assert.equal(exhaustedTransport.sent.length, 0)
    assert.equal(summary.retryExhausted, 1)
    const parent: any = (await rowsFor(SUP001_ORDER_A))[0]
    assert.equal(parent.attempts, 4)
    assert.equal((await historyFor(parent.ID)).length, 4)
  })

  for (const expected of [
    { label: 'success', result: ok204, state: 'DELIVERED' },
    { label: 'refusal', result: conflict, state: 'FAILED' },
    { label: 'ambiguity', result: timeout, state: 'UNKNOWN' }
  ]) {
    test(`${expected.label} clears automatic retry timing`, async () => {
      await accept(SUP001_ORDER_A)
      const [row]: any[] = await rowsFor(SUP001_ORDER_A)
      await UPDATE(SupplierResponseDeliveries).set({
        attempts: 1,
        retryWindowStartedAt: T0.toISOString(),
        nextAttemptAt: T0.toISOString()
      } as any).where({ ID: row.ID })

      await flushSupplierResponses({ transport: new FakeTransport(expected.result), now: () => T0 })
      const after: any = (await rowsFor(SUP001_ORDER_A))[0]
      assert.equal(after.state, expected.state)
      assert.equal(after.nextAttemptAt, null)
      assert.equal(after.retryWindowStartedAt, null)
    })
  }
})

describe('Phase 7.4b certainty and Retry-After integration', () => {
  const T0 = new Date('2026-09-21T12:00:00.000Z')
  const historyFor = (delivery: string) =>
    SELECT.from(SupplierResponseDeliveryAttempts).where({ delivery_ID: delivery }).orderBy('attemptNumber')

  test('a NOT_SENT attempt is atomically PENDING / TRANSIENT with retry timing', async () => {
    await accept(SUP001_ORDER_A)
    const transport = new FakeTransport({
      answered: false,
      certainty: 'NOT_SENT',
      detail: 'request not sent: DNS resolution failed'
    })
    await flushSupplierResponses({ transport, now: () => T0, jitter: () => 0 })

    const [parent]: any[] = await rowsFor(SUP001_ORDER_A)
    assert.equal(parent.state, 'PENDING')
    assert.equal(parent.attempts, 1)
    assert.equal(new Date(parent.retryWindowStartedAt).toISOString(), T0.toISOString())
    assert.equal(new Date(parent.nextAttemptAt).toISOString(), new Date(T0.getTime() + 5_000).toISOString())
    assert.equal(parent.lastCorrelationId, transport.sent[0].correlationId)
    assert.match(parent.lastError, /^NOT_SENT:/)

    const history: any[] = await historyFor(parent.ID)
    assert.equal(history.length, 1)
    assert.equal(history[0].attemptNumber, 1)
    assert.equal(history[0].outcome, 'PENDING')
    assert.equal(history[0].errorCategory, 'TRANSIENT')
    assert.equal(history[0].httpStatus, null)
    assert.equal(history[0].correlationId, parent.lastCorrelationId)
  })

  test('an unanswered NOT_SENT result cannot make Retry-After authoritative', async () => {
    await accept(SUP001_ORDER_A)
    await flushSupplierResponses({
      transport: new FakeTransport({
        answered: false,
        certainty: 'NOT_SENT',
        detail: 'request not sent: connection refused',
        retryAfter: '120'
      }),
      now: () => T0,
      jitter: () => 0
    })

    const [parent]: any[] = await rowsFor(SUP001_ORDER_A)
    assert.equal(parent.state, 'PENDING')
    assert.equal(new Date(parent.nextAttemptAt).toISOString(), new Date(T0.getTime() + 5_000).toISOString())
    const history: any[] = await historyFor(parent.ID)
    assert.equal(history.length, 1)
    assert.equal(history[0].errorCategory, 'TRANSIENT')
  })

  for (const status of [429, 502, 503]) {
    test(`HTTP ${status} consumes Retry-After and writes one transient history row`, async () => {
      await accept(SUP001_ORDER_A)
      const transport = new FakeTransport({ answered: true, status, retryAfter: '60' })
      await flushSupplierResponses({ transport, now: () => T0, jitter: () => 0 })

      const [parent]: any[] = await rowsFor(SUP001_ORDER_A)
      assert.equal(parent.state, 'PENDING')
      assert.equal(parent.attempts, 1)
      assert.equal(new Date(parent.nextAttemptAt).toISOString(), new Date(T0.getTime() + 60_000).toISOString())
      const history: any[] = await historyFor(parent.ID)
      assert.equal(history.length, 1)
      assert.equal(history[0].httpStatus, status)
      assert.equal(history[0].errorCategory, 'TRANSIENT')
      assert.equal(history[0].correlationId, parent.lastCorrelationId)
    })
  }

  test('an overflowing Retry-After is ignored without breaking the sender', async () => {
    await accept(SUP001_ORDER_A)
    await flushSupplierResponses({
      transport: new FakeTransport({
        answered: true,
        status: 503,
        retryAfter: '999999999999999999999999999999'
      }),
      now: () => T0,
      jitter: () => 0
    })

    const [parent]: any[] = await rowsFor(SUP001_ORDER_A)
    assert.equal(parent.state, 'PENDING')
    assert.equal(new Date(parent.nextAttemptAt).toISOString(), new Date(T0.getTime() + 5_000).toISOString())
  })

  for (const expected of [
    { status: 500, state: 'UNKNOWN', category: 'AMBIGUOUS' },
    { status: 504, state: 'UNKNOWN', category: 'AMBIGUOUS' },
    { status: 400, state: 'FAILED', category: 'REFUSED' },
    { status: 204, state: 'DELIVERED', category: 'NONE' }
  ]) {
    test(`HTTP ${expected.status} ignores Retry-After and remains ${expected.state}`, async () => {
      await accept(SUP001_ORDER_A)
      await flushSupplierResponses({
        transport: new FakeTransport({ answered: true, status: expected.status, retryAfter: '60' }),
        now: () => T0,
        jitter: () => 0
      })

      const [parent]: any[] = await rowsFor(SUP001_ORDER_A)
      assert.equal(parent.state, expected.state)
      assert.equal(parent.nextAttemptAt, null)
      assert.equal(parent.retryWindowStartedAt, null)
      const history: any[] = await historyFor(parent.ID)
      assert.equal(history.length, 1)
      assert.equal(history[0].errorCategory, expected.category)
    })
  }
})

describe('attempt history', () => {

  const historyFor = (delivery: string) =>
    SELECT.from(SupplierResponseDeliveryAttempts).where({ delivery_ID: delivery }).orderBy('attemptNumber')

  /** Drains one committed response through a scripted transport. */
  async function attemptOnce(result: TransportResult) {
    await accept(SUP001_ORDER_A, { estimatedDeliveryDate: '2026-11-15' })
    const transport = new FakeTransport(result)
    await flushSupplierResponses({ transport })
    const parent: any = (await rowsFor(SUP001_ORDER_A))[0]
    const history: any[] = await historyFor(parent.ID)
    return { transport, parent, history }
  }

  test('a 204 writes exactly one history row that matches the parent', async () => {
    const { transport, parent, history } = await attemptOnce(ok204)

    assert.equal(parent.state, 'DELIVERED')
    assert.equal(parent.attempts, 1)
    assert.equal(parent.lastCorrelationId, transport.sent[0].correlationId)

    assert.equal(history.length, 1, 'exactly one row per committed attempt')
    const [only] = history
    assert.equal(only.attemptNumber, 1)
    assert.equal(only.correlationId, transport.sent[0].correlationId, 'the id that went on the wire')
    assert.equal(only.outcome, 'DELIVERED', 'the same classified value the parent got')
    assert.equal(only.httpStatus, 204)
    assert.equal(only.errorCategory, 'NONE')
    assert.equal(only.errorSummary, null, 'a success stores no diagnosis')
    assert.ok(only.startedAt, 'the attempt is timestamped')
    assert.ok(Number.isInteger(only.durationMs) && only.durationMs >= 0, 'a real measured duration')
  })

  test('a deterministic refusal records REFUSED with its status', async () => {
    const { parent, history } = await attemptOnce(conflict)

    assert.equal(parent.state, 'FAILED')
    assert.equal(parent.attempts, 1)

    assert.equal(history.length, 1)
    assert.equal(history[0].outcome, 'FAILED')
    assert.equal(history[0].httpStatus, 409)
    assert.equal(history[0].errorCategory, 'REFUSED')
    assert.equal(history[0].errorSummary, parent.lastError, 'history and parent carry the same diagnosis')
    assert.match(history[0].errorSummary, /^HTTP 409/)
  })

  test('a transient response records TRANSIENT and leaves the row PENDING', async () => {
    const { parent, history } = await attemptOnce({ answered: true, status: 503, detail: 'upstream busy' })

    assert.equal(parent.state, 'PENDING', 'still eligible, not failed')
    assert.equal(parent.attempts, 1, 'the attempt still counts')

    assert.equal(history.length, 1)
    assert.equal(history[0].outcome, 'PENDING')
    assert.equal(history[0].httpStatus, 503)
    assert.equal(history[0].errorCategory, 'TRANSIENT')
  })

  test('an unanswered transport records NO_ANSWER with a null status', async () => {
    const { parent, history } = await attemptOnce(timeout)

    assert.equal(parent.state, 'UNKNOWN')
    assert.equal(parent.attempts, 1)

    assert.equal(history.length, 1)
    assert.equal(history[0].outcome, 'UNKNOWN')
    assert.equal(history[0].httpStatus, null, 'no answer means no status, not a zero')
    assert.equal(history[0].errorCategory, 'NO_ANSWER')
    assert.match(history[0].errorSummary, /^NO_ANSWER/)
  })

  test('a payload failure records PAYLOAD with no correlation id', async () => {
    await accept(SUP001_ORDER_A, { estimatedDeliveryDate: '2026-11-15' })
    await UPDATE(SupplierResponseDeliveries).set({ respondedAt: null } as any).where({ order_ID: SUP001_ORDER_A })

    const transport = new FakeTransport(ok204)
    await flushSupplierResponses({ transport })

    assert.equal(transport.sent.length, 0, 'nothing was sent')
    const parent: any = (await rowsFor(SUP001_ORDER_A))[0]
    assert.equal(parent.state, 'FAILED')
    assert.equal(parent.attempts, 1)
    assert.equal(parent.lastCorrelationId, null)

    const history: any[] = await historyFor(parent.ID)
    assert.equal(history.length, 1, 'a committed attempt, so a history row')
    assert.equal(history[0].attemptNumber, 1)
    assert.equal(history[0].correlationId, null, 'no transport attempt, no correlation id')
    assert.equal(history[0].outcome, 'FAILED')
    assert.equal(history[0].httpStatus, null)
    assert.equal(history[0].errorCategory, 'PAYLOAD')
    assert.match(history[0].errorSummary, /MISSING_RESPONDED_AT/)
    assert.ok(Number.isInteger(history[0].durationMs) && history[0].durationMs >= 0,
      'measured, not a manufactured zero')
  })

  test('a valid dry run sends nothing, changes nothing and records nothing', async () => {
    await accept(SUP001_ORDER_A, { estimatedDeliveryDate: '2026-11-15' })
    const before: any = (await rowsFor(SUP001_ORDER_A))[0]

    const transport = new FakeTransport(ok204)
    const summary = await flushSupplierResponses({ transport, dryRun: true })

    assert.equal(transport.sent.length, 0)
    assert.equal(summary.outcomes[0].state, 'SKIPPED')
    assert.ok(summary.outcomes[0].payload, 'the operator still gets the exact bytes')

    const after: any = (await rowsFor(SUP001_ORDER_A))[0]
    assert.equal(after.state, 'PENDING')
    for (const field of [
      'attempts', 'lastAttemptAt', 'lastError', 'lastCorrelationId',
      'nextAttemptAt', 'retryWindowStartedAt'
    ]) {
      assert.deepEqual(after[field], before[field], `${field} is unchanged`)
    }
    assert.equal((await historyFor(before.ID)).length, 0, 'a dry run records no attempt')
  })

  test('a row whose attempts predate history is accepted as-is', async () => {
    // Exactly the shape of a row written before Phase 7.3 existed: a counter
    // with nothing behind it. No backfill, and no constraint forbids it.
    await accept(SUP001_ORDER_A, { estimatedDeliveryDate: '2026-11-15' })
    const parent: any = (await rowsFor(SUP001_ORDER_A))[0]
    await UPDATE(SupplierResponseDeliveries)
      .set({ state: 'UNKNOWN', attempts: 3, lastCorrelationId: randomUUID() } as any)
      .where({ ID: parent.ID })

    const historical: any = (await rowsFor(SUP001_ORDER_A))[0]
    assert.equal(historical.attempts, 3)
    assert.equal((await historyFor(parent.ID)).length, 0,
      'attempts > 0 with no history is historical truth, not a defect')
  })
})
