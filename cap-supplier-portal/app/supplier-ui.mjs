import {
  PAGE_SIZE,
  acceptPayload,
  actionsFor,
  dateUpdatePayload,
  describeError,
  formatAmount,
  formatDate,
  formatQuantity,
  hasNextPage,
  listQuery,
  rejectPayload
} from './lib/order-view.mjs'
import * as auth from './auth.mjs'

/**
 * Phase 4.5 — the supplier UI.
 *
 * Every call goes to `SupplierService` and nowhere else. The page holds no
 * business rule: it shows what the service returns, sends the three documented
 * commands, and reloads. Anything it gets wrong is still refused by the backend.
 */

const SERVICE = '/rest/supplier/v1'

const el = id => document.getElementById(id)

/** Authentication is selected by the bundled auth module: local mock or XSUAA session. */
const session = auth.session

/** One place where the UI talks to the service, so one place handles failure. */
async function call(path, options = {}) {
  const response = await fetch(`${SERVICE}${path}`, {
    ...options,
    headers: { Accept: 'application/json', ...(options.headers ?? {}), ...auth.headers() }
  })

  const body = response.status === 204 ? null : await response.json().catch(() => null)
  if (!response.ok) throw Object.assign(new Error('request failed'), { failure: describeError(response.status, body) })
  return body
}

const state = { offset: 0, order: null, items: [] }

// ------------------------------------------------------------------ rendering

function say(text, kind = 'info') {
  const box = el('message')
  box.textContent = text
  box.className = `message ${kind}`
  box.hidden = !text
}

function show(view) {
  el('list-view').hidden = view !== 'list'
  el('detail-view').hidden = view !== 'detail'
}

function renderSession() {
  const user = session.get()
  el('signin').hidden = auth.mode !== 'mock' || Boolean(user)
  el('session').hidden = auth.mode === 'mock' && !user
  el('signout').hidden = auth.mode !== 'mock'
  if (user) el('current-user').textContent = auth.displayName(user)
}

function renderList(orders) {
  const body = el('orders').querySelector('tbody')
  body.replaceChildren()

  for (const order of orders) {
    const row = document.createElement('tr')
    const cells = [
      order.externalOrderNumber,
      order.status,
      formatAmount(order.totalAmount, order.currency),
      formatDate(order.estimatedDeliveryDate),
      String(order.responseVersion)
    ]
    for (const value of cells) {
      const cell = document.createElement('td')
      cell.textContent = value
      row.append(cell)
    }

    const action = document.createElement('td')
    const open = document.createElement('button')
    open.type = 'button'
    open.textContent = 'Open'
    // The portal id is routing only: it is never displayed as a column.
    open.addEventListener('click', () => openOrder(order.portalOrderId))
    action.append(open)
    row.append(action)

    body.append(row)
  }

  el('page-label').textContent = orders.length
    ? `Showing ${state.offset + 1}–${state.offset + orders.length}`
    : 'No orders'
  el('prev-page').disabled = state.offset === 0
  el('next-page').disabled = !hasNextPage(orders, PAGE_SIZE)
}

function renderDetail() {
  const order = state.order
  el('detail-number').textContent = order.externalOrderNumber ?? '(no number)'

  const header = el('detail-header')
  header.replaceChildren()
  const fields = [
    ['Status', order.status],
    ['Total', formatAmount(order.totalAmount, order.currency)],
    ['Estimated delivery date', formatDate(order.estimatedDeliveryDate)],
    ['Response version', String(order.responseVersion)]
  ]
  if (order.rejectionReason) fields.push(['Rejection reason', order.rejectionReason])

  for (const [label, value] of fields) {
    const term = document.createElement('dt')
    term.textContent = label
    const definition = document.createElement('dd')
    definition.textContent = value
    header.append(term, definition)
  }

  const body = el('items').querySelector('tbody')
  body.replaceChildren()
  for (const item of state.items) {
    const row = document.createElement('tr')
    for (const value of [
      String(item.lineNumber),
      item.productCode,
      item.description ?? '',
      formatQuantity(item.quantity, item.uom),
      formatAmount(item.unitPrice, item.currency),
      formatAmount(item.lineAmount, item.currency)
    ]) {
      const cell = document.createElement('td')
      cell.textContent = value
      row.append(cell)
    }
    body.append(row)
  }

  const allowed = actionsFor(order)
  el('accept-box').hidden = !auth.mutationsEnabled || !allowed.canAccept
  el('reject-box').hidden = !auth.mutationsEnabled || !allowed.canReject
  el('date-box').hidden = !auth.mutationsEnabled || !allowed.canUpdateDate
}

// ------------------------------------------------------------------- loading

async function loadList() {
  try {
    const orders = await call(`/Orders${listQuery(state.offset)}`)
    renderList(orders)
    show('list')
    say('')
  } catch (error) {
    handle(error)
  }
}

async function openOrder(portalOrderId) {
  try {
    const [order, items] = await Promise.all([
      call(`/Orders/${portalOrderId}`),
      call(`/Orders/${portalOrderId}/items`)
    ])
    state.order = order
    state.items = items
    renderDetail()
    show('detail')
    say('')
  } catch (error) {
    handle(error)
  }
}

/**
 * Sends one command, then reloads the order from the service rather than
 * trusting the response body to be the whole truth.
 */
async function send(action, payload, success) {
  if (!auth.mutationsEnabled) return say('Supplier decisions are not enabled on this portal yet.', 'error')
  try {
    const result = await call(`/Orders/${state.order.portalOrderId}/${action}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    })
    await openOrder(result.portalOrderId)
    say(success(result), 'ok')
  } catch (error) {
    handle(error)
  }
}

/**
 * A stale version means the order moved on while this page was open. The
 * command is *not* resent: it is reloaded so the supplier decides against the
 * current state. Retrying with a new id could apply a decision nobody intends.
 */
function handle(error) {
  const failure = error.failure ?? { code: 'NETWORK', message: 'The portal is unreachable.' }
  say(`${failure.message} (${failure.code})`, 'error')

  if (failure.refresh && state.order) openOrder(state.order.portalOrderId)
  if (failure.code === 'UNAUTHENTICATED') {
    session.clear()
    renderSession()
    show('none')
  }
}

// -------------------------------------------------------------------- wiring

auth.bindControls({
  onSignIn() {
    renderSession()
    state.offset = 0
    loadList()
  },
  onSignOut() {
    state.order = null
    renderSession()
    show('none')
    say('')
  }
})

el('back').addEventListener('click', () => {
  state.order = null
  loadList()
})

el('prev-page').addEventListener('click', () => {
  state.offset = Math.max(0, state.offset - PAGE_SIZE)
  loadList()
})

el('next-page').addEventListener('click', () => {
  state.offset += PAGE_SIZE
  loadList()
})

el('accept').addEventListener('click', () => {
  const date = el('accept-date').value
  send('accept', acceptPayload(state.order, date || undefined), r =>
    `Accepted. Status ${r.status}, version ${r.responseVersion}, delivery response ${r.responseDeliveryStatus}.`)
})

el('reject').addEventListener('click', () => {
  const reason = el('reject-reason').value.trim()
  // Convenience only; the service is what actually requires a reason.
  if (!reason) return say('Enter a reason before rejecting.', 'error')
  send('reject', rejectPayload(state.order, reason), r =>
    `Rejected. Status ${r.status}, version ${r.responseVersion}.`)
})

el('update').addEventListener('click', () => {
  const date = el('update-date').value
  if (!date) return say('Choose a date first.', 'error')
  send('updateEstimatedDeliveryDate', dateUpdatePayload(state.order, date), r =>
    `Delivery date updated to ${r.estimatedDeliveryDate}, version ${r.responseVersion}.`)
})

renderSession()
if (session.get()) loadList()
