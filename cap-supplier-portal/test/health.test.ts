import cds from '@sap/cds'
import assert from 'node:assert/strict'
import type { Server } from 'node:http'
import path from 'node:path'
import { after, before, test } from 'node:test'

/**
 * Phase 4.1 foundation test.
 *
 * Proves that the CAP runtime boots this project, that the REST adapter serves
 * the TypeScript handler, and that a test can drive the running server. It
 * asserts nothing about business behaviour, because none exists yet.
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

test('the CAP runtime serves the health endpoint', async () => {
  const response = await portal.GET('/health/ping')

  assert.equal(response.status, 200)
  assert.equal(response.data.status, 'UP')
  assert.equal(response.data.component, 'cap-supplier-portal')
  assert.equal(response.data.phase, '4.1')
  assert.ok(Number.isInteger(response.data.uptimeMs))
})
