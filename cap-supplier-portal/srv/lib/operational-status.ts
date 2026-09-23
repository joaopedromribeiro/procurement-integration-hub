/** Phase 7.7 read-only operational status for the inbound delivery leg. */

import {
  SupplierResponseDeliveries,
  SupplierResponseDeliveryAttempts
} from '#cds-models/pih/portal'
import { retryEligibility } from './retry-policy'

export interface DeliveryOperationalRow {
  ID: string
  responseId: string
  order_ID: string
  version: number
  state: string
  attempts: number
  nextAttemptAt?: string | Date | null
  retryWindowStartedAt?: string | Date | null
  leaseOwner?: string | null
  leaseExpiresAt?: string | Date | null
  lastCorrelationId?: string | null
  lastAttemptAt?: string | Date | null
}

export interface OperationalStatus {
  observedAt: string
  stateCensus: Record<string, number>
  beforeDue: number
  retryExhausted: number
  retryWindowBlocked: number
  liveLeases: number
  staleLeases: number
  unknown: number
  historyCount: number
  deliveries: Array<DeliveryOperationalRow & { historyCount: number }>
}

function timestamp(value: string | Date | null | undefined): number | null {
  if (value == null) return null
  const parsed = value instanceof Date ? value : new Date(value)
  return Number.isNaN(parsed.getTime()) ? null : parsed.getTime()
}

/** Reads diagnostics only. There is deliberately no UPDATE, INSERT or DELETE. */
export async function readOperationalStatus(now: Date = new Date()): Promise<OperationalStatus> {
  if (Number.isNaN(now.getTime())) throw new Error('now must be a valid Date.')

  const deliveries = await SELECT.from(SupplierResponseDeliveries).orderBy('createdAt', 'version') as any[]
  const attempts = await SELECT.from(SupplierResponseDeliveryAttempts).orderBy('startedAt', 'attemptNumber') as any[]
  const histories = new Map<string, number>()
  for (const attempt of attempts) {
    histories.set(attempt.delivery_ID, (histories.get(attempt.delivery_ID) ?? 0) + 1)
  }

  const result: OperationalStatus = {
    observedAt: now.toISOString(), stateCensus: {}, beforeDue: 0,
    retryExhausted: 0, retryWindowBlocked: 0, liveLeases: 0,
    staleLeases: 0, unknown: 0, historyCount: attempts.length, deliveries: []
  }

  for (const row of deliveries as DeliveryOperationalRow[]) {
    const state = row.state || 'PENDING'
    result.stateCensus[state] = (result.stateCensus[state] ?? 0) + 1
    if (state === 'UNKNOWN') result.unknown++

    if (state === 'PENDING') {
      const eligibility = retryEligibility(row, now)
      if (eligibility === 'BEFORE_DUE') result.beforeDue++
      else if (eligibility === 'RETRY_EXHAUSTED') result.retryExhausted++
      else if (eligibility === 'RETRY_WINDOW_BLOCKED') result.retryWindowBlocked++
    } else if (state === 'IN_FLIGHT') {
      const expiry = timestamp(row.leaseExpiresAt)
      if (expiry != null && expiry > now.getTime()) result.liveLeases++
      else result.staleLeases++
    }

    result.deliveries.push({ ...row, historyCount: histories.get(row.ID) ?? 0 })
  }

  return result
}
