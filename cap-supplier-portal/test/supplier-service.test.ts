import cds from '@sap/cds'
import assert from 'node:assert/strict'
import { randomUUID } from 'node:crypto'
import type { Server } from 'node:http'
import path from 'node:path'
import { after, before, beforeEach, describe, test } from 'node:test'
import { Orders, SupplierResponseDeliveries } from '#cds-models/pih/portal'

/**
 * Phase 4.4 supplier-service tests.
 *
 * Everything runs over HTTP against the running application, because isolation,
 * status codes and the decision contract only exist at that boundary. Persistence
 * is then read back with CQN to prove what the response claimed.
 *
 * Fixtures are reset before each test, so no test depends on another's leftovers.
 */
const portal = cds.test(path.resolve(__dirname, '..'))

const SUPPLIER = '/rest/supplier/v1'

/** Fixture ids from db/data; SUP001 owns 1 and 2, SUP002 owns 3. */
const SUP001_ORDER_A = '22222222-2222-4222-8222-000000000001'
const SUP001_ORDER_B = '22222222-2222-4222-8222-000000000002'
const SUP002_ORDER_C = '22222222-2222-4222-8222-000000000003'

const asSupplier1 = { auth: { username: 'supplier1', password: 'supplier1' } }
const asSupplier2 = { auth: { username: 'supplier2', password: 'supplier2' } }
const asNoSupplier = { auth: { username: 'nosupplier', password: 'nosupplier' } }

let server: Server | undefined

before(async () => {
  await new Promise<void>(resolve => {
    portal.then(started => {
      server = started.server
      resolve()
    })
  })
})

beforeEach(() => portal.data.reset())

after(() => {
  server?.close()
})

async function get(url: string, config: any) {
  try {
    const response = await portal.GET(`${SUPPLIER}${url}`, config)
    return { status: response.status, data: response.data }
  } catch (error: any) {
    return { status: error.response?.status, data: error.response?.data }
  }
}

async function command(order: string, action: string, body: any, config: any) {
  try {
    const response = await portal.POST(`${SUPPLIER}/Orders/${order}/${action}`, body, config)
    return { status: response.status, data: response.data }
  } catch (error: any) {
    return { status: error.response?.status, data: error.response?.data }
  }
}

const orderRow = (id: string) => SELECT.one.from(Orders).where({ ID: id })
const responsesFor = (id: string) => SELECT.from(SupplierResponseDeliveries).where({ order_ID: id })

/** A refusal must change nothing and must speak the contract's envelope. */
async function expectRefused(
  order: string, action: string, body: any, config: any, status: number, code: string
) {
  const snapshot = await orderRow(order)
  const responses = await responsesFor(order)

  const response = await command(order, action, body, config)

  assert.equal(response.status, status, `expected HTTP ${status}, got ${response.status}`)
  assert.equal(response.data?.error?.code, code)
  assert.ok(response.data?.error?.correlationId, 'the envelope carries a correlationId')

  assert.deepEqual(await orderRow(order), snapshot, 'the order is unchanged')
  assert.equal((await responsesFor(order)).length, responses.length, 'no response was recorded')
  return response
}

describe('supplier identity', () => {

  test('an anonymous caller is refused', async () => {
    const response = await get('/Orders', {})
    assert.equal(response.status, 401)
  })

  test('an authenticated user with no supplier attribute is refused', async () => {
    const response = await get('/Orders', asNoSupplier)
    assert.equal(response.status, 403)
    assert.equal(response.data?.error?.code, 'NO_SUPPLIER_IDENTITY')
  })
})

describe('row-level isolation', () => {

  test('each supplier lists only its own orders', async () => {
    const one = await get('/Orders', asSupplier1)
    assert.equal(one.status, 200)
    assert.deepEqual(
      one.data.map((o: any) => o.externalOrderNumber).sort(),
      ['PO00001001', 'PO00001002']
    )

    const two = await get('/Orders', asSupplier2)
    assert.equal(two.status, 200)
    assert.deepEqual(two.data.map((o: any) => o.externalOrderNumber), ['PO00001003'])
  })

  test('a supplier reads its own order and is refused another supplier by id', async () => {
    const own = await get(`/Orders/${SUP001_ORDER_A}`, asSupplier1)
    assert.equal(own.status, 200)
    assert.equal(own.data.externalOrderNumber, 'PO00001001')

    const foreign = await get(`/Orders/${SUP002_ORDER_C}`, asSupplier1)
    assert.equal(foreign.status, 404, 'knowing the id must not be enough')
    assert.equal(foreign.data?.externalOrderNumber, undefined, 'no field is disclosed')
  })

  test('item navigation is scoped the same way', async () => {
    const own = await get(`/Orders/${SUP001_ORDER_A}/items`, asSupplier1)
    assert.equal(own.status, 200)
    assert.deepEqual(own.data.map((i: any) => i.lineNumber).sort(), [10, 20])

    const foreign = await get(`/Orders/${SUP002_ORDER_C}/items`, asSupplier1)
    assert.equal(foreign.status, 404)
  })

  test('the item collection is scoped, so it cannot be used as a bypass', async () => {
    const one = await get('/OrderItems', asSupplier1)
    assert.equal(one.status, 200)
    assert.equal(one.data.length, 3, 'SUP001 owns three lines across two orders')

    const two = await get('/OrderItems', asSupplier2)
    assert.equal(two.data.length, 1)
    assert.equal(two.data[0].productCode, 'MAT002')
  })

  test('the read model exposes no persistence internals', async () => {
    const order = (await get(`/Orders/${SUP001_ORDER_A}`, asSupplier1)).data

    for (const leaked of [
      'supplier_ID', 'sourceSystem', 'sourceOrderId', 'sourceRevision', 'deliveryId', 'modifiedAt', 'ID'
    ]) {
      assert.equal(order[leaked], undefined, `${leaked} must not be exposed`)
    }
    assert.ok(order.portalOrderId, 'the portal id is exposed under its contract name')

    const item = (await get(`/Orders/${SUP001_ORDER_A}/items`, asSupplier1)).data[0]
    assert.equal(item.order_ID, undefined, 'no foreign key column')
    assert.equal(item.sourceItemId, undefined, 'SAP item identity is not supplier data')
  })

  test('no generic write path exists on the supplier service', async () => {
    try {
      await (portal as any).PATCH(`${SUPPLIER}/Orders/${SUP001_ORDER_A}`, { status: 'ACCEPTED' }, asSupplier1)
      assert.fail('PATCH must not be allowed')
    } catch (error: any) {
      assert.ok([404, 405].includes(error.response?.status), `PATCH was answered with ${error.response?.status}`)
    }

    try {
      await (portal as any).DELETE(`${SUPPLIER}/Orders/${SUP001_ORDER_A}`, asSupplier1)
      assert.fail('DELETE must not be allowed')
    } catch (error: any) {
      assert.ok([404, 405].includes(error.response?.status), `DELETE was answered with ${error.response?.status}`)
    }

    const stored = await orderRow(SUP001_ORDER_A)
    assert.equal(stored!.status, 'RECEIVED', 'status is untouched by any generic write attempt')
  })
})

describe('accept', () => {

  test('accepts a received order, records the decision and a pending response', async () => {
    const responseId = randomUUID()
    const response = await command(
      SUP001_ORDER_A, 'accept',
      { responseId, expectedResponseVersion: 0, estimatedDeliveryDate: '2026-12-01' },
      asSupplier1
    )

    assert.equal(response.status, 200)
    assert.deepEqual(Object.keys(response.data).sort(), [
      'estimatedDeliveryDate', 'externalOrderNumber', 'portalOrderId', 'rejectionReason',
      'respondedAt', 'responseDeliveryStatus', 'responseVersion', 'status'
    ])
    assert.equal(response.data.status, 'ACCEPTED')
    assert.equal(response.data.responseVersion, 1)
    assert.equal(response.data.estimatedDeliveryDate, '2026-12-01')
    assert.equal(response.data.rejectionReason, null)
    assert.equal(
      response.data.responseDeliveryStatus, 'PENDING',
      'accepting never claims SAP has been updated'
    )

    const stored = await orderRow(SUP001_ORDER_A)
    assert.equal(stored!.status, 'ACCEPTED')
    assert.equal(stored!.responseVersion, 1)
    assert.equal(stored!.estimatedDeliveryDate, '2026-12-01')
    assert.equal(stored!.rejectionReason, null)

    const responses = await responsesFor(SUP001_ORDER_A)
    assert.equal(responses.length, 1, 'the pending outbound response exists')
    assert.equal(responses[0].responseId, responseId)
    assert.equal(responses[0].version, 1)
    assert.equal(responses[0].decision, 'ACCEPTED')
    assert.equal(responses[0].state, 'PENDING')
    assert.ok(responses[0].respondedAt)
  })

  test('accepts without a date, because an omitted date means unknown', async () => {
    const response = await command(
      SUP001_ORDER_A, 'accept', { responseId: randomUUID(), expectedResponseVersion: 0 }, asSupplier1
    )

    assert.equal(response.status, 200)
    assert.equal(response.data.status, 'ACCEPTED')
    assert.equal(response.data.estimatedDeliveryDate, null)
  })

  test('an exact replay returns the original decision and records nothing new', async () => {
    const body = { responseId: randomUUID(), expectedResponseVersion: 0, estimatedDeliveryDate: '2026-12-01' }

    const first = await command(SUP001_ORDER_A, 'accept', body, asSupplier1)
    assert.equal(first.status, 200)

    // The version precondition is now stale, and the replay must still succeed.
    const replay = await command(SUP001_ORDER_A, 'accept', body, asSupplier1)

    assert.equal(replay.status, 200)
    assert.deepEqual(replay.data, first.data)
    assert.equal((await responsesFor(SUP001_ORDER_A)).length, 1)
    assert.equal((await orderRow(SUP001_ORDER_A))!.responseVersion, 1)
  })

  test('the same responseId with different content is a conflict', async () => {
    const responseId = randomUUID()
    await command(
      SUP001_ORDER_A, 'accept',
      { responseId, expectedResponseVersion: 0, estimatedDeliveryDate: '2026-12-01' },
      asSupplier1
    )

    await expectRefused(
      SUP001_ORDER_A, 'accept',
      { responseId, expectedResponseVersion: 1, estimatedDeliveryDate: '2026-12-09' },
      asSupplier1, 409, 'RESPONSE_PAYLOAD_CONFLICT'
    )
  })

  test('another supplier cannot accept an order it does not own', async () => {
    await expectRefused(
      SUP002_ORDER_C, 'accept', { responseId: randomUUID(), expectedResponseVersion: 0 },
      asSupplier1, 404, 'ORDER_NOT_FOUND'
    )
  })

  test('an already decided order cannot be accepted again', async () => {
    await command(
      SUP001_ORDER_A, 'accept', { responseId: randomUUID(), expectedResponseVersion: 0 }, asSupplier1
    )

    await expectRefused(
      SUP001_ORDER_A, 'accept', { responseId: randomUUID(), expectedResponseVersion: 1 },
      asSupplier1, 409, 'INVALID_STATE_FOR_DECISION'
    )
  })

  test('a stale version precondition is refused', async () => {
    await command(
      SUP001_ORDER_A, 'accept', { responseId: randomUUID(), expectedResponseVersion: 0 }, asSupplier1
    )

    await expectRefused(
      SUP001_ORDER_A, 'updateEstimatedDeliveryDate',
      { responseId: randomUUID(), expectedResponseVersion: 0, estimatedDeliveryDate: '2026-12-20' },
      asSupplier1, 409, 'STALE_RESPONSE_VERSION'
    )
  })

  test('a malformed command payload is refused', async () => {
    await expectRefused(
      SUP001_ORDER_A, 'accept', { expectedResponseVersion: 0 },
      asSupplier1, 400, 'MISSING_RESPONSE_ID'
    )
    await expectRefused(
      SUP001_ORDER_A, 'accept', { responseId: 'not-a-uuid', expectedResponseVersion: 0 },
      asSupplier1, 400, 'MISSING_RESPONSE_ID'
    )
    await expectRefused(
      SUP001_ORDER_A, 'accept', { responseId: randomUUID() },
      asSupplier1, 400, 'MISSING_VERSION_PRECONDITION'
    )
  })

  test('a delivery date before today is refused', async () => {
    await expectRefused(
      SUP001_ORDER_A, 'accept',
      { responseId: randomUUID(), expectedResponseVersion: 0, estimatedDeliveryDate: '2020-01-01' },
      asSupplier1, 400, 'DELIVERY_DATE_IN_PAST'
    )
  })
})

describe('reject', () => {

  test('rejects a received order with a reason and records a pending response', async () => {
    const responseId = randomUUID()
    const response = await command(
      SUP002_ORDER_C, 'reject',
      { responseId, expectedResponseVersion: 0, reason: 'Out of stock until Q1' },
      asSupplier2
    )

    assert.equal(response.status, 200)
    assert.equal(response.data.status, 'REJECTED')
    assert.equal(response.data.responseVersion, 1)
    assert.equal(response.data.rejectionReason, 'Out of stock until Q1')
    assert.equal(response.data.estimatedDeliveryDate, null, 'rejection forbids a delivery date')
    assert.equal(response.data.responseDeliveryStatus, 'PENDING')

    const stored = await orderRow(SUP002_ORDER_C)
    assert.equal(stored!.status, 'REJECTED')
    assert.equal(stored!.rejectionReason, 'Out of stock until Q1')
    assert.equal(stored!.estimatedDeliveryDate, null)
    assert.equal(stored!.responseVersion, 1)

    const responses = await responsesFor(SUP002_ORDER_C)
    assert.equal(responses.length, 1)
    assert.equal(responses[0].decision, 'REJECTED')
    assert.equal(responses[0].reason, 'Out of stock until Q1')
    assert.equal(responses[0].estimatedDeliveryDate, null)
    assert.equal(responses[0].state, 'PENDING')
  })

  test('a rejection without a reason is refused', async () => {
    await expectRefused(
      SUP001_ORDER_A, 'reject', { responseId: randomUUID(), expectedResponseVersion: 0 },
      asSupplier1, 400, 'MISSING_REJECTION_REASON'
    )
    await expectRefused(
      SUP001_ORDER_A, 'reject', { responseId: randomUUID(), expectedResponseVersion: 0, reason: '   ' },
      asSupplier1, 400, 'MISSING_REJECTION_REASON'
    )
  })

  test('another supplier cannot reject an order it does not own', async () => {
    await expectRefused(
      SUP002_ORDER_C, 'reject', { responseId: randomUUID(), expectedResponseVersion: 0, reason: 'no' },
      asSupplier1, 404, 'ORDER_NOT_FOUND'
    )
  })

  test('an already rejected order cannot be rejected again', async () => {
    await command(
      SUP002_ORDER_C, 'reject',
      { responseId: randomUUID(), expectedResponseVersion: 0, reason: 'first' },
      asSupplier2
    )

    await expectRefused(
      SUP002_ORDER_C, 'reject',
      { responseId: randomUUID(), expectedResponseVersion: 1, reason: 'second' },
      asSupplier2, 409, 'INVALID_STATE_FOR_DECISION'
    )
  })
})

describe('updateEstimatedDeliveryDate', () => {

  async function acceptOrderA() {
    const response = await command(
      SUP001_ORDER_A, 'accept',
      { responseId: randomUUID(), expectedResponseVersion: 0, estimatedDeliveryDate: '2026-12-01' },
      asSupplier1
    )
    assert.equal(response.status, 200)
  }

  test('updates the date on an accepted order and increments the version', async () => {
    await acceptOrderA()

    const response = await command(
      SUP001_ORDER_A, 'updateEstimatedDeliveryDate',
      { responseId: randomUUID(), expectedResponseVersion: 1, estimatedDeliveryDate: '2026-12-20' },
      asSupplier1
    )

    assert.equal(response.status, 200)
    assert.equal(response.data.status, 'ACCEPTED', 'a date update keeps the decision')
    assert.equal(response.data.responseVersion, 2)
    assert.equal(response.data.estimatedDeliveryDate, '2026-12-20')

    const stored = await orderRow(SUP001_ORDER_A)
    assert.equal(stored!.status, 'ACCEPTED')
    assert.equal(stored!.estimatedDeliveryDate, '2026-12-20')
    assert.equal(stored!.responseVersion, 2)

    const responses = await responsesFor(SUP001_ORDER_A)
    assert.equal(responses.length, 2, 'each response is its own record')
    assert.deepEqual(responses.map(r => r.version).sort(), [1, 2])
  })

  test('a date cannot be updated on an order that was never accepted', async () => {
    await expectRefused(
      SUP001_ORDER_A, 'updateEstimatedDeliveryDate',
      { responseId: randomUUID(), expectedResponseVersion: 0, estimatedDeliveryDate: '2026-12-20' },
      asSupplier1, 409, 'INVALID_STATE_FOR_DATE_UPDATE'
    )
  })

  test('a missing or past date is refused', async () => {
    await acceptOrderA()

    await expectRefused(
      SUP001_ORDER_A, 'updateEstimatedDeliveryDate',
      { responseId: randomUUID(), expectedResponseVersion: 1 },
      asSupplier1, 400, 'INVALID_DELIVERY_DATE'
    )
    await expectRefused(
      SUP001_ORDER_A, 'updateEstimatedDeliveryDate',
      { responseId: randomUUID(), expectedResponseVersion: 1, estimatedDeliveryDate: '2020-01-01' },
      asSupplier1, 400, 'DELIVERY_DATE_IN_PAST'
    )
  })

  test('another supplier cannot update a date it does not own', async () => {
    await expectRefused(
      SUP002_ORDER_C, 'updateEstimatedDeliveryDate',
      { responseId: randomUUID(), expectedResponseVersion: 0, estimatedDeliveryDate: '2026-12-20' },
      asSupplier1, 404, 'ORDER_NOT_FOUND'
    )
  })
})

describe('the decision and its pending response are atomic', () => {

  /**
   * Forces the *second* write to fail while the first has already run.
   *
   * A response row for (order, version 1) is planted directly, taking the slot
   * the next decision will need. The handler then updates the order to ACCEPTED
   * and tries to insert its own response at version 1, which violates the
   * documented `responses(order, version)` uniqueness rule. Nothing here is
   * simulated: the constraint is the one the domain model specifies, and the
   * failure happens after the order row has already been written in the same
   * transaction.
   */
  test('a failure in the response write rolls back the decision write', async () => {
    await INSERT.into(SupplierResponseDeliveries).entries({
      ID: cds.utils.uuid(),
      responseId: randomUUID(),
      order_ID: SUP001_ORDER_A,
      version: 1,
      decision: 'ACCEPTED',
      respondedAt: new Date().toISOString(),
      state: 'PENDING'
    } as any)

    const before = await orderRow(SUP001_ORDER_A)
    assert.equal(before!.status, 'RECEIVED')

    const response = await command(
      SUP001_ORDER_A, 'accept',
      { responseId: randomUUID(), expectedResponseVersion: 0, estimatedDeliveryDate: '2026-12-01' },
      asSupplier1
    )

    assert.ok(response.status >= 400, `the command must fail, got ${response.status}`)

    const after = await orderRow(SUP001_ORDER_A)
    assert.equal(after!.status, 'RECEIVED', 'the decision write was rolled back')
    assert.equal(after!.responseVersion, 0, 'the version was rolled back')
    assert.equal(after!.estimatedDeliveryDate, null, 'the date was rolled back')

    assert.equal(
      (await responsesFor(SUP001_ORDER_A)).length, 1,
      'only the planted row remains; the handler added nothing'
    )
  })
})
