import cds from '@sap/cds'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import type { Server } from 'node:http'
import path from 'node:path'
import { after, before, describe, test } from 'node:test'

/**
 * Phase 4.5 UI tests.
 *
 * Two kinds, both lightweight and neither a browser automation framework.
 *
 * The presentation logic lives in `app/lib/order-view.mjs` as pure functions, so
 * the same module the browser loads is imported here and tested directly. The
 * rest is asserted over HTTP against the running application — that the assets
 * are served, that the pagination contract behaves, and that the shipped script
 * talks to nothing but `SupplierService`.
 */
const portal = cds.test(path.resolve(__dirname, '..'))

const APP = path.resolve(__dirname, '..', 'app')
const asSupplier1 = { auth: { username: 'supplier1', password: 'supplier1' } }

let server: Server | undefined
let view: any

before(async () => {
  await new Promise<void>(resolve => {
    portal.then(started => {
      server = started.server
      resolve()
    })
  })
  view = await import('../app/lib/order-view.mjs')
})

after(() => {
  server?.close()
})

async function get(url: string, config: any = {}) {
  try {
    const response = await portal.GET(url, config)
    return { status: response.status, data: response.data }
  } catch (error: any) {
    return { status: error.response?.status, data: error.response?.data }
  }
}

describe('the UI is served as static assets', () => {

  test('every page asset is reachable', async () => {
    for (const asset of ['/index.html', '/styles.css', '/supplier-ui.mjs', '/lib/order-view.mjs']) {
      const response = await get(asset)
      assert.equal(response.status, 200, `${asset} is not served`)
    }
  })

  test('the page needs no sign-in to load, but the service does', async () => {
    assert.equal((await get('/index.html')).status, 200)
    assert.equal(
      (await get('/rest/supplier/v1/Orders')).status, 401,
      'the data behind the page is still protected'
    )
  })
})

describe('the browser code talks only to SupplierService', () => {

  const script = () => readFileSync(path.join(APP, 'supplier-ui.mjs'), 'utf8')

  test('every request path is under the supplier service', () => {
    const source = script()

    // The one place a URL is built, plus the paths passed to it.
    assert.match(source, /const SERVICE = '\/rest\/supplier\/v1'/)
    assert.equal(
      source.includes('/rest/integration/v1'), false,
      'the supplier UI must not touch the integration service'
    )
    assert.equal(source.includes('/odata/'), false, 'no generic OData surface is used')
  })

  test('no generic write verb is used anywhere', () => {
    const source = script()

    for (const verb of ['PATCH', 'PUT', 'DELETE']) {
      assert.equal(
        source.includes(`'${verb}'`), false,
        `${verb} must not appear; status changes go through the bound actions`
      )
    }
    assert.match(source, /method: 'POST'/, 'decisions are POSTed to the bound actions')
  })

  test('the browser never sends a supplier code', () => {
    const source = script()
    const logic = readFileSync(path.join(APP, 'lib', 'order-view.mjs'), 'utf8')

    // supplierCode may be read from a response, never written into a request.
    for (const file of [source, logic]) {
      assert.equal(
        /supplierCode\s*[:=]/.test(file), false,
        'supplier identity is derived by the backend, never submitted'
      )
    }
  })
})

describe('lifecycle controls follow the order status', () => {

  test('a received order can be accepted or rejected, but not re-dated', () => {
    assert.deepEqual(view.actionsFor({ status: 'RECEIVED' }), {
      canAccept: true, canReject: true, canUpdateDate: false
    })
  })

  test('an accepted order can only have its date revised', () => {
    assert.deepEqual(view.actionsFor({ status: 'ACCEPTED' }), {
      canAccept: false, canReject: false, canUpdateDate: true
    })
  })

  test('a rejected order offers nothing, and neither does an unknown status', () => {
    for (const status of ['REJECTED', undefined]) {
      assert.deepEqual(view.actionsFor({ status }), {
        canAccept: false, canReject: false, canUpdateDate: false
      })
    }
  })
})

describe('command payloads', () => {

  const order = { portalOrderId: 'abc', responseVersion: 3, status: 'RECEIVED' }

  test('accept carries the loaded version and a fresh response id', () => {
    const payload = view.acceptPayload(order, '2026-12-01')

    assert.equal(payload.expectedResponseVersion, 3, 'taken from the order, never typed')
    assert.equal(payload.estimatedDeliveryDate, '2026-12-01')
    assert.match(payload.responseId, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i)
    assert.deepEqual(Object.keys(payload).sort(), [
      'estimatedDeliveryDate', 'expectedResponseVersion', 'responseId'
    ])
  })

  test('accept omits the date entirely when none was chosen', () => {
    const payload = view.acceptPayload(order, undefined)

    assert.equal('estimatedDeliveryDate' in payload, false, 'an omitted date means unknown')
    assert.deepEqual(Object.keys(payload).sort(), ['expectedResponseVersion', 'responseId'])
  })

  test('each command gets its own response id', () => {
    const first = view.acceptPayload(order)
    const second = view.acceptPayload(order)

    assert.notEqual(first.responseId, second.responseId)
  })

  test('a supplied response id is reused, so a retry is a replay', () => {
    const payload = view.acceptPayload(order, undefined, 'fixed-id')
    assert.equal(payload.responseId, 'fixed-id')
  })

  test('reject carries the reason, and the date update carries the date', () => {
    const rejection = view.rejectPayload(order, 'Out of stock')
    assert.equal(rejection.reason, 'Out of stock')
    assert.equal(rejection.expectedResponseVersion, 3)
    assert.equal('estimatedDeliveryDate' in rejection, false, 'rejection forbids a date')

    const dated = view.dateUpdatePayload(order, '2026-12-20')
    assert.equal(dated.estimatedDeliveryDate, '2026-12-20')
    assert.equal(dated.expectedResponseVersion, 3)
  })

  test('no payload ever contains a supplier code or a status', () => {
    for (const payload of [
      view.acceptPayload(order, '2026-12-01'),
      view.rejectPayload(order, 'why'),
      view.dateUpdatePayload(order, '2026-12-01')
    ]) {
      assert.equal('supplierCode' in payload, false)
      assert.equal('status' in payload, false, 'the frontend never proposes a status')
    }
  })
})

describe('error presentation', () => {

  test('a stale version asks for a reload and is never retried silently', () => {
    const shown = view.describeError(409, {
      error: { code: 'STALE_RESPONSE_VERSION', message: 'Version 0 does not match 2.' }
    })

    assert.equal(shown.code, 'STALE_RESPONSE_VERSION')
    assert.equal(shown.refresh, true)
    assert.match(shown.message, /Version 0 does not match 2\./)
  })

  test('a contract error is shown as the service wrote it', () => {
    const shown = view.describeError(400, {
      error: { code: 'MISSING_REJECTION_REASON', message: 'A rejection requires a reason.' }
    })

    assert.equal(shown.code, 'MISSING_REJECTION_REASON')
    assert.equal(shown.message, 'A rejection requires a reason.')
    assert.equal(shown.refresh, false)
  })

  test('an unexpected failure gets a safe generic message', () => {
    const shown = view.describeError(500, { stack: 'Error: at Object.<anonymous> …' })

    assert.equal(shown.code, 'HTTP_500')
    assert.equal(/stack|anonymous/i.test(shown.message), false, 'no internals are shown')
  })

  test('authentication and scoped not-found are explained plainly', () => {
    assert.equal(view.describeError(401, null).code, 'UNAUTHENTICATED')
    assert.equal(view.describeError(404, null).code, 'ORDER_NOT_FOUND')
  })
})

describe('the list is bounded', () => {

  test('the client never asks for more than the server maximum', () => {
    assert.equal(view.listQuery(0), `?limit=${view.PAGE_SIZE}&offset=0`)
    assert.equal(view.listQuery(20, 5000), `?limit=${view.MAX_PAGE_SIZE}&offset=20`)
    assert.equal(view.listQuery(-5), `?limit=${view.PAGE_SIZE}&offset=0`)
  })

  test('a full page implies another may follow', () => {
    assert.equal(view.hasNextPage(new Array(view.PAGE_SIZE).fill({}), view.PAGE_SIZE), true)
    assert.equal(view.hasNextPage([{}], view.PAGE_SIZE), false)
    assert.equal(view.hasNextPage([], view.PAGE_SIZE), false)
  })

  test('limit and offset are honoured by the service', async () => {
    const all = await get('/rest/supplier/v1/Orders', asSupplier1)
    assert.equal(all.data.length, 2)

    const first = await get('/rest/supplier/v1/Orders?limit=1&offset=0', asSupplier1)
    assert.equal(first.data.length, 1)

    const second = await get('/rest/supplier/v1/Orders?limit=1&offset=1', asSupplier1)
    assert.equal(second.data.length, 1)
    assert.notEqual(second.data[0].portalOrderId, first.data[0].portalOrderId)
  })

  test('a malformed page parameter is refused rather than ignored', async () => {
    for (const query of ['?limit=abc', '?limit=-1', '?offset=x', '?limit=1.5']) {
      const response = await get(`/rest/supplier/v1/Orders${query}`, asSupplier1)
      assert.equal(response.status, 400, `${query} should be refused`)
      assert.equal(response.data?.error?.code, 'INVALID_PAGINATION')
    }
  })

  test('an oversized limit is clamped, not refused', async () => {
    const response = await get('/rest/supplier/v1/Orders?limit=100000', asSupplier1)
    assert.equal(response.status, 200)
    assert.equal(response.data.length, 2)
  })

  test('a single order read and its items are not paged', async () => {
    const order = await get('/rest/supplier/v1/Orders/22222222-2222-4222-8222-000000000001', asSupplier1)
    assert.equal(order.status, 200)
    assert.equal(order.data.externalOrderNumber, 'PO00001001')

    // Items are already bounded by the ingestion rule, so the detail view is whole.
    const items = await get(
      '/rest/supplier/v1/Orders/22222222-2222-4222-8222-000000000001/items', asSupplier1
    )
    assert.equal(items.data.length, 2)
  })
})
