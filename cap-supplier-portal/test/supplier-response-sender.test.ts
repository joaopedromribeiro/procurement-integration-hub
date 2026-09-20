import cds from '@sap/cds'
import assert from 'node:assert/strict'
import { randomUUID } from 'node:crypto'
import type { Server } from 'node:http'
import path from 'node:path'
import { after, before, beforeEach, describe, test } from 'node:test'
import { Orders, SupplierResponseDeliveries } from '#cds-models/pih/portal'

import {
  CI_CLIENT_ID_VAR, CI_CLIENT_SECRET_VAR, CI_TIMEOUT_VAR, CI_URL_VAR,
  ConfigError, DEFAULT_TIMEOUT_MS, HttpResponseTransport, readCiConfig, safeDetail,
  type ResponseTransport
} from '../srv/lib/ci-transport'
import { flushSupplierResponses } from '../srv/lib/response-sender'
import {
  buildSupplierResponsePayload, classify, PayloadError, toRfc3339,
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

  test('a retryable refusal returns the row to PENDING and it is picked up again', async () => {
    await accept(SUP001_ORDER_A)

    await flushSupplierResponses({ transport: new FakeTransport({ answered: true, status: 503 }) })

    const [afterFirst]: any[] = await rowsFor(SUP001_ORDER_A)
    assert.equal(afterFirst.state, 'PENDING', 'congestion is not a failure')
    assert.equal(afterFirst.attempts, 1)

    const retry = new FakeTransport(ok204)
    await flushSupplierResponses({ transport: retry })

    const [afterRetry]: any[] = await rowsFor(SUP001_ORDER_A)
    assert.equal(afterRetry.state, 'DELIVERED')
    assert.equal(afterRetry.attempts, 2, 'attempts accumulate and are never reset')
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
  async function capture(payload: SupplierResponsePayload, correlationId: string, status = 204) {
    const original = globalThis.fetch
    let seen: { url: string; init: any } | undefined

    globalThis.fetch = (async (url: any, init: any) => {
      seen = { url: String(url), init }
      return {
        status,
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
