import { createHash } from 'node:crypto'
import { formatDecimal, multiplyRounded, parseDecimal } from './decimal'

/**
 * Validation and normalization for the Phase 4.3 ingestion boundary.
 *
 * Everything here checks the *integration contract*: that the message is a
 * well-formed, internally consistent, mappable snapshot. None of it re-decides
 * anything SAP already decided. Whether an order may be submitted, approved or
 * cancelled is RAP's business and stays there (ADR-004); by the time a delivery
 * reaches this boundary those questions are settled and the portal's only job
 * is to refuse a message it cannot faithfully store.
 */

/** Scales fixed by the CAP persistence model in docs/architecture/domain-model.md. */
export const AMOUNT_SCALE = 2
export const QUANTITY_SCALE = 3
export const PRICE_SCALE = 4

/** "Initial currency support is EUR only" and the contract's EA → PCE mapping. */
export const SUPPORTED_CURRENCIES = ['EUR']
export const SUPPORTED_UNITS = ['PCE']

/** "Proposed initial bound: 100 items ... enforce before expensive processing." */
export const MAX_LINES = 100

const SUPPORTED_SCHEMA_MAJOR = '1'
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export interface ValidationFailure {
  code: string
  message: string
}

export interface NormalizedLine {
  sourceItemId: string
  lineNumber: number
  productCode: string
  description: string | null
  quantity: string
  uom: string
  unitPrice: string
  currency: string
  lineAmount: string
}

export interface NormalizedDelivery {
  deliveryId: string
  schemaVersion: string
  sourceSystem: string
  sourceOrderId: string
  sourceRevision: number
  externalOrderNumber: string | null
  supplierCode: string
  currency: string
  totalAmount: string
  lines: NormalizedLine[]
}

function fail(code: string, message: string): ValidationFailure {
  return { code, message }
}

function text(value: unknown): string | null {
  return typeof value === 'string' && value.trim() !== '' ? value.trim() : null
}

/**
 * Validates the inbound payload and returns it in canonical form, or the first
 * contract violation found. Order matters: identity and schema are checked
 * before content, so an unparseable message never reaches arithmetic.
 */
export function normalizeDelivery(payload: any): NormalizedDelivery | ValidationFailure {
  if (!payload || typeof payload !== 'object') {
    return fail('INVALID_PAYLOAD', 'The request body is not a JSON object.')
  }

  const schemaVersion = text(payload.schemaVersion)
  if (!schemaVersion || schemaVersion.split('.')[0] !== SUPPORTED_SCHEMA_MAJOR) {
    return fail(
      'SCHEMA_VERSION_UNSUPPORTED',
      `Unsupported schemaVersion "${payload.schemaVersion}". This endpoint accepts major version ${SUPPORTED_SCHEMA_MAJOR}.`
    )
  }

  const deliveryId = text(payload.deliveryId)
  if (!deliveryId || !UUID.test(deliveryId)) {
    return fail('MISSING_DELIVERY_ID', 'deliveryId is required and must be a canonical UUID.')
  }

  const source = payload.source
  const sourceSystem = source ? text(source.system) : null
  const sourceOrderId = source ? text(source.orderId) : null
  const sourceRevision = source?.revision

  if (!sourceSystem) {
    return fail('INVALID_SOURCE_IDENTITY', 'source.system is required.')
  }
  if (!sourceOrderId || !UUID.test(sourceOrderId)) {
    return fail('INVALID_SOURCE_IDENTITY', 'source.orderId is required and must be a canonical UUID.')
  }
  if (!Number.isInteger(sourceRevision) || sourceRevision < 1) {
    return fail('INVALID_SOURCE_IDENTITY', 'source.revision is required and must be a positive integer.')
  }

  const supplierCode = text(payload.supplierCode)
  if (!supplierCode) {
    return fail('MISSING_SUPPLIER_CODE', 'supplierCode is required.')
  }

  const currency = text(payload.amount?.currency)
  if (!currency || !SUPPORTED_CURRENCIES.includes(currency)) {
    return fail(
      'UNSUPPORTED_CURRENCY',
      `Unsupported currency "${payload.amount?.currency}". Supported: ${SUPPORTED_CURRENCIES.join(', ')}.`
    )
  }

  const totalAmount = parseDecimal(payload.amount?.value, AMOUNT_SCALE)
  if (totalAmount === null) {
    return fail(
      'INVALID_DECIMAL',
      `amount.value "${payload.amount?.value}" is not a plain decimal with at most ${AMOUNT_SCALE} fractional digits.`
    )
  }

  const rawLines = payload.lines
  if (!Array.isArray(rawLines) || rawLines.length === 0) {
    return fail('NO_LINES', 'A delivery must contain at least one line.')
  }
  if (rawLines.length > MAX_LINES) {
    return fail('TOO_MANY_LINES', `A delivery may contain at most ${MAX_LINES} lines; received ${rawLines.length}.`)
  }

  const lines: NormalizedLine[] = []
  const seenLineNumbers = new Set<number>()
  const seenItemIds = new Set<string>()
  let summed = 0n

  for (const raw of rawLines) {
    const lineNumber = raw?.lineNumber
    if (!Number.isInteger(lineNumber) || lineNumber < 1) {
      return fail('INVALID_LINE_NUMBER', `lineNumber "${raw?.lineNumber}" must be a positive integer.`)
    }
    if (seenLineNumbers.has(lineNumber)) {
      return fail('DUPLICATE_LINE_NUMBER', `lineNumber ${lineNumber} appears more than once in this delivery.`)
    }
    seenLineNumbers.add(lineNumber)

    const sourceItemId = text(raw.sourceItemId)
    if (!sourceItemId || !UUID.test(sourceItemId)) {
      return fail('INVALID_SOURCE_ITEM_ID', `Line ${lineNumber}: sourceItemId is required and must be a canonical UUID.`)
    }
    if (seenItemIds.has(sourceItemId)) {
      return fail('DUPLICATE_SOURCE_ITEM_ID', `Line ${lineNumber}: sourceItemId ${sourceItemId} appears more than once.`)
    }
    seenItemIds.add(sourceItemId)

    const productCode = text(raw.product?.code)
    if (!productCode) {
      return fail('MISSING_PRODUCT_CODE', `Line ${lineNumber}: product.code is required.`)
    }

    const unit = text(raw.orderedQuantity?.unit)
    if (!unit || !SUPPORTED_UNITS.includes(unit)) {
      return fail(
        'UNSUPPORTED_UNIT',
        `Line ${lineNumber}: unsupported unit "${raw.orderedQuantity?.unit}". Supported: ${SUPPORTED_UNITS.join(', ')}.`
      )
    }

    const quantity = parseDecimal(raw.orderedQuantity?.value, QUANTITY_SCALE)
    if (quantity === null) {
      return fail(
        'INVALID_DECIMAL',
        `Line ${lineNumber}: orderedQuantity.value "${raw.orderedQuantity?.value}" is not a plain decimal with at most ${QUANTITY_SCALE} fractional digits.`
      )
    }
    if (quantity <= 0n) {
      return fail('INVALID_QUANTITY', `Line ${lineNumber}: orderedQuantity.value must be greater than zero.`)
    }

    const lineCurrency = text(raw.unitPrice?.currency)
    if (lineCurrency !== currency) {
      return fail(
        'LINE_CURRENCY_MISMATCH',
        `Line ${lineNumber}: unitPrice.currency "${raw.unitPrice?.currency}" does not match the header currency "${currency}".`
      )
    }

    const unitPrice = parseDecimal(raw.unitPrice?.value, PRICE_SCALE)
    if (unitPrice === null) {
      return fail(
        'INVALID_DECIMAL',
        `Line ${lineNumber}: unitPrice.value "${raw.unitPrice?.value}" is not a plain decimal with at most ${PRICE_SCALE} fractional digits.`
      )
    }
    if (unitPrice < 0n) {
      return fail('INVALID_PRICE', `Line ${lineNumber}: unitPrice.value must not be negative.`)
    }

    const lineAmount = parseDecimal(raw.lineAmount, AMOUNT_SCALE)
    if (lineAmount === null) {
      return fail(
        'INVALID_DECIMAL',
        `Line ${lineNumber}: lineAmount "${raw.lineAmount}" is not a plain decimal with at most ${AMOUNT_SCALE} fractional digits.`
      )
    }

    const expected = multiplyRounded(quantity, QUANTITY_SCALE, unitPrice, PRICE_SCALE, AMOUNT_SCALE)
    if (expected !== lineAmount) {
      return fail(
        'LINE_AMOUNT_MISMATCH',
        `Line ${lineNumber}: lineAmount ${formatDecimal(lineAmount, AMOUNT_SCALE)} does not match quantity x unitPrice rounded to ${AMOUNT_SCALE} decimals (${formatDecimal(expected, AMOUNT_SCALE)}).`
      )
    }

    summed += lineAmount

    lines.push({
      sourceItemId,
      lineNumber,
      productCode,
      description: text(raw.product?.description),
      quantity: formatDecimal(quantity, QUANTITY_SCALE),
      uom: unit,
      unitPrice: formatDecimal(unitPrice, PRICE_SCALE),
      currency,
      lineAmount: formatDecimal(lineAmount, AMOUNT_SCALE)
    })
  }

  if (summed !== totalAmount) {
    return fail(
      'TOTAL_AMOUNT_MISMATCH',
      `amount.value ${formatDecimal(totalAmount, AMOUNT_SCALE)} does not equal the sum of the line amounts (${formatDecimal(summed, AMOUNT_SCALE)}).`
    )
  }

  lines.sort((a, b) => a.lineNumber - b.lineNumber)

  return {
    deliveryId,
    schemaVersion,
    sourceSystem,
    sourceOrderId,
    sourceRevision,
    externalOrderNumber: source ? text(source.orderNumber) : null,
    supplierCode,
    currency,
    totalAmount: formatDecimal(totalAmount, AMOUNT_SCALE),
    lines
  }
}

export function isFailure(value: NormalizedDelivery | ValidationFailure): value is ValidationFailure {
  return 'code' in value
}

/**
 * Hash of the delivery's immutable content, used to tell an exact replay from a
 * conflicting reuse of the same deliveryId.
 *
 * The contract requires normalizing "known fields, decimal representation and
 * object member ordering before hashing", because "raw JSON byte order alone is
 * not a meaningful equality check". `normalizeDelivery` has already fixed the
 * decimal representation and sorted the lines; building the hashed object with
 * an explicit key order fixes the rest. Two byte-different but business-identical
 * messages therefore hash the same, which is what makes a replay a replay.
 */
export function deliveryHash(delivery: NormalizedDelivery): string {
  const canonical = [
    delivery.schemaVersion,
    delivery.deliveryId,
    delivery.sourceSystem,
    delivery.sourceOrderId,
    String(delivery.sourceRevision),
    delivery.externalOrderNumber ?? '',
    delivery.supplierCode,
    delivery.currency,
    delivery.totalAmount,
    ...delivery.lines.map(line => [
      String(line.lineNumber),
      line.sourceItemId,
      line.productCode,
      line.description ?? '',
      line.quantity,
      line.uom,
      line.unitPrice,
      line.currency,
      line.lineAmount
    ].join(''))
  ].join('')

  return createHash('sha256').update(canonical, 'utf8').digest('hex')
}
