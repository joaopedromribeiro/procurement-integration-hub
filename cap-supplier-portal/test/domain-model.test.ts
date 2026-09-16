import cds from '@sap/cds'
import assert from 'node:assert/strict'
import type { Server } from 'node:http'
import path from 'node:path'
import { after, before, describe, test } from 'node:test'
import { OrderItems, Orders, Suppliers } from '#cds-models/pih/portal'

/**
 * Phase 4.2 persistence tests.
 *
 * These exercise the domain model through CAP's query API only. No service and
 * no HTTP business endpoint is involved, because none exists: ingestion is
 * Phase 4.3 and supplier decisions are Phase 4.4. Importing the entities from
 * `#cds-models` is itself part of the check — it proves the generated types
 * resolve both to the TypeScript compiler and to the Node runtime.
 */
const portal = cds.test(path.resolve(__dirname, '..'))

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

describe('the model deploys', () => {

  test('all three entities are in the deployed model', () => {
    const model = cds.model
    assert.ok(model, 'the CDS model is loaded')

    for (const name of ['pih.portal.Suppliers', 'pih.portal.Orders', 'pih.portal.OrderItems']) {
      assert.ok(model.definitions[name], `${name} is missing from the model`)
    }
  })

  test('the composition and the association are modelled as different things', () => {
    const model = cds.model
    assert.ok(model, 'the CDS model is loaded')

    const orders = model.definitions['pih.portal.Orders'] as any
    const suppliers = model.definitions['pih.portal.Suppliers'] as any

    assert.equal(orders.elements.items.type, 'cds.Composition')
    assert.equal(orders.elements.supplier.type, 'cds.Association')
    assert.equal(suppliers.elements.orders.type, 'cds.Association')
  })
})

describe('fixtures load', () => {

  test('suppliers are queryable with their fixture values', async () => {
    const suppliers = await SELECT.from(Suppliers).orderBy('supplierCode')

    assert.equal(suppliers.length, 2)
    assert.deepEqual(suppliers.map(s => s.supplierCode), ['SUP001', 'SUP002'])
    assert.equal(suppliers[0].name, 'Example Technology Supplier')
    assert.equal(suppliers[0].active, true)
    assert.ok(suppliers[0].ID, 'the portal assigns its own UUID key')
  })

  test('orders are queryable and carry both identities', async () => {
    const orders = await SELECT.from(Orders).orderBy('externalOrderNumber')

    assert.equal(orders.length, 3)
    assert.deepEqual(
      orders.map(o => o.externalOrderNumber),
      ['PO00001001', 'PO00001002', 'PO00001003']
    )

    const first = orders[0]
    assert.ok(first.ID, 'the portal has its own key')
    assert.equal(first.sourceSystem, 'PIH_ABAP_DEV')
    assert.ok(first.sourceOrderId, 'the SAP identity is kept separately')
    assert.equal(first.sourceRevision, 1)
    assert.equal(first.currency, 'EUR')
    assert.equal(Number(first.totalAmount), 1861.5)
    assert.equal(first.status, 'RECEIVED')
    assert.equal(first.responseVersion, 0)
    assert.equal(first.estimatedDeliveryDate, null)
    assert.equal(first.rejectionReason, null)
    assert.ok(first.deliveryId)
    assert.ok(first.receivedAt)
  })

  test('order items are queryable and use portal-side names and units', async () => {
    const items = await SELECT.from(OrderItems)

    assert.equal(items.length, 4)
    for (const item of items) {
      assert.equal(item.uom, 'PCE', 'the boundary maps EA to the portal unit PCE')
      assert.equal(item.currency, 'EUR')
    }

    const laptop = items.find(i => i.productCode === 'MAT001' && Number(i.quantity) === 2)
    assert.ok(laptop)
    assert.equal(laptop.description, 'Laptop')
    assert.equal(Number(laptop.unitPrice), 750)
    assert.equal(Number(laptop.lineAmount), 1500)
  })
})

describe('relationships', () => {

  test('an order composes its items, and the line totals sum to the header total', async () => {
    const order = await SELECT.one
      .from(Orders, o => {
        o.ID, o.externalOrderNumber, o.totalAmount,
        o.items(i => { i.lineNumber, i.productCode, i.lineAmount })
      })
      .where({ externalOrderNumber: 'PO00001001' })

    assert.ok(order)
    assert.equal(order.items?.length, 2)
    assert.deepEqual(order.items?.map(i => i.lineNumber), [10, 20])

    const summed = order.items!.reduce((total, item) => total + Number(item.lineAmount), 0)
    assert.equal(summed, Number(order.totalAmount))
  })

  test('a supplier reaches its orders through the association', async () => {
    const supplier = await SELECT.one
      .from(Suppliers, s => { s.supplierCode, s.orders(o => o.externalOrderNumber) })
      .where({ supplierCode: 'SUP001' })

    assert.equal(supplier?.orders?.length, 2)

    const other = await SELECT.one
      .from(Suppliers, s => { s.supplierCode, s.orders(o => o.externalOrderNumber) })
      .where({ supplierCode: 'SUP002' })

    assert.equal(other?.orders?.length, 1)
  })

  test('deleting an order deletes its items but never its supplier', async () => {
    const supplier = await SELECT.one.from(Suppliers).where({ supplierCode: 'SUP002' })
    const orderID = cds.utils.uuid()

    await INSERT.into(Orders).entries({
      ID: orderID,
      sourceSystem: 'PIH_ABAP_DEV',
      sourceOrderId: cds.utils.uuid(),
      sourceRevision: 1,
      externalOrderNumber: 'PO00009999',
      supplier_ID: supplier!.ID,
      currency: 'EUR',
      totalAmount: 10.00,
      deliveryId: cds.utils.uuid(),
      items: [{
        sourceItemId: cds.utils.uuid(),
        lineNumber: 10,
        productCode: 'MAT001',
        description: 'Laptop',
        quantity: 1.000,
        uom: 'PCE',
        unitPrice: 10.0000,
        currency: 'EUR',
        lineAmount: 10.00
      }]
    })

    assert.equal((await SELECT.from(OrderItems).where({ order_ID: orderID })).length, 1)

    await DELETE.from(Orders).where({ ID: orderID })

    assert.equal(
      (await SELECT.from(OrderItems).where({ order_ID: orderID })).length, 0,
      'composition: the items go with their order'
    )
    assert.ok(
      await SELECT.one.from(Suppliers).where({ supplierCode: 'SUP002' }),
      'association: the supplier outlives the order'
    )
  })
})
