/**
 * Phase 6.5e — the explicit flush command.
 *
 * ARCHITECTURE.md: *"A CAP development command can similarly flush a committed
 * response. Automatic scheduling is a later enhancement."* This is that command
 * and nothing more. It is not a service, not a route and not a job; the only way
 * it runs is because somebody ran it, which is what keeps the commit boundaries
 * observable while the HTTP implementation stays small.
 *
 * It is deliberately NOT an administrative HTTP endpoint. Exposing one would
 * mean authorizing it, and a public trigger for an outbox drain is a far larger
 * surface than a command an operator runs against a bound application.
 *
 * Run it locally:
 *   npm run flush-responses -- --dry-run
 *
 * Run it against the deployed application, over its existing bindings:
 *   cf run-task cap-supplier-portal-srv --command "node scripts/flush-supplier-responses.js --limit 1"
 *
 * NOTHING SECRET IS PRINTED. The configuration is read from the environment,
 * the credential never leaves the transport, and the endpoint is reported as a
 * path rather than a full URL.
 */

import cds from '@sap/cds'
import { bootstrapCds } from '../srv/lib/cds-bootstrap'
import { HttpResponseTransport, ConfigError, readCiConfig } from '../srv/lib/ci-transport'
import { flushSupplierResponses, DEFAULT_LIMIT } from '../srv/lib/response-sender'

interface Args {
  limit: number
  dryRun: boolean
  help: boolean
}

function parseArgs(argv: string[]): Args {
  const args: Args = { limit: DEFAULT_LIMIT, dryRun: false, help: false }

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === '--dry-run') args.dryRun = true
    else if (arg === '--help' || arg === '-h') args.help = true
    else if (arg === '--limit') {
      const value = Number(argv[++i])
      if (!Number.isInteger(value) || value <= 0) {
        throw new Error('--limit needs a positive whole number.')
      }
      args.limit = value
    } else if (arg.startsWith('--limit=')) {
      const value = Number(arg.slice('--limit='.length))
      if (!Number.isInteger(value) || value <= 0) {
        throw new Error('--limit needs a positive whole number.')
      }
      args.limit = value
    } else {
      throw new Error(`Unknown argument "${arg}".`)
    }
  }

  return args
}

const USAGE = `
Flush committed supplier responses to Cloud Integration.

  --limit N    attempt at most N PENDING rows (default ${DEFAULT_LIMIT})
  --dry-run    build and print the payloads without sending anything
  --help       show this

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

  // A dry run must work with no credential at all, so the configuration is read
  // only when something is actually going to be sent.
  let transport: HttpResponseTransport | undefined
  if (!args.dryRun) {
    const config = readCiConfig()
    transport = new HttpResponseTransport(config)
    // The path, never the host and never the credential.
    console.log(`Target path: ${new URL(config.url).pathname}  (timeout ${config.timeoutMs} ms)`)
  } else {
    console.log('DRY RUN — nothing will be sent and no credential is read.')
  }

  // Model first, then connect. See `cds-bootstrap.ts` — the reverse order is
  // what made the first deployed dry-run fail inside HANA's cqn2sql, and it is
  // deliberately not inline here so that the ordering has its own test.
  await bootstrapCds(cds as any, line => console.log(line))

  const summary = await flushSupplierResponses({
    // On a dry run the transport is never reached; the sender returns before it.
    transport: transport ?? { send: async () => { throw new Error('unreachable on a dry run') } },
    limit: args.limit,
    dryRun: args.dryRun,
    log: line => console.log(line)
  })

  if (args.dryRun) {
    for (const outcome of summary.outcomes) {
      if (outcome.payload) console.log(JSON.stringify(outcome.payload, null, 2))
    }
  }

  console.log(
    `\nscanned ${summary.scanned}` +
    `  delivered ${summary.delivered}` +
    `  failed ${summary.failed}` +
    `  pending ${summary.pending}` +
    `  unknown ${summary.unknown}` +
    `  skipped ${summary.skipped}` +
    `  before-due ${summary.beforeDue}` +
    `  retry-exhausted ${summary.retryExhausted}` +
    `  retry-window-blocked ${summary.retryWindowBlocked}`
  )

  // A non-zero exit for anything that did not reach SAP, so a task's outcome is
  // visible without reading the log. UNKNOWN counts: it means we do not know.
  return summary.failed + summary.unknown > 0 ? 1 : 0
}

main()
  .then(code => process.exit(code))
  .catch(error => {
    // A configuration problem is the operator's, not a stack trace's.
    console.error(error instanceof ConfigError ? error.message : error)
    process.exit(2)
  })
