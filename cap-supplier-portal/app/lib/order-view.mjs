/**
 * Phase 4.5 — presentation logic for the supplier UI.
 *
 * Pure functions only: no DOM, no fetch, no state. The browser module imports
 * them to build its screens, and the test suite imports the same file to check
 * them, so what is tested is what runs.
 *
 * None of this is a business rule. Which actions a status permits is decided by
 * `SupplierService`; the copy here only decides which buttons to draw, and a
 * button the backend would refuse is refused by the backend anyway.
 */

/** Page size for the order list. See the Phase 4.5 pagination contract. */
export const PAGE_SIZE = 20

/** The server clamps to this; the UI never asks for more. */
export const MAX_PAGE_SIZE = 100

/**
 * Which controls an order may show.
 *
 * A mirror of the Phase 4.4 lifecycle, kept deliberately thin: `RECEIVED` can be
 * answered, an `ACCEPTED` order can have its date revised, and a `REJECTED`
 * order is terminal. Getting this wrong hides or offers a button; it cannot
 * change what the service allows.
 */
export function actionsFor(order) {
  const status = order?.status
  return {
    canAccept: status === 'RECEIVED',
    canReject: status === 'RECEIVED',
    canUpdateDate: status === 'ACCEPTED'
  }
}

function newResponseId() {
  return globalThis.crypto.randomUUID()
}

/**
 * Every command carries a fresh `responseId` and the version the client
 * currently believes is correct.
 *
 * `expectedResponseVersion` is read from the loaded order and never typed by a
 * user: it is a precondition the client observed, not an input it chooses. The
 * `responseId` is generated per command, so a retry of the *same* user action
 * reuses its id and is recognised as a replay, while a new action gets a new id.
 */
function baseCommand(order, responseId = newResponseId()) {
  return { responseId, expectedResponseVersion: order.responseVersion }
}

export function acceptPayload(order, estimatedDeliveryDate, responseId) {
  const payload = baseCommand(order, responseId)
  // An omitted date means unknown; it is never defaulted to today.
  if (estimatedDeliveryDate) payload.estimatedDeliveryDate = estimatedDeliveryDate
  return payload
}

export function rejectPayload(order, reason, responseId) {
  return { ...baseCommand(order, responseId), reason }
}

export function dateUpdatePayload(order, estimatedDeliveryDate, responseId) {
  return { ...baseCommand(order, responseId), estimatedDeliveryDate }
}

/** `?limit=&offset=`, the Phase 4.5 list contract. */
export function listQuery(offset = 0, limit = PAGE_SIZE) {
  return `?limit=${Math.min(limit, MAX_PAGE_SIZE)}&offset=${Math.max(0, offset)}`
}

/** A full page implies there may be another; a short page is the last one. */
export function hasNextPage(rows, limit = PAGE_SIZE) {
  return Array.isArray(rows) && rows.length === limit
}

/**
 * Turns any failure into something a supplier can read.
 *
 * The service answers with `{ error: { code, message, correlationId } }`, so the
 * message is shown as written — it was composed for this audience. Anything
 * else gets a generic line, because an unexpected failure's text is not meant
 * for a user and may not be safe to show.
 *
 * `refresh` is the one piece of behaviour here: a stale version means somebody
 * else moved the order on, so the screen must be reloaded before the supplier
 * decides again. The command is never retried automatically, because a retry
 * with a new id could apply a decision the supplier no longer intends.
 */
export function describeError(status, body) {
  const code = body?.error?.code
  const message = body?.error?.message

  if (status === 401) {
    return { code: 'UNAUTHENTICATED', message: 'Sign in to continue.', refresh: false }
  }
  if (status === 403 && !message) {
    return { code: 'FORBIDDEN', message: 'This user has no supplier access.', refresh: false }
  }
  if (status === 404 && !message) {
    return { code: 'ORDER_NOT_FOUND', message: 'That order is not available to you.', refresh: false }
  }
  if (code === 'STALE_RESPONSE_VERSION') {
    return {
      code,
      message: `${message} Reloading the order so you can review the current state.`,
      refresh: true
    }
  }
  if (code) {
    return { code, message, refresh: false }
  }

  return {
    code: `HTTP_${status}`,
    message: 'The portal could not complete that request. Please try again.',
    refresh: false
  }
}

/** Money and quantities arrive as decimal strings and are shown unchanged. */
export function formatAmount(value, currency) {
  if (value == null) return ''
  return currency ? `${value} ${currency}` : String(value)
}

export function formatQuantity(value, uom) {
  if (value == null) return ''
  return uom ? `${value} ${uom}` : String(value)
}

export function formatDate(value) {
  return value ?? '—'
}
