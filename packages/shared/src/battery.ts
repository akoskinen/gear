import type { BatteryFields, BatteryType, ItemStatus } from './types.js';

export interface BatteryEstimate {
  pct: number | null;
  isEstimate: boolean;
  charging: boolean;
  readyAt: number | null;
  fullAt: number | null;
  lastReadingAt: number | null;
}

const MIN = 60_000;

/**
 * Piecewise-linear charge model from docs/05-battery-charge-estimation.md:
 * a fast segment to 80 % and a slow tail to 100 %, scaled by the charger speed factor.
 */
export function estimateBattery(
  battery: BatteryFields | null,
  type: Pick<BatteryType, 'minutesTo80' | 'minutes80To100'> | null,
  readyPct: number,
  now: number,
): BatteryEstimate {
  const reading = battery?.lastReading ?? null;
  const session = battery?.charging ?? null;

  if (!session) {
    return {
      pct: reading?.pct ?? null,
      isEstimate: reading?.source === 'estimate_freeze',
      charging: false,
      readyAt: null,
      fullAt: null,
      lastReadingAt: reading?.at ?? null,
    };
  }

  if (!type) {
    return { pct: session.startPct, isEstimate: true, charging: true, readyAt: null, fullAt: null, lastReadingAt: reading?.at ?? null };
  }

  const t80 = type.minutesTo80;
  const t100 = type.minutes80To100;
  const start = session.startPct;
  const factor = session.speedFactor > 0 ? session.speedFactor : 1;
  const effMin = Math.max(0, (now - session.startedAt) / MIN) * factor;

  let cur: number;
  if (start < 80) {
    const minTo80 = ((80 - start) / 80) * t80;
    cur = effMin <= minTo80
      ? start + (effMin / t80) * 80
      : 80 + Math.min(20, ((effMin - minTo80) / t100) * 20);
  } else {
    cur = start + Math.min(100 - start, (effMin / t100) * 20);
  }

  const minutesFromStartTo = (target: number): number => {
    if (start >= target) return 0;
    if (target <= 80) return ((target - start) / 80) * t80;
    return (Math.max(0, 80 - start) / 80) * t80 + ((target - Math.max(80, start)) / 20) * t100;
  };

  return {
    pct: Math.round(Math.min(100, cur) * 10) / 10,
    isEstimate: true,
    charging: true,
    readyAt: session.startedAt + (minutesFromStartTo(readyPct) / factor) * MIN,
    fullAt: session.startedAt + (minutesFromStartTo(100) / factor) * MIN,
    lastReadingAt: reading?.at ?? null,
  };
}

export type BatteryStripState = 'in_use' | 'charging' | 'ready' | 'low' | 'unknown' | Exclude<ItemStatus, 'ready'>;

/** The state a battery tile shows on the hub, kiosk and rider app. */
export function batteryStripState(
  item: { status: ItemStatus; holderMemberId: string | null },
  est: BatteryEstimate,
  readyPct: number,
): BatteryStripState {
  if (item.status !== 'ready') return item.status;
  if (item.holderMemberId) return 'in_use';
  if (est.charging) return est.pct !== null && est.pct >= readyPct ? 'ready' : 'charging';
  if (est.pct === null) return 'unknown';
  return est.pct >= readyPct ? 'ready' : 'low';
}
