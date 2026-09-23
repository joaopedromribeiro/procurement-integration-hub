import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { readFileSync, readdirSync, statSync } from 'node:fs'
import path from 'node:path'
import { describe, test } from 'node:test'

const project = process.cwd()
const router = path.join(project, 'app', 'router')
const read = (file: string) => readFileSync(path.join(router, file), 'utf8')
const resources = path.join(router, 'resources')

function filesUnder(directory: string): string[] {
  return readdirSync(directory).flatMap(name => {
    const file = path.join(directory, name)
    return statSync(file).isDirectory() ? filesUnder(file) : [file]
  })
}

describe('Phase 8.2a interactive boundary (static, not runtime acceptance)', () => {
  test('approuter only proxies the supplier API and requires XSUAA', () => {
    const config = JSON.parse(read('xs-app.json'))
    assert.equal(config.authenticationMethod, 'route')
    assert.equal(config.routes.length, 2)
    assert.equal(config.routes[0].destination, 'srv-api')
    assert.equal(config.routes[0].authenticationType, 'xsuaa')
    assert.equal(config.routes[0].csrfProtection, true)
    assert.match(config.routes[0].source, /rest\/supplier\/v1/)
    assert.doesNotMatch(config.routes[0].source, /integration/)
    assert.equal(config.routes[1].authenticationType, 'xsuaa')
    assert.equal(config.routes[1].destination, undefined)
    assert.equal(config.routes[1].localDir, 'resources')
  })

  test('production static bundle has no mock credentials, Basic auth, or POST capability', () => {
    execFileSync(process.execPath, [path.join(router, 'build.mjs')], { cwd: project })
    const html = read('resources/index.html')
    const auth = read('resources/auth.mjs')
    const ui = read('resources/supplier-ui.mjs')
    const files = filesUnder(resources)
    assert.equal(files.length, 5, 'ship only the five approved static assets')
    for (const file of files) {
      const source = readFileSync(file, 'utf8')
      assert.doesNotMatch(
        source,
        /\busername\b|\bpassword\b|supplier1|supplier2|sessionStorage|localStorage|Basic\s|Authorization|btoa|signin-form.*addEventListener|\/rest\/integration\/v1/i,
        `${file} must contain no mock credential implementation or integration route`
      )
    }
    assert.match(auth, /mutationsEnabled = false/)
    assert.match(ui, /!auth\.mutationsEnabled/)
    assert.doesNotMatch(ui, /signin-form|signout.*addEventListener/)
    assert.match(ui, /\/rest\/supplier\/v1/)
    assert.doesNotMatch(html, /mock sign-in/i)
  })

  test('development-only auth retains mock sign-in and Basic authentication', () => {
    const mock = readFileSync(path.join(project, 'app', 'auth.mjs'), 'utf8')
    assert.match(mock, /sessionStorage/)
    assert.match(mock, /Basic /)
    assert.match(mock, /signin-form.*addEventListener/)
  })

  test('MTA forwards the user token through the existing srv-api destination', () => {
    const mta = readFileSync(path.join(project, 'mta.yaml'), 'utf8')
    assert.match(mta, /name: cap-supplier-portal-router/)
    assert.match(mta, /name: srv-api[\s\S]*?url: ~\{srv-url\}[\s\S]*?forwardAuthToken: true/)
    assert.match(mta, /https:\/\/~\{router-api\/router-uri\}\/login\/callback/)
  })
})
