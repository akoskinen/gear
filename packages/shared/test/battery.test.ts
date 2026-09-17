import { describe, expect, it } from 'vitest';
import { batteryStripState, estimateBattery } from '../src/battery.js';

const MIN = 60_000;
const type = { minutesTo80: 80, minutes80To100: 40 }; // 1 %/min then 0.5 %/min
const t0 = Date.parse('2026-10-03T10:00:00Z');

describe('estimateBattery', () => {
  it('reports the last reading when not charging', () => {
    const est = estimateBattery({ lastReading: { pct: 42, at: t0, source: 'rider_return', memberId: null, eventId: null }, charging: null }, type, 80, t0 + 5 * MIN);
    expect(est).toMatchObject({ pct: 42, isEstimate: false, charging: false, readyAt: null, fullAt: null });
  });

  it('is unknown with no reading', () => {
    expect(estimateBattery(null, type, 80, t0).pct).toBeNull();
  });

  it('climbs the fast segment then the tail: 30 % + 60 min = 85 %', () => {
    const est = estimateBattery({ lastReading: null, charging: { sessionId: 's_0', startedAt: t0, startPct: 30, speedFactor: 1, eventId: null, startedBy: null } }, type, 80, t0 + 60 * MIN);
    expect(est.pct).toBe(85);
    expect(est.charging).toBe(true);
    expect(est.isEstimate).toBe(true);
    expect(est.readyAt).toBe(t0 + 50 * MIN);   // (80-30)/80*80
    expect(est.fullAt).toBe(t0 + 90 * MIN);    // 50 + 40
  });

  it('stays inside the fast segment early on', () => {
    const est = estimateBattery({ lastReading: null, charging: { sessionId: 's_0', startedAt: t0, startPct: 30, speedFactor: 1, eventId: null, startedBy: null } }, type, 80, t0 + 20 * MIN);
    expect(est.pct).toBe(50);
  });

  it('never exceeds 100', () => {
    const est = estimateBattery({ lastReading: null, charging: { sessionId: 's_0', startedAt: t0, startPct: 30, speedFactor: 1, eventId: null, startedBy: null } }, type, 80, t0 + 500 * MIN);
    expect(est.pct).toBe(100);
  });

  it('starting above 80 only uses the tail', () => {
    const est = estimateBattery({ lastReading: null, charging: { sessionId: 's_0', startedAt: t0, startPct: 90, speedFactor: 1, eventId: null, startedBy: null } }, type, 80, t0 + 10 * MIN);
    expect(est.pct).toBe(95);
    expect(est.readyAt).toBe(t0);              // already past threshold
    expect(est.fullAt).toBe(t0 + 20 * MIN);
  });

  it('a faster charger shortens the times', () => {
    const est = estimateBattery({ lastReading: null, charging: { sessionId: 's_0', startedAt: t0, startPct: 30, speedFactor: 2, eventId: null, startedBy: null } }, type, 80, t0 + 25 * MIN);
    expect(est.pct).toBe(80);
    expect(est.readyAt).toBe(t0 + 25 * MIN);
  });

  it('with no charge model it reports the start percentage as an estimate', () => {
    const est = estimateBattery({ lastReading: null, charging: { sessionId: 's_0', startedAt: t0, startPct: 30, speedFactor: 1, eventId: null, startedBy: null } }, null, 80, t0 + 60 * MIN);
    expect(est).toMatchObject({ pct: 30, isEstimate: true, charging: true, readyAt: null });
  });
});

describe('batteryStripState', () => {
  const ready = { status: 'ready' as const, holderMemberId: null };
  it('orders by status, holder, charging, threshold', () => {
    expect(batteryStripState({ status: 'needs_check', holderMemberId: null }, estimateBattery(null, type, 80, t0), 80)).toBe('needs_check');
    expect(batteryStripState({ status: 'ready', holderMemberId: 'pete' }, estimateBattery(null, type, 80, t0), 80)).toBe('in_use');
    expect(batteryStripState(ready, estimateBattery(null, type, 80, t0), 80)).toBe('unknown');
    const low = { lastReading: { pct: 40, at: t0, source: 'rider_return' as const, memberId: null, eventId: null }, charging: null };
    expect(batteryStripState(ready, estimateBattery(low, type, 80, t0), 80)).toBe('low');
    const charging = { lastReading: null, charging: { sessionId: 's_0', startedAt: t0, startPct: 30, speedFactor: 1, eventId: null, startedBy: null } };
    expect(batteryStripState(ready, estimateBattery(charging, type, 80, t0 + 10 * MIN), 80)).toBe('charging');
    expect(batteryStripState(ready, estimateBattery(charging, type, 80, t0 + 60 * MIN), 80)).toBe('ready');
  });
});
