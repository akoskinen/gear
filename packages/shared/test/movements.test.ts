import { describe, expect, it } from 'vitest';
import { applyMovement, type ApplyContext } from '../src/movements.js';
import type { Item, Movement } from '../src/types.js';

const MIN = 60_000;
const t0 = Date.parse('2026-10-03T10:00:00Z');
const type = { minutesTo80: 80, minutes80To100: 40 };

function item(over: Partial<Item> = {}): Item {
  return {
    category: 'battery', labelCode: 'BAT-09', model: 'Lift 100 Ah', spec: {}, serial: null,
    ownerMemberId: null, homeLocationId: 'hq', locationId: 'site', holderMemberId: null,
    status: 'ready', statusReason: null, expectedBackOn: null, batteryTypeId: 'bt', firmwareVersion: null,
    cycleCount: 0, chargerSpeedFactor: null, battery: { lastReading: null, charging: null }, photos: [],
    createdAt: t0, retiredAt: null, lastMovementAt: null, ...over,
  };
}
function movement(over: Partial<Movement> = {}): Movement {
  return {
    eventId: 'ev', itemId: 'bat9', kind: 'checkout', actorMemberId: 'kiosk', subjectMemberId: 'pete',
    fromLocationId: null, toLocationId: null, fromStatus: null, toStatus: null, conditionFlags: [],
    readingPct: null, payload: {}, conflictReason: null, rejectedReason: null, recordedOffline: false,
    deviceId: null, occurredAt: t0, receivedAt: null, applied: false, appliedAt: null, ...over,
  };
}
function ctx(over: Partial<ApplyContext> = {}): ApplyContext {
  return { item: item(), movement: movement(), event: { siteLocationId: 'site', chargerSpeedFactor: 1 }, reservedForMemberId: null, batteryType: type, readyPct: 80, ...over };
}

describe('checkout', () => {
  it('sets the holder and clears the location', () => {
    const r = applyMovement(ctx());
    expect(r.rejectedReason).toBeNull();
    expect(r.conflictReason).toBeNull();
    expect(r.itemPatch).toMatchObject({ holderMemberId: 'pete', locationId: null });
    expect(r.movementPatch.fromLocationId).toBe('site');
  });

  it('flags but applies when reserved for someone else', () => {
    const r = applyMovement(ctx({ reservedForMemberId: 'manel' }));
    expect(r.conflictReason).toBe('item reserved for another rider');
    expect(r.itemPatch.holderMemberId).toBe('pete');
  });

  it('does not flag the reserved rider', () => {
    expect(applyMovement(ctx({ reservedForMemberId: 'pete' })).conflictReason).toBeNull();
  });

  it('flags a not-ready item and an item already with someone else', () => {
    expect(applyMovement(ctx({ item: item({ status: 'needs_check' }) })).conflictReason).toBe('item was needs_check at checkout');
    expect(applyMovement(ctx({ item: item({ holderMemberId: 'gina', locationId: null }) })).conflictReason).toBe('item was already with another rider');
  });

  it('force_checkout never flags', () => {
    expect(applyMovement(ctx({ movement: movement({ kind: 'force_checkout', actorMemberId: 'axel' }), reservedForMemberId: 'manel' })).conflictReason).toBeNull();
  });

  it('rejects rider-owned gear', () => {
    expect(applyMovement(ctx({ item: item({ ownerMemberId: 'pete' }) })).rejectedReason).toMatch(/rider-owned/);
  });

  it('closes an open charging session and records the take reading', () => {
    const charging = { sessionId: 's_0', startedAt: t0 - 60 * MIN, startPct: 30, speedFactor: 1, eventId: 'ev', startedBy: 'kiosk' };
    const r = applyMovement(ctx({ item: item({ battery: { lastReading: null, charging } }), movement: movement({ readingPct: 84 }) }));
    expect(r.sessionEnded).toMatchObject({ endedAt: t0, endPct: 84 });
    expect(r.readings).toEqual([{ pct: 84, at: t0, source: 'rider_take', memberId: 'pete', eventId: 'ev' }]);
    expect(r.itemPatch.battery).toMatchObject({ charging: null, lastReading: { pct: 84 } });
  });

  it('freezes the estimate when a charging battery is taken without a reading', () => {
    const charging = { sessionId: 's_0', startedAt: t0 - 60 * MIN, startPct: 30, speedFactor: 1, eventId: 'ev', startedBy: 'kiosk' };
    const r = applyMovement(ctx({ item: item({ battery: { lastReading: null, charging } }) }));
    expect(r.sessionEnded?.endPct).toBe(85);
  });
});

describe('checkin', () => {
  const held = item({ holderMemberId: 'pete', locationId: null });

  it('returns to the event site and records the reading, cycle count and charging', () => {
    const r = applyMovement(ctx({ item: held, movement: movement({ kind: 'checkin', readingPct: 30, payload: { on_charger: true } }) }));
    expect(r.conflictReason).toBeNull();
    expect(r.itemPatch).toMatchObject({ holderMemberId: null, locationId: 'site', cycleCount: 0.7 });
    expect(r.readings[0]).toMatchObject({ pct: 30, source: 'rider_return', memberId: 'pete' });
    expect(r.sessionStarted).toMatchObject({ sessionId: `s_${t0}`, startedAt: t0, startPct: 30, speedFactor: 1 });
    expect(r.itemPatch.battery?.charging?.startPct).toBe(30);
  });

  it('on the shelf: reading stored, no session', () => {
    const r = applyMovement(ctx({ item: held, movement: movement({ kind: 'checkin', readingPct: 55 }) }));
    expect(r.sessionStarted).toBeNull();
    expect(r.itemPatch.battery?.lastReading?.pct).toBe(55);
  });

  it('falls back to home when there is no event site', () => {
    const r = applyMovement(ctx({ item: held, event: null, movement: movement({ kind: 'checkin', eventId: null }) }));
    expect(r.itemPatch.locationId).toBe('hq');
  });

  it('condition flags move the item to needs_check', () => {
    const board = item({ category: 'board', labelCode: 'BRD-03', battery: null, holderMemberId: 'pete', locationId: null });
    const r = applyMovement(ctx({ item: board, movement: movement({ kind: 'checkin', conditionFlags: ['damaged', 'loose'] }) }));
    expect(r.itemPatch).toMatchObject({ status: 'needs_check', statusReason: 'damaged, loose' });
    expect(r.movementPatch).toMatchObject({ fromStatus: 'ready', toStatus: 'needs_check' });
    expect(r.itemPatch.battery).toBeUndefined();
  });

  it('flags a return of something not checked out, and a return by a different rider', () => {
    expect(applyMovement(ctx({ movement: movement({ kind: 'checkin' }) })).conflictReason).toBe('item was not checked out');
    expect(applyMovement(ctx({ item: held, movement: movement({ kind: 'checkin', subjectMemberId: 'gina' }) })).conflictReason).toBe('item was with a different rider');
  });

  it('force_checkin without a subject uses the current holder', () => {
    const r = applyMovement(ctx({ item: held, movement: movement({ kind: 'force_checkin', actorMemberId: 'axel', subjectMemberId: null }) }));
    expect(r.movementPatch.subjectMemberId).toBe('pete');
  });
});

describe('battery management', () => {
  const charging = { sessionId: 's_0', startedAt: t0 - 60 * MIN, startPct: 30, speedFactor: 1, eventId: 'ev', startedBy: 'kiosk' };

  it('a manual reading restarts the model from that point', () => {
    const r = applyMovement(ctx({ item: item({ battery: { lastReading: null, charging } }), movement: movement({ kind: 'battery_reading', actorMemberId: 'axel', readingPct: 70 }) }));
    expect(r.itemPatch.battery?.charging).toMatchObject({ sessionId: 's_0', startedAt: t0, startPct: 70 });
    expect(r.readings[0]).toMatchObject({ pct: 70, source: 'manager' });
  });

  it('charging_started uses the reading or the last known percentage', () => {
    const r = applyMovement(ctx({ item: item({ battery: { lastReading: { pct: 40, at: t0 - MIN, source: 'rider_return', memberId: null, eventId: null }, charging: null } }), movement: movement({ kind: 'charging_started', actorMemberId: 'axel' }) }));
    expect(r.sessionStarted?.startPct).toBe(40);
  });

  it('charging_ended freezes an estimate reading', () => {
    const r = applyMovement(ctx({ item: item({ battery: { lastReading: null, charging } }), movement: movement({ kind: 'charging_ended', actorMemberId: 'axel' }) }));
    expect(r.sessionEnded?.endPct).toBe(85);
    expect(r.readings[0]).toMatchObject({ pct: 85, source: 'estimate_freeze' });
    expect(r.itemPatch.battery?.charging).toBeNull();
  });
});

describe('location and status', () => {
  it('location_change clears the holder', () => {
    const r = applyMovement(ctx({ item: item({ holderMemberId: 'pete', locationId: null }), movement: movement({ kind: 'location_change', actorMemberId: 'axel', toLocationId: 'van' }) }));
    expect(r.itemPatch).toMatchObject({ locationId: 'van', holderMemberId: null });
  });

  it('leaving ready needs a reason; retiring releases reservations', () => {
    expect(applyMovement(ctx({ movement: movement({ kind: 'status_change', toStatus: 'in_repair', payload: {} }) })).rejectedReason).toMatch(/reason/);
    const r = applyMovement(ctx({ movement: movement({ kind: 'status_change', toStatus: 'retired', payload: { reason: 'cracked' } }) }));
    expect(r.itemPatch).toMatchObject({ status: 'retired', statusReason: 'cracked', retiredAt: t0 });
    expect(r.releaseReservations).toBe(true);
  });

  it('informational kinds do nothing', () => {
    const r = applyMovement(ctx({ movement: movement({ kind: 'reservation_set' }) }));
    expect(r.itemPatch).toEqual({});
    expect(r.readings).toEqual([]);
  });
});
