import cds from '@sap/cds'
import assert from 'node:assert/strict'
import { randomUUID } from 'node:crypto'
import type { Server } from 'node:http'
import path from 'node:path'
import { after, before, describe, test } from 'node:test'
import { DeliveryReceipts, OrderItems, Orders } from '#cds-models/pih/portal'
import { isFailure, normalizeDelivery } from '../srv/lib/ingestion'

/**
 * Phase 4.3 ingestion tests.
 *
 * Every case goes through the running CAP application over HTTP, because the
 * things being verified — status codes, the receipt body, the error envelope,
 * replay semantics — only exist at that boundary. Persistence is then inspected
 * with CQN to prove what the HTTP response claimed.
 */
const portal = cds.test(path.resolve(__dirname, '..'))

const ENDPOINT = '/rest/integration/v1/Orders'

let server: Server | undefined

before(async () => {
  await new Promise<void>(resolve => {
    portal.then(started => {
      server = started.server
      resolve()
    })
  })
})

after(() => {
  server?.close()
})

/** A valid delivery with fresh identities, shaped exactly as API_CONTRACTS.md. */
function delivery(overrides: Record<string, any> = {}) {
  return {
    schemaVersion: '1.0',
    deliveryId: randomUUID(),
    source: {
      system: 'PIH_ABAP_DEV',
      orderId: randomUUID(),
      orderNumber: 'PO00002001',
      revision: 1
    },
    supplierCode: 'SUP001',
    amount: { currency: 'EUR', value: '1500.00' },
    lines: [{
      sourceItemId: randomUUID(),
      lineNumber: 10,
      product: { code: 'MAT001', description: 'Laptop' },
      orderedQuantity: { value: '2.000', unit: 'PCE' },
      unitPrice: { currency: 'EUR', value: '750.0000' },
      lineAmount: '1500.00'
    }],
    ...overrides
  }
}

/** POST without throwing, so a rejected request can be asserted on. */
async function post(body: any, config?: any) {
  try {
    const response = await portal.POST(ENDPOINT, body, config)
    return { status: response.status, data: response.data }
  } catch (error: any) {
    return { status: error.response?.status, data: error.response?.data }
  }
}

async function counts() {
  return {
    orders: (await SELECT.from(Orders)).length,
    items: (await SELECT.from(OrderItems)).length,
    receipts: (await SELECT.from(DeliveryReceipts)).length
  }
}

/** Asserts a request changed nothing, which is the point of every refusal. */
async function expectRefused(body: any, status: number, code: string) {
  const before = await counts()
  const response = await post(body)

  assert.equal(response.status, status, `expected HTTP ${status}, got ${response.status}`)
  assert.equal(response.data?.error?.code, code)
  assert.ok(response.data?.error?.message, 'the envelope carries a message')
  assert.ok(response.data?.error?.correlationId, 'the envelope carries a correlationId')
  assert.equal(response.data?.error?.retryable, false)

  assert.deepEqual(await counts(), before, 'a refused delivery must persist nothing')
  return response
}

describe('a valid delivery', () => {

  test('is accepted with 201 and the contract receipt, and is fully persisted', async () => {
    const body = delivery({
      amount: { currency: 'EUR', value: '1861.50' },
      lines: [
        {
          sourceItemId: randomUUID(), lineNumber: 10,
          product: { code: 'MAT001', description: 'Laptop' },
          orderedQuantity: { value: '2.000', unit: 'PCE' },
          unitPrice: { currency: 'EUR', value: '750.0000' },
          lineAmount: '1500.00'
        },
        {
          sourceItemId: randomUUID(), lineNumber: 20,
          product: { code: 'MAT002', description: 'Docking station' },
          orderedQuantity: { value: '3.000', unit: 'PCE' },
          unitPrice: { currency: 'EUR', value: '120.5000' },
          lineAmount: '361.50'
        }
      ]
    })

    const response = await post(body)

    assert.equal(response.status, 201)
    assert.deepEqual(Object.keys(response.data).sort(), [
      'deliveryId', 'portalOrderId', 'receivedAt', 'sourceOrderId', 'status'
    ])
    assert.equal(response.data.deliveryId, body.deliveryId)
    assert.equal(response.data.sourceOrderId, body.source.orderId)
    assert.equal(response.data.status, 'RECEIVED')
    assert.ok(response.data.portalOrderId)
    assert.ok(response.data.receivedAt)

    const stored: any = await SELECT.one
      .from(Orders, (o: any) => {
        o('*'), o.supplier((s: any) => s.supplierCode), o.items((i: any) => i('*'))
      })
      .where({ ID: response.data.portalOrderId })

    assert.ok(stored, 'the receipt points at a real order')
    assert.equal(stored.supplier.supplierCode, 'SUP001', 'supplierCode resolved to the portal supplier')
    assert.equal(stored.sourceSystem, 'PIH_ABAP_DEV')
    assert.equal(stored.sourceOrderId, body.source.orderId)
    assert.equal(stored.sourceRevision, 1)
    assert.equal(stored.externalOrderNumber, 'PO00002001')
    assert.equal(stored.deliveryId, body.deliveryId)
    assert.equal(stored.currency, 'EUR')
    assert.equal(Number(stored.totalAmount), 1861.5)

    // Server-owned, and never taken from the payload.
    assert.equal(stored.status, 'RECEIVED')
    assert.equal(stored.responseVersion, 0)
    assert.ok(stored.receivedAt)
    assert.ok(stored.modifiedAt)
    assert.equal(stored.estimatedDeliveryDate, null)
    assert.equal(stored.rejectionReason, null)

    assert.equal(stored.items.length, 2)
    const first = stored.items.find((i: any) => i.lineNumber === 10)
    assert.equal(first.productCode, 'MAT001')
    assert.equal(first.description, 'Laptop')
    assert.equal(first.uom, 'PCE')
    assert.equal(Number(first.quantity), 2)
    assert.equal(Number(first.unitPrice), 750)
    assert.equal(Number(first.lineAmount), 1500)
  })
})

describe('delivery idempotency', () => {

  test('an exact replay returns the original receipt with 200 and creates nothing', async () => {
    const body = delivery()

    const created = await post(body)
    assert.equal(created.status, 201)

    const afterCreate = await counts()
    const replayed = await post(body)

    assert.equal(replayed.status, 200, 'a replay is not a creation')
    assert.deepEqual(replayed.data, created.data, 'the original receipt is returned, not a new one')
    assert.deepEqual(await counts(), afterCreate, 'no second order, no duplicated items, no second receipt')
  })

  test('a byte-different but business-identical replay is still a replay', async () => {
    const body = delivery()
    const created = await post(body)
    assert.equal(created.status, 201)

    // Same facts: reordered members, and decimals written at a different scale.
    const equivalent = {
      deliveryId: body.deliveryId,
      schemaVersion: body.schemaVersion,
      supplierCode: body.supplierCode,
      amount: { value: '1500.0', currency: 'EUR' },
      source: {
        orderId: body.source.orderId,
        system: body.source.system,
        revision: body.source.revision,
        orderNumber: body.source.orderNumber
      },
      lines: [{
        lineNumber: 10,
        sourceItemId: body.lines[0].sourceItemId,
        lineAmount: '1500.0',
        product: { description: 'Laptop', code: 'MAT001' },
        unitPrice: { value: '750.00', currency: 'EUR' },
        orderedQuantity: { unit: 'PCE', value: '2' }
      }]
    }

    const replayed = await post(equivalent)
    assert.equal(replayed.status, 200)
    assert.deepEqual(replayed.data, created.data)
  })

  test('the same deliveryId with changed content is 409 and leaves the stored order alone', async () => {
    const body = delivery()
    const created = await post(body)
    assert.equal(created.status, 201)

    const conflicting = delivery({
      deliveryId: body.deliveryId,
      source: body.source,
      amount: { currency: 'EUR', value: '2250.00' },
      lines: [{ ...body.lines[0], orderedQuantity: { value: '3.000', unit: 'PCE' }, lineAmount: '2250.00' }]
    })

    await expectRefused(conflicting, 409, 'DELIVERY_PAYLOAD_CONFLICT')

    const stored: any = await SELECT.one.from(Orders).where({ ID: created.data.portalOrderId })
    assert.equal(Number(stored.totalAmount), 1500, 'the original order is untouched')
  })

  test('two concurrent deliveries with one deliveryId produce exactly one order', async () => {
    const body = delivery()
    const before = await counts()

    const [a, b] = await Promise.all([post(body), post(body)])

    const statuses = [a.status, b.status].sort()
    assert.ok(
      statuses.every(s => s === 200 || s === 201),
      `both callers must be answered, got ${statuses.join(' and ')}`
    )

    const after = await counts()
    assert.equal(after.orders, before.orders + 1, 'exactly one order')
    assert.equal(after.items, before.items + 1, 'exactly one line')
    assert.equal(after.receipts, before.receipts + 1, 'exactly one receipt')

    const receipts = [a.data, b.data].filter(Boolean)
    assert.equal(
      new Set(receipts.map((r: any) => r.portalOrderId)).size, 1,
      'both callers resolve the same portal order'
    )
  })

  test('the delivery uniqueness rule is enforced by the database, not only by the handler', async () => {
    const body = delivery()
    const created = await post(body)
    assert.equal(created.status, 201)

    const stored: any = await SELECT.one
      .from(DeliveryReceipts)
      .where({ deliveryId: body.deliveryId })

    await assert.rejects(
      async () => { await INSERT.into(DeliveryReceipts).entries({
        ID: cds.utils.uuid(),
        sourceSystem: stored.sourceSystem,
        deliveryId: stored.deliveryId,
        requestHash: stored.requestHash,
        sourceOrderId: stored.sourceOrderId,
        sourceRevision: stored.sourceRevision,
        order_ID: stored.order_ID
      } as any) },
      'a second receipt for the same source system and deliveryId must be refused'
    )
  })
})

describe('source-order uniqueness is a different rule from delivery uniqueness', () => {

  test('a new deliveryId carrying an already ingested source order and revision is 409', async () => {
    const body = delivery()
    const created = await post(body)
    assert.equal(created.status, 201)

    const resent = delivery({ source: body.source })
    const response = await expectRefused(resent, 409, 'SOURCE_ORDER_ALREADY_INGESTED')

    assert.match(response.data.error.message, new RegExp(created.data.portalOrderId))
    assert.match(response.data.error.message, new RegExp(body.deliveryId))
  })

  test('the same source order at a new revision is a different order and is accepted', async () => {
    const body = delivery()
    assert.equal((await post(body)).status, 201)

    const revised = delivery({ source: { ...body.source, revision: 2 } })
    const response = await post(revised)

    assert.equal(response.status, 201)
    assert.notEqual(response.data.portalOrderId, undefined)
  })
})

describe('integration-contract validation', () => {

  test('an unknown supplier is refused and nothing is persisted', async () => {
    await expectRefused(delivery({ supplierCode: 'SUP999' }), 400, 'UNKNOWN_SUPPLIER')
  })

  test('a delivery with no lines is refused', async () => {
    await expectRefused(
      delivery({ amount: { currency: 'EUR', value: '0.00' }, lines: [] }),
      400, 'NO_LINES'
    )
  })

  test('a duplicated line number within one delivery is refused', async () => {
    const line = delivery().lines[0]
    await expectRefused(
      delivery({
        amount: { currency: 'EUR', value: '3000.00' },
        lines: [line, { ...line, sourceItemId: randomUUID() }]
      }),
      400, 'DUPLICATE_LINE_NUMBER'
    )
  })

  test('an unsupported currency is refused', async () => {
    await expectRefused(
      delivery({
        amount: { currency: 'USD', value: '1500.00' },
        lines: [{ ...delivery().lines[0], unitPrice: { currency: 'USD', value: '750.0000' } }]
      }),
      400, 'UNSUPPORTED_CURRENCY'
    )
  })

  test('an unmapped unit is refused rather than guessed', async () => {
    const line = delivery().lines[0]
    await expectRefused(
      delivery({ lines: [{ ...line, orderedQuantity: { value: '2.000', unit: 'EA' } }] }),
      400, 'UNSUPPORTED_UNIT'
    )
  })

  test('a line currency differing from the header currency is refused', async () => {
    const line = delivery().lines[0]
    await expectRefused(
      delivery({ lines: [{ ...line, unitPrice: { currency: 'USD', value: '750.0000' } }] }),
      400, 'LINE_CURRENCY_MISMATCH'
    )
  })

  test('a header total that does not equal the sum of the lines is refused', async () => {
    await expectRefused(
      delivery({ amount: { currency: 'EUR', value: '1400.00' } }),
      400, 'TOTAL_AMOUNT_MISMATCH'
    )
  })

  test('a line amount that is not quantity times price is refused', async () => {
    const line = delivery().lines[0]
    await expectRefused(
      delivery({
        amount: { currency: 'EUR', value: '1499.00' },
        lines: [{ ...line, lineAmount: '1499.00' }]
      }),
      400, 'LINE_AMOUNT_MISMATCH'
    )
  })

  test('a non-positive quantity is refused', async () => {
    const line = delivery().lines[0]
    await expectRefused(
      delivery({
        amount: { currency: 'EUR', value: '0.00' },
        lines: [{ ...line, orderedQuantity: { value: '0.000', unit: 'PCE' }, lineAmount: '0.00' }]
      }),
      400, 'INVALID_QUANTITY'
    )
  })

  test('a negative price is refused, while a zero price is valid', async () => {
    const line = delivery().lines[0]

    await expectRefused(
      delivery({
        amount: { currency: 'EUR', value: '-1500.00' },
        lines: [{ ...line, unitPrice: { currency: 'EUR', value: '-750.0000' }, lineAmount: '-1500.00' }]
      }),
      400, 'INVALID_PRICE'
    )

    const free = await post(delivery({
      amount: { currency: 'EUR', value: '0.00' },
      lines: [{ ...line, unitPrice: { currency: 'EUR', value: '0.0000' }, lineAmount: '0.00' }]
    }))
    assert.equal(free.status, 201, 'zero price is explicitly valid in the contract')
  })

  test('scientific notation is refused, because decimals are transported as plain strings', async () => {
    await expectRefused(
      delivery({ amount: { currency: 'EUR', value: '1.5e3' } }),
      400, 'INVALID_DECIMAL'
    )
  })

  test('an unsupported schema major version is refused', async () => {
    await expectRefused(delivery({ schemaVersion: '2.0' }), 400, 'SCHEMA_VERSION_UNSUPPORTED')
  })

  test('a missing or malformed source identity is refused', async () => {
    await expectRefused(
      delivery({ source: { system: 'PIH_ABAP_DEV', orderId: randomUUID(), orderNumber: 'PO1', revision: 0 } }),
      400, 'INVALID_SOURCE_IDENTITY'
    )
  })

  test('a missing deliveryId is refused', async () => {
    const body: any = delivery()
    delete body.deliveryId
    await expectRefused(body, 400, 'MISSING_DELIVERY_ID')
  })

  test('a line without product.code is refused', async () => {
    const line: any = { ...delivery().lines[0] }
    delete line.product.code

    await expectRefused(
      delivery({ lines: [{ ...line, product: { description: 'Laptop' } }] }),
      400, 'MISSING_PRODUCT_CODE'
    )
  })

  /**
   * A body that is not an order object is refused, but not by this service.
   *
   * CAP's own type assertion rejects a JSON scalar before any handler runs, so
   * the response carries CAP's envelope rather than the contract envelope. What
   * matters at the boundary is still guaranteed: 400, and nothing persisted.
   */
  test('a request body that is not an order object is refused before the handler', async () => {
    const before = await counts()

    // Sent as a raw JSON scalar, so the adapter parses it and then refuses it.
    const response = await post('"just a string"' as any, { headers: { 'Content-Type': 'application/json' } })

    assert.equal(response.status, 400)
    assert.equal(response.data?.error?.code, 'ASSERT_DATA_TYPE')
    assert.notEqual(
      response.data?.error?.code, 'INVALID_PAYLOAD',
      'the contract guard is not what refuses this; CAP stops it first'
    )
    assert.deepEqual(await counts(), before, 'nothing is persisted')
  })

  /**
   * `INVALID_PAYLOAD` is unreachable over HTTP and is therefore covered directly.
   *
   * No JSON body produces it: scalars are stopped by CAP's type assertion above,
   * and `null`, `[]` and `{}` all arrive at the handler as an empty object, which
   * passes the object check and falls through to SCHEMA_VERSION_UNSUPPORTED. The
   * guard still protects `normalizeDelivery` from a non-HTTP caller, so it is
   * asserted where it can actually fire.
   */
  test('the INVALID_PAYLOAD guard rejects a non-object payload', () => {
    for (const payload of [null, undefined, 'a string', 42, true]) {
      const result = normalizeDelivery(payload)
      assert.ok(isFailure(result), `${String(payload)} must not normalize`)
      assert.equal(result.code, 'INVALID_PAYLOAD')
    }
  })
})

describe('the service boundary', () => {

  test('the integration service is insert-only', async () => {
    await assert.rejects(() => portal.GET(ENDPOINT), (error: any) => {
      assert.equal(error.response?.status, 405)
      return true
    })
  })

  /**
   * Phase 4.4 added the supplier surface, so this no longer asserts its absence.
   * What must stay true is that it is a *separate, authenticated* service: the
   * integration client's anonymous access does not reach it, and no persistence
   * entity is served anywhere.
   */
  test('the supplier surface is a separate, authenticated service', async () => {
    for (const route of ['/rest/supplier/v1/Orders', '/rest/supplier/v1/OrderItems']) {
      await assert.rejects(() => portal.GET(route), (error: any) => {
        assert.equal(error.response?.status, 401, `${route} must require authentication`)
        return true
      })
    }

    await assert.rejects(() => portal.GET('/odata/v4/Orders'), (error: any) => {
      assert.equal(error.response?.status, 404, 'no generic OData surface over persistence')
      return true
    })
  })

  test('persistence entities are not exposed through any service', () => {
    const model = cds.model
    assert.ok(model)

    for (const service of ['IntegrationService', 'HealthService']) {
      for (const name of Object.keys(model.definitions)) {
        if (!name.startsWith(`${service}.`)) continue
        const definition: any = model.definitions[name]
        if (definition.kind !== 'entity') continue
        assert.equal(
          definition.projection ?? definition.query, undefined,
          `${name} must not be a projection on persistence`
        )
      }
    }
  })
})
