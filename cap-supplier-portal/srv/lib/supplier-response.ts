/**
 * Phase 6.5e — the supplier-response wire contract and the transport
 * classification, as pure functions.
 *
 * Nothing here touches the database, the network, the clock or the environment.
 * That is deliberate: the two things most worth testing about a sender are the
 * exact bytes it puts on the wire and how it reads the answer, and neither
 * should need a server, a fixture or a live Cloud Integration tenant to assert.
 * The sender in `response-sender.ts` supplies the rows, the transport and the
 * correlation IDs; this file decides what they mean.
 */

/**
 * The frozen CAP → CI payload, exactly as API_CONTRACTS.md fixes it and exactly
 * as the deployed `PIH_SupplierResponse_v1` was runtime-verified against.
 *
 * The field set and the names are the contract. `estimatedDeliveryDate` and
 * `reason` are explicitly nullable rather than optional, because the iFlow was
 * proven against a payload that carries them as `null` — omitting a key is a
 * different message from sending it null, and this project does not get to find
 * out which one the mapping tolerates by guessing.
 */
export interface SupplierResponsePayload {
  schemaVersion: string
  responseId: string
  sourceSystem: string
  sourceOrderId: string
  sourceRevision: number
  deliveryId: string
  portalOrderId: string
  supplierCode: string
  responseVersion: number
  decision: string
  estimatedDeliveryDate: string | null
  reason: string | null
  respondedAt: string
}

/** The persisted outbox row, in the shape the sender reads it. */
export interface ResponseRow {
  ID: string
  responseId: string
  order_ID: string
  version: number
  decision: string
  estimatedDeliveryDate?: string | null
  reason?: string | null
  respondedAt?: string | Date | null
  state?: string | null
  attempts?: number | null
  nextAttemptAt?: string | Date | null
  retryWindowStartedAt?: string | Date | null
}

/** The portal order the response answers, joined with its supplier code. */
export interface ResponseOrder {
  ID: string
  sourceSystem: string
  sourceOrderId: string
  sourceRevision: number
  deliveryId: string
  supplierCode: string
}

export const SCHEMA_VERSION = '1.0'

/** Raised when a row cannot be turned into a payload. Never retried blindly. */
export class PayloadError extends Error {
  readonly code: string
  constructor(code: string, message: string) {
    super(message)
    this.code = code
    this.name = 'PayloadError'
  }
}

/**
 * RFC 3339, second precision, always UTC.
 *
 * The persisted `respondedAt` arrives as a `Date` from HANA and as an ISO string
 * from SQLite, so both are normalized here rather than in two call sites. The
 * milliseconds are dropped because the verified runtime evidence shows SAP
 * storing the value to the second — `2026-09-20T03:08:45Z` — and a sender that
 * sends more precision than the receiver keeps would make an idempotent replay
 * look like a content change to anything comparing the two.
 */
export function toRfc3339(value: string | Date | null | undefined): string {
  if (value == null) {
    throw new PayloadError('MISSING_RESPONDED_AT', 'respondedAt is required and was not persisted.')
  }

  const date = value instanceof Date ? value : new Date(value)
  if (Number.isNaN(date.getTime())) {
    throw new PayloadError('INVALID_RESPONDED_AT', `respondedAt "${String(value)}" is not a valid timestamp.`)
  }

  return `${date.toISOString().slice(0, 19)}Z`
}

/**
 * One persisted response, as the frozen payload.
 *
 * Response identity, version, decision, date, reason and timestamp come from the
 * immutable row; the source identity triple, the delivery and the portal order
 * come from the order it points at; the supplier code comes from the supplier
 * association. Nothing is defaulted, derived or invented — a row that cannot
 * supply a mandatory field is a `PayloadError`, not a payload with a guess in
 * it, because a guess would be posted to SAP and applied.
 */
export function buildSupplierResponsePayload(row: ResponseRow, order: ResponseOrder): SupplierResponsePayload {
  if (!row.responseId) {
    throw new PayloadError('MISSING_RESPONSE_ID', `Response row ${row.ID} carries no responseId.`)
  }
  if (!order) {
    throw new PayloadError('ORDER_NOT_FOUND', `Response ${row.responseId} points at no readable order.`)
  }
  if (!order.supplierCode) {
    throw new PayloadError('MISSING_SUPPLIER_CODE', `Order ${order.ID} resolves to no supplier code.`)
  }

  const decision = row.decision
  if (decision !== 'ACCEPTED' && decision !== 'REJECTED') {
    throw new PayloadError('UNKNOWN_DECISION', `Response ${row.responseId} carries decision "${decision}".`)
  }

  const estimatedDeliveryDate = row.estimatedDeliveryDate ?? null
  const reason = row.reason ?? null

  // The contract's own two content rules, checked before the payload leaves
  // rather than after SAP refuses it. A rejection with no reason and an
  // acceptance carrying one are both malformed, and both would be a 400 from
  // the iFlow that told us nothing a local check could not have told us first.
  if (decision === 'REJECTED') {
    if (!reason) {
      throw new PayloadError('MISSING_REJECTION_REASON', `Rejection ${row.responseId} carries no reason.`)
    }
    if (estimatedDeliveryDate) {
      throw new PayloadError(
        'REJECTION_CARRIES_DATE',
        `Rejection ${row.responseId} carries an estimatedDeliveryDate, which the contract forbids.`
      )
    }
  }

  return {
    schemaVersion: SCHEMA_VERSION,
    responseId: row.responseId,
    sourceSystem: order.sourceSystem,
    sourceOrderId: order.sourceOrderId,
    sourceRevision: order.sourceRevision,
    deliveryId: order.deliveryId,
    portalOrderId: order.ID,
    supplierCode: order.supplierCode,
    responseVersion: row.version,
    decision,
    // A rejection has already been proven to carry no date; an acceptance with
    // no date means "unknown", which the contract represents as null.
    estimatedDeliveryDate: decision === 'REJECTED' ? null : estimatedDeliveryDate,
    reason: decision === 'REJECTED' ? reason : null,
    respondedAt: toRfc3339(row.respondedAt)
  }
}

/** What one attempt did to the outbox row. */
export type DeliveryState = 'PENDING' | 'DELIVERED' | 'FAILED' | 'UNKNOWN'

/** What the transport observed. `answered` and `status` are not the same fact. */
export interface TransportResult {
  /** False for a timeout, a DNS failure or a socket error: no HTTP answer at all. */
  answered: boolean
  status?: number
  /** A short safe reason. Never a body, a header or a credential. */
  detail?: string
}

/**
 * The transport outcome, as a delivery state.
 *
 * This is the ABAP coordinator's `classify` method read in the other direction,
 * and it is the same table on purpose: API_CONTRACTS.md's error policy governs
 * both legs, and two systems disagreeing about what a 502 means is how an outbox
 * mints a second delivery for something the receiver already committed.
 *
 * The one asymmetry is success. Outbound, CAP answers 201 or 200; inbound, the
 * verified Cloud Integration route answers 204. So the rule here is the whole
 * 2xx class rather than an enumeration — the contract's own wording is "any 2xx
 * response from CI means DELIVERED", and hard-coding 204 would turn a harmless
 * iFlow change into a false failure on a response SAP had already applied.
 */
export function classify(result: TransportResult): DeliveryState {
  // A timeout never proves non-delivery. SAP may already have applied it, so
  // the row must stay replayable under the SAME responseId. RAP's idempotency
  // is what makes that safe, and it is runtime-proven.
  if (!result.answered) return 'UNKNOWN'

  const status = result.status ?? 0

  if (status >= 200 && status < 300) return 'DELIVERED'

  switch (status) {
    // Deterministic refusals. Nothing about replaying an unchanged payload
    // would change any of these answers, so they are terminal for this row and
    // need a human, not a retry. 409 in particular is NOT success: it means the
    // same identity was reused for different content, or the version conflicts.
    case 400:
    case 401:
    case 403:
    case 404:
    case 409:
    case 412:
    case 413:
      return 'FAILED'

    // Congestion and transient upstream failure. The row returns to PENDING so
    // a later flush may pick it up; nothing about the supplier's decision moves.
    case 429:
    case 502:
    case 503:
      return 'PENDING'

    // Ambiguous: the receiver may have committed before failing.
    case 500:
    case 504:
      return 'UNKNOWN'

    default:
      // Not in the contract's table. Split by class rather than guessed, which
      // is exactly what the ABAP side does: a 5xx may have been delivered and
      // so replays, anything else was an answered refusal.
      return status >= 500 ? 'UNKNOWN' : 'FAILED'
  }
}

/** The one-line safe diagnosis persisted in `lastError`. */
export function describe(result: TransportResult): string | null {
  if (!result.answered) return `NO_ANSWER: ${result.detail ?? 'the request produced no HTTP response'}`.slice(0, 255)
  if (result.status !== undefined && result.status >= 200 && result.status < 300) return null
  return `HTTP ${result.status ?? 'unknown'}: ${result.detail ?? 'the receiver refused the request'}`.slice(0, 255)
}

/**
 * Phase 7.3 — why an attempt ended as it did, for attempt history.
 *
 * A different question from `classify`, and deliberately a separate function:
 * `classify` answers what the row's durable state becomes, this answers the
 * reason. The two are stored side by side so a `FAILED` caused by a refusal can
 * be told from a `FAILED` caused by a payload that could not be built.
 *
 * `PAYLOAD` is never produced here. A payload failure happens before there is a
 * `TransportResult` at all, so the sender supplies that category directly.
 *
 * `NO_ANSWER` deliberately does not say whether the request was sent. Splitting
 * pre-send from ambiguous post-send is Phase 7.4 work, and a category that
 * claimed to know today would be claiming more than the transport reports.
 */
export type AttemptErrorCategory = 'NONE' | 'REFUSED' | 'TRANSIENT' | 'AMBIGUOUS' | 'NO_ANSWER' | 'PAYLOAD'

export function categorise(result: TransportResult): AttemptErrorCategory {
  if (!result.answered) return 'NO_ANSWER'

  const status = result.status ?? 0

  if (status >= 200 && status < 300) return 'NONE'

  switch (status) {
    case 400:
    case 401:
    case 403:
    case 404:
    case 409:
    case 412:
    case 413:
      return 'REFUSED'

    case 429:
    case 502:
    case 503:
      return 'TRANSIENT'

    case 500:
    case 504:
      return 'AMBIGUOUS'

    default:
      // The same split `classify` makes, for the same reason: an unlisted 5xx
      // may have been delivered, anything else was an answered refusal.
      return status >= 500 ? 'AMBIGUOUS' : 'REFUSED'
  }
}
