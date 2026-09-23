import { copyFileSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const router = dirname(fileURLToPath(import.meta.url))
const app = resolve(router, '..')
const output = join(router, 'resources')

// Generated assets have one source of truth: app/. Never ship the mock auth module.
rmSync(output, { recursive: true, force: true })
mkdirSync(join(output, 'lib'), { recursive: true })
for (const asset of ['styles.css', 'supplier-ui.mjs']) {
  copyFileSync(join(app, asset), join(output, asset))
}
copyFileSync(join(app, 'lib', 'order-view.mjs'), join(output, 'lib', 'order-view.mjs'))
copyFileSync(join(app, 'auth.production.mjs'), join(output, 'auth.mjs'))

const source = readFileSync(join(app, 'index.html'), 'utf8')
const mockBanner = /<p class="mock-warning">[\s\S]*?<\/p>/
const mockForm = /<section id="signin" class="panel">[\s\S]*?<\/section>/
if (!mockBanner.test(source) || !mockForm.test(source)) {
  throw new Error('Supplier UI mock markup changed; production copy was not generated')
}
const production = source
  .replace(mockBanner, '<p>Authenticated with SAP BTP. Supplier decisions are not yet enabled in this interactive UI.</p>')
  .replace(mockForm, '<section id="signin" class="panel" hidden><form id="signin-form"></form></section>')
writeFileSync(join(output, 'index.html'), production)
