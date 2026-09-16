/**
 * Decimal handling for the integration boundary.
 *
 * API_CONTRACTS.md transports monetary and quantity values as decimal strings
 * with "no scientific notation", and requires precision, scale and bounds to be
 * enforced from the domain model. Parsing into scaled BigInt keeps every check
 * and every product exact: binary floating point cannot represent 750.0000 or
 * 120.5000 exactly, and money compared with `===` after a float multiply is a
 * bug waiting for the first awkward price.
 */

/** Strictly `[-]digits[.digits]`. Rejects `1e3`, spaces, `+1`, `.5` and ``. */
const DECIMAL = /^-?\d+(\.\d+)?$/

/**
 * Parses a decimal string into an integer scaled by 10^scale.
 * Returns null when the text is not a plain decimal or carries more fractional
 * digits than the target scale allows.
 */
export function parseDecimal(text: unknown, scale: number): bigint | null {
  if (typeof text !== 'string' || !DECIMAL.test(text)) return null

  const negative = text.startsWith('-')
  const [whole, fraction = ''] = (negative ? text.slice(1) : text).split('.')
  if (fraction.length > scale) return null

  const scaled = BigInt(whole + fraction.padEnd(scale, '0'))
  return negative ? -scaled : scaled
}

/** Renders a scaled integer back as a canonical decimal string. */
export function formatDecimal(value: bigint, scale: number): string {
  const negative = value < 0n
  const digits = (negative ? -value : value).toString().padStart(scale + 1, '0')
  const whole = digits.slice(0, digits.length - scale)
  const fraction = scale === 0 ? '' : `.${digits.slice(digits.length - scale)}`
  return `${negative ? '-' : ''}${whole}${fraction}`
}

/**
 * Multiplies two scaled integers and rounds the result half up to `toScale`.
 *
 * The domain model's rounding rule is "calculate each item at sufficient
 * precision, round half up to two decimals, then sum rounded items", so line
 * amounts are rounded individually and the header is the sum of those.
 */
export function multiplyRounded(
  left: bigint, leftScale: number,
  right: bigint, rightScale: number,
  toScale: number
): bigint {
  const product = left * right
  const drop = leftScale + rightScale - toScale
  if (drop <= 0) return product * 10n ** BigInt(-drop)

  const divisor = 10n ** BigInt(drop)
  const negative = product < 0n
  const magnitude = negative ? -product : product
  const quotient = magnitude / divisor
  const remainder = magnitude % divisor
  const rounded = remainder * 2n >= divisor ? quotient + 1n : quotient
  return negative ? -rounded : rounded
}
