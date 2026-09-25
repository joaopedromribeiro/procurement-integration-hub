// Local Phase 9.2 model only. No SAP, broker, transport, or CAP connection.
export const EVENT_TYPE = 'com.pih.purchaseorder.deliveryrequested.v1';

export type DeliveryEvent = {
  specversion: '1.0';
  id: string;
  source: string;
  type: typeof EVENT_TYPE;
  time: string;
  subject: string;
  data: {
    purchaseOrderId: string;
    orderRevision: number;
    deliveryId: string;
    payloadHash: string;
  };
};

export type DeliveryRecord = {
  purchaseOrderId: string;
  orderRevision: number;
  deliveryId: string;
  payloadHash: string;
  state: 'READY' | 'IN_FLIGHT' | 'COMPLETED';
};

export type Outcome =
  | 'DISPATCH'
  | 'DUPLICATE'
  | 'ALREADY_COMPLETED'
  | 'STALE'
  | 'CONFLICT'
  | 'UNKNOWN_DELIVERY'
  | 'INVALID_EVENT'
  | 'UNSUPPORTED_VERSION'
  | 'AMBIGUOUS';

export type ConsumerResult = { outcome: Outcome; ack: boolean; quarantine: boolean };

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const hash = /^[0-9a-f]{64}$/i;
const keysAre = (value: Record<string, unknown>, keys: string[]) =>
  Object.keys(value).sort().join(',') === [...keys].sort().join(',');

function isObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function validate(input: unknown): { event?: DeliveryEvent; outcome?: Outcome } {
  if (!isObject(input) || !keysAre(input, ['specversion', 'id', 'source', 'type', 'time', 'subject', 'data'])) {
    return { outcome: 'INVALID_EVENT' };
  }
  if (input.specversion !== '1.0' || input.type !== EVENT_TYPE) {
    return { outcome: 'UNSUPPORTED_VERSION' };
  }
  if (!isObject(input.data) || !keysAre(input.data, ['purchaseOrderId', 'orderRevision', 'deliveryId', 'payloadHash'])) {
    return { outcome: 'INVALID_EVENT' };
  }
  const data = input.data;
  if (typeof input.id !== 'string' || !uuid.test(input.id) ||
      typeof input.source !== 'string' || input.source.length === 0 ||
      typeof input.time !== 'string' || !/^\d{4}-\d{2}-\d{2}T.*Z$/.test(input.time) || Number.isNaN(Date.parse(input.time)) ||
      typeof input.subject !== 'string' || !uuid.test(input.subject) ||
      typeof data.purchaseOrderId !== 'string' || !uuid.test(data.purchaseOrderId) ||
      input.subject !== data.purchaseOrderId ||
      typeof data.orderRevision !== 'number' || !Number.isSafeInteger(data.orderRevision) || data.orderRevision < 1 ||
      typeof data.deliveryId !== 'string' || !uuid.test(data.deliveryId) ||
      typeof data.payloadHash !== 'string' || !hash.test(data.payloadHash)) {
    return { outcome: 'INVALID_EVENT' };
  }
  return { event: input as DeliveryEvent };
}

// This registry represents an already committed DeliveryIntent census supplied by
// the authoritative business system. The consumer never creates an intent.
export class LocalDeliveryRegistry {
  private readonly records = new Map<string, DeliveryRecord>();
  private readonly latestRevision = new Map<string, number>();
  private readonly seenPublicationIds = new Map<string, string>();

  constructor(records: DeliveryRecord[]) {
    for (const record of records) {
      if (this.records.has(record.deliveryId)) throw new Error('Duplicate authoritative deliveryId');
      this.records.set(record.deliveryId, { ...record });
      this.latestRevision.set(record.purchaseOrderId,
        Math.max(this.latestRevision.get(record.purchaseOrderId) ?? 0, record.orderRevision));
    }
  }

  get(deliveryId: string): Readonly<DeliveryRecord> | undefined {
    const record = this.records.get(deliveryId);
    return record && { ...record };
  }

  newestRevision(purchaseOrderId: string): number {
    return this.latestRevision.get(purchaseOrderId) ?? 0;
  }

  publication(deliveryEventId: string): string | undefined {
    return this.seenPublicationIds.get(deliveryEventId);
  }

  markInFlight(deliveryId: string, eventId: string): void {
    const record = this.records.get(deliveryId);
    if (!record || record.state !== 'READY') throw new Error('Delivery is not ready');
    record.state = 'IN_FLIGHT';
    this.seenPublicationIds.set(eventId, deliveryId);
  }

  // Simulates a durable completion observed from the existing business authority.
  complete(deliveryId: string): void {
    const record = this.records.get(deliveryId);
    if (!record || record.state !== 'IN_FLIGHT') throw new Error('Delivery is not in flight');
    record.state = 'COMPLETED';
  }
}

const result = (outcome: Outcome, ack: boolean, quarantine = false): ConsumerResult =>
  ({ outcome, ack, quarantine });

export function consumeEvent(
  input: unknown,
  registry: LocalDeliveryRegistry,
  dispatch: (deliveryId: string) => void,
): ConsumerResult {
  const checked = validate(input);
  if (!checked.event) return result(checked.outcome!, false, true);
  const event = checked.event;
  const data = event.data;
  const record = registry.get(data.deliveryId);
  if (!record) return result('UNKNOWN_DELIVERY', false, true);
  if (record.purchaseOrderId !== data.purchaseOrderId ||
      record.orderRevision !== data.orderRevision ||
      record.payloadHash.toLowerCase() !== data.payloadHash.toLowerCase()) {
    return result('CONFLICT', false, true);
  }
  if (data.orderRevision < registry.newestRevision(data.purchaseOrderId)) {
    return result('STALE', true);
  }
  const previousDeliveryId = registry.publication(event.id);
  if (previousDeliveryId && previousDeliveryId !== data.deliveryId) return result('CONFLICT', false, true);
  if (record.state === 'COMPLETED') {
    return result(previousDeliveryId ? 'DUPLICATE' : 'ALREADY_COMPLETED', true);
  }
  if (record.state === 'IN_FLIGHT') {
    // No safe ACK until the authoritative result is known.
    return result('DUPLICATE', false);
  }
  registry.markInFlight(data.deliveryId, event.id);
  try {
    dispatch(data.deliveryId);
  } catch {
    // The callback may have sent the business effect. Never dispatch again blindly.
    return result('AMBIGUOUS', false);
  }
  return result('DISPATCH', registry.get(data.deliveryId)?.state === 'COMPLETED');
}
