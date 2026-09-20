/**
 * Phase 6.5e — the Cloud Integration transport.
 *
 * The only file in the portal that opens a socket, and the only one that reads a
 * credential. Both facts are deliberate: the sender in `response-sender.ts` is
 * written against the `ResponseTransport` interface below and never learns
 * whether it is talking to a tenant or to a test double, which is what lets the
 * whole delivery state machine be proven without a live iFlow.
 *
 * NOTHING HERE IS EVER LOGGED. The Authorization header is built inside `send`
 * and does not escape it, the configuration object is never returned to a
 * caller, and `safeDetail` truncates a response body to a short diagnosis
 * precisely so that a receiver echoing something sensitive cannot be persisted
 * into `lastError` or printed by the flush command.
 */

import type { SupplierResponsePayload, TransportResult } from './supplier-response'

/**
 * One delivery attempt.
 *
 * It resolves for every outcome and rejects for none: a timeout is a result
 * (`answered: false`), not an exception, because the caller has to record it
 * against the row rather than lose the attempt. See `classify`.
 */
export interface ResponseTransport {
  send(payload: SupplierResponsePayload, correlationId: string): Promise<TransportResult>
}

/**
 * Where the sender posts, and as whom.
 *
 * Read from the environment and never from a tracked file. The values live in
 * the Cloud Foundry application's own environment in the deployed case and in
 * the operator's shell in the local case; the repository holds the NAMES only.
 */
export interface CiConfig {
  url: string
  clientId: string
  clientSecret: string
  timeoutMs: number
}

export const CI_URL_VAR = 'PIH_CI_SUPPLIER_RESPONSE_URL'
export const CI_CLIENT_ID_VAR = 'PIH_CI_CLIENT_ID'
export const CI_CLIENT_SECRET_VAR = 'PIH_CI_CLIENT_SECRET'
export const CI_TIMEOUT_VAR = 'PIH_CI_TIMEOUT_MS'

/**
 * API_CONTRACTS.md proposes a 25 s Cloud Integration processing budget, and the
 * iFlow's own work — validate, map, fetch a CSRF token from SAP, then post the
 * action — all happens inside this one request. The sender's ceiling is set
 * above that budget so that a slow-but-working iFlow is not cut off and turned
 * into an avoidable UNKNOWN, and still bounded so the command cannot hang.
 */
export const DEFAULT_TIMEOUT_MS = 30_000

export class ConfigError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'ConfigError'
  }
}

/**
 * Reads the transport configuration, refusing rather than defaulting.
 *
 * A missing URL must never fall back to a built-in endpoint and a missing
 * credential must never fall back to an unauthenticated call: both would turn a
 * misconfigured environment into a silent behaviour change against a real
 * system. The message names the variable and never its value.
 */
export function readCiConfig(env: NodeJS.ProcessEnv = process.env): CiConfig {
  const url = env[CI_URL_VAR]?.trim()
  const clientId = env[CI_CLIENT_ID_VAR]?.trim()
  const clientSecret = env[CI_CLIENT_SECRET_VAR]

  const missing = [
    url ? null : CI_URL_VAR,
    clientId ? null : CI_CLIENT_ID_VAR,
    clientSecret ? null : CI_CLIENT_SECRET_VAR
  ].filter(Boolean)

  if (missing.length) {
    throw new ConfigError(
      `The supplier-response sender is not configured: ${missing.join(', ')} ` +
      'must be set in the environment. Never put these values in a tracked file.'
    )
  }

  if (!/^https:\/\//i.test(url!)) {
    throw new ConfigError(
      `${CI_URL_VAR} must be an https URL; a credential must not be sent over plain HTTP.`
    )
  }

  const rawTimeout = env[CI_TIMEOUT_VAR]
  const timeoutMs = rawTimeout ? Number(rawTimeout) : DEFAULT_TIMEOUT_MS
  if (!Number.isInteger(timeoutMs) || timeoutMs <= 0) {
    throw new ConfigError(`${CI_TIMEOUT_VAR} must be a positive whole number of milliseconds.`)
  }

  return { url: url!, clientId: clientId!, clientSecret: clientSecret!, timeoutMs }
}

/**
 * A short, safe diagnosis of a refusal.
 *
 * Collapsed to one line and cut to 180 characters. A receiver's error body is
 * useful for telling a 400 from a 409 and is not a place this project will store
 * unbounded foreign text: it is written to `lastError` and printed by an
 * operator's console, so it is treated as untrusted.
 */
export function safeDetail(body: string): string {
  const flat = body.replace(/\s+/g, ' ').trim()
  if (!flat) return 'the receiver returned no body'
  return flat.length > 180 ? `${flat.slice(0, 177)}...` : flat
}

/**
 * The real transport: one bounded POST per attempt.
 *
 * HTTP Basic with a Process Integration Runtime `clientid`/`clientsecret` is
 * what was runtime-proven against this sender channel, whose HTTPS sender uses
 * User Role `ESBMessaging.send`. It is deliberately the development-phase
 * mechanism; a client-credentials token flow is a later hardening step and is
 * not implemented here, because implementing an unproven second auth path
 * alongside a proven one would mean two ways for the first real end-to-end run
 * to fail.
 *
 * There is no retry loop inside `send`. A transient failure returns a result,
 * the row goes back to PENDING, and the operator runs the command again — the
 * architecture's explicit flush, not a request sleeping through a retry budget.
 */
export class HttpResponseTransport implements ResponseTransport {
  private readonly config: CiConfig

  constructor(config: CiConfig = readCiConfig()) {
    this.config = config
  }

  /** The endpoint, for the command's own banner. Carries no credential. */
  get endpoint(): string {
    return this.config.url
  }

  async send(payload: SupplierResponsePayload, correlationId: string): Promise<TransportResult> {
    const authorization =
      'Basic ' + Buffer.from(`${this.config.clientId}:${this.config.clientSecret}`).toString('base64')

    try {
      const response = await fetch(this.config.url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
          // Transport metadata for exactly this attempt, and the only header
          // that changes between a first send and its replay.
          'X-Correlation-ID': correlationId,
          // Taken from the payload rather than from a second argument, so it
          // CANNOT drift from the body. API_CONTRACTS.md permits this header
          // and requires that "where one is present it must equal the body
          // identity"; reading the same field twice is what makes a mismatch
          // unrepresentable rather than merely unlikely. The body's responseId
          // remains the authoritative identity — an adapter that drops custom
          // headers changes nothing about how SAP deduplicates.
          'Idempotency-Key': payload.responseId,
          Authorization: authorization
        },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(this.config.timeoutMs)
      })

      // Read the body only to diagnose a refusal. A 2xx body is irrelevant: the
      // verified route answers 204 with nothing in it.
      let detail: string | undefined
      if (response.status < 200 || response.status >= 300) {
        detail = safeDetail(await response.text().catch(() => ''))
      }

      return { answered: true, status: response.status, detail }
    } catch (error: any) {
      // No HTTP answer: a timeout, an aborted socket, a DNS or TLS failure. The
      // receiver may already have committed, so this is reported as unanswered
      // and the caller leaves the row replayable under the same responseId.
      const cause = error?.name === 'TimeoutError' || error?.name === 'AbortError'
        ? `no answer within ${this.config.timeoutMs} ms`
        : `${error?.name ?? 'Error'}: ${error?.message ?? 'the request could not be completed'}`

      return { answered: false, detail: safeDetail(cause) }
    }
  }
}
