import cds from '@sap/cds'
import assert from 'node:assert/strict'
import type { Server } from 'node:http'
import path from 'node:path'
import { after, before, beforeEach, describe, test } from 'node:test'
import { SupplierResponseDeliveries, SupplierResponseDeliveryAttempts } from '#cds-models/pih/portal'
import { readOperationalStatus } from '../srv/lib/operational-status'

const portal = cds.test(path.resolve(__dirname, '..'))
let server: Server | undefined

before(async () => {
  await new Promise<void>(resolve => portal.then(started => { server = started.server; resolve() }))
})
after(() => server?.close())
beforeEach(async () => {
  await DELETE.from(SupplierResponseDeliveryAttempts)
  await DELETE.from(SupplierResponseDeliveries)
  version = 0
})

const NOW = new Date('2026-09-22T12:00:00.000Z')
const ORDER = '22222222-2222-4222-8222-000000000001'
let version = 0

async function insert(state: string, fields: Record<string, unknown> = {}) {
  const ID = cds.utils.uuid()
  await INSERT.into(SupplierResponseDeliveries).entries({
    ID, responseId: cds.utils.uuid(), order_ID: ORDER, version: ++version,
    decision: 'ACCEPTED', respondedAt: NOW.toISOString(), state, attempts: 0,
    ...fields
  } as any)
  return ID
}

describe('Phase 7.7 operational status is read-only and complete', () => {
  test('reports census, retry blocks, leases, UNKNOWN, history and correlation', async () => {
    const due = await insert('PENDING', { nextAttemptAt: '2026-09-22T12:01:00.000Z' })
    await insert('PENDING', { attempts: 4 })
    await insert('PENDING', {
      attempts: 1,
      retryWindowStartedAt: '2026-09-22T11:40:00.000Z',
      nextAttemptAt: '2026-09-22T11:41:00.000Z'
    })
    await insert('IN_FLIGHT', { leaseOwner: cds.utils.uuid(), leaseExpiresAt: '2026-09-22T12:01:00.000Z' })
    await insert('IN_FLIGHT', { leaseOwner: cds.utils.uuid(), leaseExpiresAt: '2026-09-22T11:59:00.000Z' })
    const unknown = await insert('UNKNOWN', { lastCorrelationId: '11111111-2222-4333-8444-555555555555' })
    await INSERT.into(SupplierResponseDeliveryAttempts).entries({
      delivery_ID: unknown, attemptNumber: 1,
      correlationId: '11111111-2222-4333-8444-555555555555',
      startedAt: NOW.toISOString(), durationMs: 10, outcome: 'UNKNOWN', errorCategory: 'NO_ANSWER'
    } as any)

    const beforeRows = await SELECT.from(SupplierResponseDeliveries)
    const status = await readOperationalStatus(NOW)
    const afterRows = await SELECT.from(SupplierResponseDeliveries)

    assert.deepEqual(status.stateCensus, { PENDING: 3, IN_FLIGHT: 2, UNKNOWN: 1 })
    assert.equal(status.beforeDue, 1)
    assert.equal(status.retryExhausted, 1)
    assert.equal(status.retryWindowBlocked, 1)
    assert.equal(status.liveLeases, 1)
    assert.equal(status.staleLeases, 1)
    assert.equal(status.unknown, 1)
    assert.equal(status.historyCount, 1)
    assert.equal(status.deliveries.find(row => row.ID === unknown)?.historyCount, 1)
    assert.equal(status.deliveries.find(row => row.ID === unknown)?.lastCorrelationId,
      '11111111-2222-4333-8444-555555555555')
    assert.ok(status.deliveries.find(row => row.ID === due))
    assert.deepEqual(afterRows, beforeRows, 'the report performs no mutations')
  })
})
