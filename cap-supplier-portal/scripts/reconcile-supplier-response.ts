/**
 * Phase 6.5g — the UNKNOWN reconciliation command.
 *
 * `UNKNOWN` means the receiver may or may not have committed: a timeout, a
 * `500`, a `504`, a dropped socket. The sender deliberately refuses to guess, so
 * nothing drains such a row automatically and this command is the only thing
 * that moves it. One row, named explicitly, one attempt, no loop.
 *
 * IT DOES NOT READ SAP. CAP has no direct dependency on SAP and gains none
 * here — Cloud Integration remains the only mediation layer. The question "did
 * SAP already get this?" is answered by sending the same durable response
 * again, which is sound because RAP's idempotency is runtime-proven: the same
 * `responseId` with the same content returned HTTP 204 with `LastChangedAt`
 * unmoved. If the original landed, the replay is a no-op; if it never landed,
 * the replay applies it; if the answer is ambiguous again, the row stays
 * `UNKNOWN` and nothing has been lost.
 *
 * Nothing commercial is re-decided. No new `responseId`, no new version, no new
 * response, and `Orders` is never touched.
 *
 * Run it against the deployed application, over its existing bindings:
 *   cf run-task cap-supplier-portal-srv \
 *     --command "node scripts/reconcile-supplier-response.js --response-id <uuid>"
 *
 * NOTHING SECRET IS PRINTED. Configuration comes from the environment, the
 * credential never leaves the transport, and the endpoint is reported as a path.
 */

import cds from '@sap/cds'
import { bootstrapCds } from '../srv/lib/cds-bootstrap'
import { HttpResponseTransport, ConfigError, readCiConfig } from '../srv/lib/ci-transport'
import { reconcileSupplierResponse } from '../srv/lib/response-sender'

interface Args {
  responseId?: string
  help: boolean
}

function parseArgs(argv: string[]): Args {
  const args: Args = { help: false }

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === '--help' || arg === '-h') args.help = true
    else if (arg === '--response-id') args.responseId = argv[++i]
    else if (arg.startsWith('--response-id=')) args.responseId = arg.slice('--response-id='.length)
    else throw new Error(`Unknown argument "${arg}".`)
  }

  return args
}

const USAGE = `
Reconcile ONE supplier response that is stuck in UNKNOWN, by replaying it
through Cloud Integration under its existing responseId.

  --response-id <uuid>   the durable response to replay (required)
  --help                 show this

Only an UNKNOWN row can be reconciled. DELIVERED, FAILED and PENDING are
refused, and the row's decision, version, date, reason and respondedAt are
never modified. Exactly one attempt is made; there is no retry loop.

Configuration, from the environment only:
  PIH_CI_SUPPLIER_RESPONSE_URL   the PIH_SupplierResponse_v1 endpoint
  PIH_CI_CLIENT_ID               Process Integration Runtime clientid
  PIH_CI_CLIENT_SECRET           Process Integration Runtime clientsecret
  PIH_CI_TIMEOUT_MS              optional request ceiling, default 30000
`.trim()

async function main() {
  const args = parseArgs(process.argv.slice(2))

  if (args.help) {
    console.log(USAGE)
    return 0
  }

  // Refused before anything is configured, connected to or sent. An operator
  // reconciling the wrong row by omission is the failure mode worth blocking
  // earliest.
  if (!args.responseId || !args.responseId.trim()) {
    console.error('--response-id is required. Nothing was sent.')
    console.error(USAGE)
    return 2
  }

  const config = readCiConfig()
  const transport = new HttpResponseTransport(config)
  console.log(`Target path: ${new URL(config.url).pathname}  (timeout ${config.timeoutMs} ms)`)

  await bootstrapCds(cds as any, line => console.log(line))

  const result = await reconcileSupplierResponse({
    responseId: args.responseId,
    transport,
    log: line => console.log(line)
  })

  if (result.refused) {
    console.error(`REFUSED ${result.refused}: ${result.message}`)
    return 2
  }

  const outcome = result.outcome!
  console.log(
    `\nresponseId ${outcome.responseId}  v${outcome.version}  ${outcome.decision}` +
    `\nstate      ${outcome.state}` +
    `\nstatus     ${outcome.status ?? 'no answer'}` +
    `\ncorrelation ${outcome.correlationId}` +
    (outcome.error ? `\nerror      ${outcome.error}` : '')
  )

  if (outcome.state === 'DELIVERED') {
    console.log('\nResolved: SAP holds this response.')
    return 0
  }
  if (outcome.state === 'UNKNOWN') {
    // Still ambiguous, and that is a legitimate result rather than a bug. The
    // row keeps its identity and can be reconciled again later.
    console.log('\nStill UNKNOWN. The row is unchanged in substance and may be reconciled again.')
    return 1
  }
  console.log(`\nNow ${outcome.state}. This needs a decision, not another replay.`)
  return 1
}

main()
  .then(code => process.exit(code))
  .catch(error => {
    console.error(error instanceof ConfigError ? error.message : error)
    process.exit(2)
  })
