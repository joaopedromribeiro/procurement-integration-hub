import assert from 'node:assert/strict'
import { describe, test } from 'node:test'

import { bootstrapCds, isInMemory, IN_MEMORY_URL, type CdsBootstrapHost } from '../srv/lib/cds-bootstrap'

/**
 * Phase 6.5e — the standalone command's boot order.
 *
 * These tests exist because of a defect that only appeared on Cloud Foundry:
 * the command connected to the database BEFORE publishing the model, the HANA
 * service captured an empty model, and `SELECT.from(...)` could not be inferred
 * — "Query was not inferred and includes '*' in the columns."
 *
 * Local SQLite never caught it, because `cds.deploy` repairs `db.model` as a
 * side effect and the deploy only runs on the in-memory profile. So a test that
 * merely runs the command locally would have passed both before and after the
 * fix and proven nothing.
 *
 * The order is therefore asserted DIRECTLY, against a recording stand-in, with
 * no real database involved. That is what makes these tests able to fail for
 * the original defect.
 */

interface Recorder {
  host: CdsBootstrapHost
  calls: string[]
  modelAtConnect: any
  deployedModel: any
}

function recorder(dbUrl?: string): Recorder {
  const calls: string[] = []
  const state: any = { modelAtConnect: undefined, deployedModel: undefined }

  const compiled = { definitions: { 'pih.portal.SupplierResponseDeliveries': { kind: 'entity' } } }
  const db = { kind: 'fake-db' }

  const host: CdsBootstrapHost = {
    // Mirrors the real `cds.model`: a truthy but empty model before boot, which
    // is exactly why `??=` was never a safe way to publish it.
    model: { definitions: undefined },
    env: { requires: { db: dbUrl ? { credentials: { url: dbUrl } } : {} } },

    async load(pattern: string) {
      calls.push(`load(${pattern})`)
      return { raw: true }
    },
    compile: {
      for: {
        nodejs(_csn: any) {
          calls.push('compile.for.nodejs')
          return compiled
        }
      }
    },
    connect: {
      async to(name: string) {
        calls.push(`connect.to(${name})`)
        // The real database service captures the model here and never updates
        // it again. Recording it is the whole assertion.
        state.modelAtConnect = host.model
        return db
      }
    },
    deploy(model: any) {
      calls.push('deploy')
      state.deployedModel = model
      return { to: async (_db: any) => { calls.push('deploy.to'); return _db } }
    }
  }

  return {
    host, calls,
    get modelAtConnect() { return state.modelAtConnect },
    get deployedModel() { return state.deployedModel }
  } as Recorder
}

describe('standalone command boot order', () => {

  test('the model is published BEFORE the database is connected', async () => {
    const r = recorder()

    await bootstrapCds(r.host)

    const compileIndex = r.calls.indexOf('compile.for.nodejs')
    const connectIndex = r.calls.indexOf('connect.to(db)')

    assert.ok(compileIndex >= 0, 'the model is compiled')
    assert.ok(connectIndex >= 0, 'the database is connected')
    assert.ok(
      compileIndex < connectIndex,
      'the model must be compiled and published before connect; the reverse order is the ' +
      'deployed defect that produced "Query was not inferred and includes \'*\' in the columns"'
    )
  })

  test('the model the database captures at connect actually has definitions', async () => {
    const r = recorder()

    await bootstrapCds(r.host)

    // This is the assertion that fails for the original defect. Connecting
    // first would capture the empty placeholder, and an empty model is exactly
    // what stops HANA resolving the columns behind `*`.
    assert.ok(r.modelAtConnect, 'a model was captured at connect')
    assert.ok(
      r.modelAtConnect.definitions,
      'the captured model carries definitions rather than the empty placeholder'
    )
    assert.ok(
      'pih.portal.SupplierResponseDeliveries' in r.modelAtConnect.definitions,
      'the outbox entity is resolvable by the service that will query it'
    )
  })

  test('the runtime compilation is used, not a bare link', async () => {
    const r = recorder()
    await bootstrapCds(r.host)

    // `cds.compile.for.nodejs` applies the runtime transformations the database
    // layer reads. The previously successful HANA verification tasks in this
    // app used exactly this call, and `cds.linked` alone is not equivalent.
    assert.ok(r.calls.includes('compile.for.nodejs'), 'compiled for the Node.js runtime')
  })
})

describe('deploy is development-only', () => {

  test('the in-memory profile deploys the model it just published', async () => {
    const r = recorder(IN_MEMORY_URL)

    const result = await bootstrapCds(r.host)

    assert.equal(result.deployed, true)
    assert.ok(r.calls.includes('deploy.to'), 'the in-memory database is populated')
    // Deliberately NOT the runtime-compiled model: cds.deploy runs the
    // relational transformation itself and flattening twice is a compiler error.
    assert.notEqual(r.deployedModel, r.host.model, 'deploy gets its own freshly loaded CSN')
    assert.equal(r.calls.filter(c => c === 'load(*)').length, 2, 'the model is loaded twice, on purpose')
    // Order still holds: the deploy happens after the connect, never before it.
    assert.ok(r.calls.indexOf('connect.to(db)') < r.calls.indexOf('deploy'))
  })

  test('a bound HANA container is connected to and NOTHING else', async () => {
    // A real bound container's url is a JDBC url, never ':memory:'.
    const r = recorder('jdbc:sap://example.invalid:443?encrypt=true')

    const result = await bootstrapCds(r.host)

    assert.equal(result.deployed, false)
    assert.ok(!r.calls.includes('deploy'), 'no cds.deploy on a deployed target')
    assert.ok(!r.calls.includes('deploy.to'), 'no schema creation and no fixture seeding')
    assert.deepEqual(r.calls, ['load(*)', 'compile.for.nodejs', 'connect.to(db)'])
  })

  test('an unbound production profile still never deploys', async () => {
    // Production resolves with no `credentials` at all until a binding supplies
    // them; an absent url must not be mistaken for the in-memory one.
    const r = recorder()

    const result = await bootstrapCds(r.host)

    assert.equal(result.deployed, false)
    assert.ok(!r.calls.includes('deploy'))
  })

  test('isInMemory matches only the exact in-memory url', () => {
    assert.equal(isInMemory({ requires: { db: { credentials: { url: ':memory:' } } } }), true)
    assert.equal(isInMemory({ requires: { db: { credentials: { url: 'jdbc:sap://x' } } } }), false)
    assert.equal(isInMemory({ requires: { db: {} } }), false)
    assert.equal(isInMemory({ requires: {} }), false)
    assert.equal(isInMemory({}), false)
    assert.equal(isInMemory(undefined), false)
  })
})
