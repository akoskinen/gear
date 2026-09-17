import { estimateBattery } from './battery.js';
import type { BatteryFields, BatteryReading, BatteryType, ChargingState, Item, ItemStatus, Movement, ReadingSource } from './types.js';

export interface ApplyContext {
  item: Item;
  movement: Movement;
  /** The movement's event, when it has one. */
  event: { siteLocationId: string | null; chargerSpeedFactor: number } | null;
  /** Member the item is reserved for at this event, if any. */
  reservedForMemberId: string | null;
  batteryType: Pick<BatteryType, 'minutesTo80' | 'minutes80To100'> | null;
  readyPct: number;
}

export interface ApplyResult {
  /** Set when nothing was applied and the movement is kept as a rejected record. */
  rejectedReason: string | null;
  /** Set when the movement was applied but disagreed with the item's state. */
  conflictReason: string | null;
  itemPatch: Partial<Item>;
  movementPatch: Partial<Movement>;
  /** History rows to append under the item. */
  readings: BatteryReading[];
  sessionEnded: { session: ChargingState; endedAt: number; endPct: number; endedBy: string | null } | null;
  sessionStarted: ChargingState | null;
  /** Reservations to release (item retired). */
  releaseReservations: boolean;
}

function empty(): ApplyResult {
  return { rejectedReason: null, conflictReason: null, itemPatch: {}, movementPatch: {}, readings: [], sessionEnded: null, sessionStarted: null, releaseReservations: false };
}

/**
 * Applies one movement to an item. Pure: no I/O, deterministic for a given context.
 * Used by the Cloud Function that processes the log and by the kiosk to derive local state
 * from queued offline movements.
 */
export function applyMovement(ctx: ApplyContext): ApplyResult {
  const { item, movement: m, event } = ctx;
  const r = empty();
  const at = m.occurredAt;
  const isBattery = item.category === 'battery';
  let battery: BatteryFields = item.battery ?? { lastReading: null, charging: null };
  const conflict = (reason: string) => { if (!r.conflictReason) r.conflictReason = reason; };

  const currentEstimatePct = (): number => {
    const est = estimateBattery(battery, ctx.batteryType, ctx.readyPct, at);
    return est.pct === null ? 0 : Math.round(est.pct);
  };
  const addReading = (pct: number, source: ReadingSource, memberId: string | null) => {
    const reading: BatteryReading = { pct, at, source, memberId, eventId: m.eventId };
    r.readings.push(reading);
    battery = { ...battery, lastReading: reading };
  };
  const endSession = (endPct: number | null) => {
    if (!battery.charging) return;
    r.sessionEnded = { session: battery.charging, endedAt: at, endPct: endPct ?? currentEstimatePct(), endedBy: m.actorMemberId };
    battery = { ...battery, charging: null };
  };
  const startSession = (startPct: number) => {
    const s: ChargingState = { sessionId: `s_${at}`, startedAt: at, startPct, speedFactor: event?.chargerSpeedFactor ?? 1, eventId: m.eventId, startedBy: m.actorMemberId };
    r.sessionStarted = s;
    battery = { ...battery, charging: s };
  };

  switch (m.kind) {
    case 'checkout':
    case 'force_checkout': {
      if (item.ownerMemberId) return { ...r, rejectedReason: `rider-owned item ${item.labelCode} cannot be checked out` };
      if (!m.subjectMemberId) return { ...r, rejectedReason: 'checkout needs subjectMemberId' };
      if (m.kind === 'checkout') {
        if (item.status !== 'ready') conflict(`item was ${item.status} at checkout`);
        if (item.holderMemberId && item.holderMemberId !== m.subjectMemberId) conflict('item was already with another rider');
        if (ctx.reservedForMemberId && ctx.reservedForMemberId !== m.subjectMemberId) conflict('item reserved for another rider');
      }
      r.movementPatch.fromLocationId = item.locationId;
      if (isBattery) {
        endSession(m.readingPct);
        if (m.readingPct !== null) addReading(m.readingPct, 'rider_take', m.subjectMemberId);
      }
      r.itemPatch = { holderMemberId: m.subjectMemberId, locationId: null };
      break;
    }

    case 'checkin':
    case 'force_checkin': {
      if (!item.holderMemberId) conflict('item was not checked out');
      else if (m.subjectMemberId && item.holderMemberId !== m.subjectMemberId) conflict('item was with a different rider');
      const subject = m.subjectMemberId ?? item.holderMemberId;
      const dest = m.toLocationId ?? event?.siteLocationId ?? item.homeLocationId;
      if (!dest) return { ...r, rejectedReason: 'checkin needs a destination location' };
      r.movementPatch.subjectMemberId = subject;
      r.movementPatch.toLocationId = dest;
      r.itemPatch = { holderMemberId: null, locationId: dest };
      if (m.conditionFlags.length > 0) {
        r.movementPatch.fromStatus = item.status;
        r.movementPatch.toStatus = 'needs_check';
        r.itemPatch.status = 'needs_check';
        r.itemPatch.statusReason = m.conditionFlags.join(', ');
      }
      if (isBattery) {
        if (m.readingPct !== null) {
          addReading(m.readingPct, 'rider_return', subject);
          r.itemPatch.cycleCount = round2(item.cycleCount + (100 - m.readingPct) / 100);
        }
        if (m.payload['on_charger'] === true) {
          endSession(m.readingPct);
          startSession(m.readingPct ?? 0);
        }
      }
      break;
    }

    case 'battery_reading': {
      if (m.readingPct === null) return { ...r, rejectedReason: 'battery_reading needs readingPct' };
      const source = (typeof m.payload['source'] === 'string' ? m.payload['source'] : 'manager') as ReadingSource;
      addReading(m.readingPct, source, m.actorMemberId);
      // a manual reading restarts the model from that point
      if (battery.charging) battery = { ...battery, charging: { ...battery.charging, startedAt: at, startPct: m.readingPct } };
      break;
    }

    case 'charging_started': {
      const startPct = m.readingPct ?? currentEstimatePct();
      endSession(null);
      if (m.readingPct !== null) addReading(m.readingPct, 'manager', m.actorMemberId);
      startSession(startPct);
      break;
    }

    case 'charging_ended': {
      if (!battery.charging) conflict('battery was not charging');
      const endPct = m.readingPct ?? currentEstimatePct();
      endSession(endPct);
      addReading(endPct, m.readingPct === null ? 'estimate_freeze' : 'manager', m.actorMemberId);
      break;
    }

    case 'location_change': {
      if (!m.toLocationId) return { ...r, rejectedReason: 'location_change needs toLocationId' };
      r.movementPatch.fromLocationId = item.locationId;
      r.itemPatch = { locationId: m.toLocationId, holderMemberId: null };
      break;
    }

    case 'status_change': {
      const to = m.toStatus as ItemStatus | null;
      if (!to) return { ...r, rejectedReason: 'status_change needs toStatus' };
      const reason = typeof m.payload['reason'] === 'string' ? m.payload['reason'].trim() : '';
      if (to !== 'ready' && reason === '') return { ...r, rejectedReason: 'leaving ready needs a reason' };
      r.movementPatch.fromStatus = item.status;
      r.itemPatch = { status: to, statusReason: to === 'ready' ? null : reason };
      if (to === 'retired') { r.itemPatch.retiredAt = at; r.releaseReservations = true; }
      break;
    }

    default:
      // informational kinds have no side effects
      return r;
  }

  if (isBattery) r.itemPatch.battery = battery;
  r.itemPatch.lastMovementAt = at;
  return r;
}

function round2(n: number): number { return Math.round(n * 100) / 100; }
