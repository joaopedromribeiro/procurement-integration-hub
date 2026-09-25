import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { consumeEvent, LocalDeliveryRegistry, type DeliveryEvent, type DeliveryRecord } from '../src/consumer.mts';

function fixture(name: string): DeliveryEvent {
  return JSON.parse(readFileSync(new URL(`../payloads/${name}.json`, import.meta.url), 'utf8')) as DeliveryEvent;
}

const original = fixture('purchase-order-delivery-requested-v1');
const oldRecord: DeliveryRecord = { ...original.data, state: 'READY' };
const newerRecord: DeliveryRecord = {
  ...oldRecord,
  orderRevision: 2,
  deliveryId: '55555555-5555-4555-8555-555555555555',
  payloadHash: 'c'.repeat(64),
};

function completeOnDispatch(registry: LocalDeliveryRegistry, calls: string[]): (id: string) => void {
  return id => { calls.push(id); registry.complete(id); };
}

test('1. first delivery event dispatches the committed identity once', () => {
  const registry = new LocalDeliveryRegistry([oldRecord]);
  const calls: string[] = [];
  assert.deepEqual(consumeEvent(original, registry, completeOnDispatch(registry, calls)),
    { outcome: 'DISPATCH', ack: true, quarantine: false });
  assert.deepEqual(calls, [original.data.deliveryId]);
  assert.equal(registry.get(original.data.deliveryId)?.state, 'COMPLETED');
});

test('2. exact duplicate publication does not dispatch again', () => {
  const registry = new LocalDeliveryRegistry([oldRecord]);
  const calls: string[] = [];
  const dispatch = completeOnDispatch(registry, calls);
  consumeEvent(original, registry, dispatch);
  assert.deepEqual(consumeEvent(fixture('duplicate-same-event'), registry, dispatch),
    { outcome: 'DUPLICATE', ack: true, quarantine: false });
  assert.equal(calls.length, 1);
});

test('3. new publication id for the same business operation is already completed', () => {
  const registry = new LocalDeliveryRegistry([oldRecord]);
  const calls: string[] = [];
  const dispatch = completeOnDispatch(registry, calls);
  consumeEvent(original, registry, dispatch);
  assert.deepEqual(consumeEvent(fixture('republished-same-delivery'), registry, dispatch),
    { outcome: 'ALREADY_COMPLETED', ack: true, quarantine: false });
  assert.equal(calls.length, 1);
});

test('4. conflicting hash, revision, or order identity is quarantined', () => {
  const registry = new LocalDeliveryRegistry([oldRecord]);
  const conflicts = [fixture('conflicting-delivery')];
  const revision = structuredClone(original);
  revision.data.orderRevision = 2;
  conflicts.push(revision);
  const order = structuredClone(original);
  order.subject = '44444444-4444-4444-8444-444444444444';
  order.data.purchaseOrderId = order.subject;
  conflicts.push(order);
  let calls = 0;
  for (const event of conflicts) {
    assert.deepEqual(consumeEvent(event, registry, () => { calls++; }),
      { outcome: 'CONFLICT', ack: false, quarantine: true });
  }
  assert.equal(calls, 0);
  assert.equal(registry.get(original.data.deliveryId)?.state, 'READY');
});

test('5. older revision is stale even when its identity exists', () => {
  const registry = new LocalDeliveryRegistry([oldRecord, newerRecord]);
  let calls = 0;
  assert.deepEqual(consumeEvent(fixture('stale-revision'), registry, () => { calls++; }),
    { outcome: 'STALE', ack: true, quarantine: false });
  assert.equal(calls, 0);
});

test('6. redelivery before ack while in flight cannot invoke dispatch twice', () => {
  const registry = new LocalDeliveryRegistry([oldRecord]);
  let calls = 0;
  const dispatch = () => { calls++; }; // Durable claim remains IN_FLIGHT.
  assert.deepEqual(consumeEvent(original, registry, dispatch),
    { outcome: 'DISPATCH', ack: false, quarantine: false });
  assert.deepEqual(consumeEvent(original, registry, dispatch),
    { outcome: 'DUPLICATE', ack: false, quarantine: false });
  assert.equal(calls, 1);
});

test('7. crash after durable success but before broker ack is safe on redelivery', () => {
  const registry = new LocalDeliveryRegistry([oldRecord]);
  const calls: string[] = [];
  const dispatch = completeOnDispatch(registry, calls);
  consumeEvent(original, registry, dispatch); // Simulated ACK is lost; state remains durable.
  assert.deepEqual(consumeEvent(original, registry, dispatch),
    { outcome: 'DUPLICATE', ack: true, quarantine: false });
  assert.equal(calls.length, 1);
});

test('8. malformed and unsupported events are quarantined without dispatch', () => {
  const registry = new LocalDeliveryRegistry([oldRecord]);
  const malformed = structuredClone(original) as DeliveryEvent & { unexpectedField?: string };
  malformed.unexpectedField = 'not-in-v1-contract';
  let calls = 0;
  assert.deepEqual(consumeEvent(malformed, registry, () => { calls++; }),
    { outcome: 'INVALID_EVENT', ack: false, quarantine: true });
  assert.deepEqual(consumeEvent(fixture('unsupported-version'), registry, () => { calls++; }),
    { outcome: 'UNSUPPORTED_VERSION', ack: false, quarantine: true });
  assert.equal(calls, 0);
});

test('9. unknown DeliveryUUID never manufactures a DeliveryIntent', () => {
  const registry = new LocalDeliveryRegistry([oldRecord]);
  const unknown = structuredClone(original);
  unknown.data.deliveryId = '44444444-4444-4444-8444-444444444444';
  let calls = 0;
  assert.deepEqual(consumeEvent(unknown, registry, () => { calls++; }),
    { outcome: 'UNKNOWN_DELIVERY', ack: false, quarantine: true });
  assert.equal(calls, 0);
  assert.equal(registry.get(unknown.data.deliveryId), undefined);
});

test('10. later revision arriving first makes an earlier arrival stale', () => {
  const registry = new LocalDeliveryRegistry([oldRecord, newerRecord]);
  const later = structuredClone(original);
  later.id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  later.data.orderRevision = 2;
  later.data.deliveryId = newerRecord.deliveryId;
  later.data.payloadHash = newerRecord.payloadHash;
  const calls: string[] = [];
  const dispatch = completeOnDispatch(registry, calls);
  assert.equal(consumeEvent(later, registry, dispatch).outcome, 'DISPATCH');
  assert.equal(consumeEvent(original, registry, dispatch).outcome, 'STALE');
  assert.deepEqual(calls, [newerRecord.deliveryId]);
});

test('ambiguous callback failure is not acknowledged or replayed blindly', () => {
  const registry = new LocalDeliveryRegistry([oldRecord]);
  let calls = 0;
  const dispatch = () => { calls++; throw new Error('simulated lost response'); };
  assert.deepEqual(consumeEvent(original, registry, dispatch),
    { outcome: 'AMBIGUOUS', ack: false, quarantine: false });
  assert.deepEqual(consumeEvent(original, registry, dispatch),
    { outcome: 'DUPLICATE', ack: false, quarantine: false });
  assert.equal(calls, 1);
});
