// Shared data model for the Gear app. Mirrors docs/09-firestore-data-model.md.
// Timestamps are epoch milliseconds in shared logic; the Firestore layer converts.

export type MemberRole = 'owner' | 'manager' | 'rider' | 'kiosk';
export type RiderTier = 'core' | 'team' | 'guest';
export type SetupSlot = 'board' | 'mast_fuselage' | 'front_wing' | 'stabilizer' | 'propulsion' | 'battery' | 'controller';
export type SetupSource = 'own' | 'team';
export type GearCategory = 'board' | 'mast' | 'front_wing' | 'stabilizer' | 'fuselage' | 'propulsion' | 'battery' | 'controller' | 'charger' | 'spare';
export type ItemStatus = 'ready' | 'needs_check' | 'in_repair' | 'retired';
export type LocationKind = 'hq' | 'hq_sub' | 'vehicle' | 'event_site' | 'unknown';
export type EventType = 'race' | 'training' | 'testing' | 'demo';
export type EventPhase = 'planned' | 'packing' | 'live' | 'wrap_up' | 'closed';
export type RosterStatus = 'invited' | 'confirmed' | 'declined' | 'not_coming';
export type RequestStatus = 'submitted' | 'seen' | 'planned' | 'fulfilled' | 'declined';
export type RequestLineKind = 'gear' | 'spare' | 'free_text';
export type RequestLineStatus = 'open' | 'planned' | 'fulfilled' | 'declined';
export type PackingState = 'planned' | 'packed' | 'loaded' | 'on_site' | 'returned';
export type EssentialState = 'todo' | 'confirmed' | 'packed' | 'on_site';
export type ReadingSource = 'rider_return' | 'rider_take' | 'manager' | 'import' | 'estimate_freeze';

export type MovementKind =
  | 'checkout' | 'checkin' | 'force_checkout' | 'force_checkin'
  | 'location_change' | 'status_change'
  | 'battery_reading' | 'charging_started' | 'charging_ended'
  | 'reservation_set' | 'reservation_released'
  | 'manifest_added' | 'manifest_removed' | 'packing_state'
  | 'availability_request' | 'import' | 'event_closed' | 'note';

/** Kinds a kiosk device may write. Everything else is manager-only. */
export const KIOSK_MOVEMENT_KINDS: readonly MovementKind[] = [
  'checkout', 'checkin', 'battery_reading', 'charging_started', 'charging_ended', 'availability_request',
];

/** Kinds that change item state when applied. The rest are informational log rows. */
export const STATEFUL_MOVEMENT_KINDS: readonly MovementKind[] = [
  'checkout', 'checkin', 'force_checkout', 'force_checkin',
  'location_change', 'status_change',
  'battery_reading', 'charging_started', 'charging_ended',
];

export const SETUP_SLOTS: readonly SetupSlot[] = ['board', 'mast_fuselage', 'front_wing', 'stabilizer', 'propulsion', 'battery', 'controller'];

export const DEFAULT_LABEL_PREFIXES: Record<GearCategory, { prefix: string; seqWidth: number; includeSize: boolean }> = {
  board: { prefix: 'BRD', seqWidth: 2, includeSize: false },
  mast: { prefix: 'MST', seqWidth: 2, includeSize: false },
  front_wing: { prefix: 'FW', seqWidth: 2, includeSize: true },
  stabilizer: { prefix: 'STB', seqWidth: 2, includeSize: false },
  fuselage: { prefix: 'FUS', seqWidth: 2, includeSize: false },
  propulsion: { prefix: 'PRP', seqWidth: 2, includeSize: false },
  battery: { prefix: 'BAT', seqWidth: 2, includeSize: false },
  controller: { prefix: 'CTL', seqWidth: 2, includeSize: false },
  charger: { prefix: 'CHG', seqWidth: 2, includeSize: false },
  spare: { prefix: 'SPR', seqWidth: 2, includeSize: false },
};

export const DEFAULT_ESSENTIALS: Array<{ name: string; quantity: number; leadTimeDays: number }> = [
  { name: 'Tents', quantity: 2, leadTimeDays: 7 },
  { name: 'Tables', quantity: 2, leadTimeDays: 7 },
  { name: 'Chairs', quantity: 6, leadTimeDays: 7 },
  { name: 'Water', quantity: 1, leadTimeDays: 2 },
  { name: 'Lunch per day', quantity: 1, leadTimeDays: 2 },
  { name: 'Fuel', quantity: 1, leadTimeDays: 2 },
  { name: 'Generator', quantity: 1, leadTimeDays: 7 },
  { name: 'Tools', quantity: 1, leadTimeDays: 3 },
  { name: 'First aid', quantity: 1, leadTimeDays: 3 },
  { name: 'Signage and flags', quantity: 1, leadTimeDays: 7 },
  { name: 'Buoys for the speed track', quantity: 3, leadTimeDays: 7 },
  { name: 'Timing gear', quantity: 1, leadTimeDays: 7 },
  { name: 'Chargers', quantity: 4, leadTimeDays: 3 },
  { name: 'Extension leads', quantity: 4, leadTimeDays: 3 },
];

export const DEFAULT_SPARE_OPTIONS = ['Prop', 'Fuse', 'Mast bolts', 'Wing screws', 'Controller strap'];

export interface KioskSettings {
  sessionTimeoutS: number;
  confirmDismissS: number;
  askPctAtTake: boolean;
  pctStep: 5 | 10;
  theme: 'light' | 'dark';
  sound: boolean;
}

export const DEFAULT_KIOSK_SETTINGS: KioskSettings = {
  sessionTimeoutS: 20, confirmDismissS: 4, askPctAtTake: true, pctStep: 10, theme: 'light', sound: true,
};

export interface Team {
  name: string;
  shortName: string;
  logoUrl: string | null;
  timeZone: string;
  endOfDay: string;              // "19:00"
  batteryReadyPct: number;
  requestDeadlineDays: number;
  overdueHours: number;
  defaultChargers: number;
  kiosk: KioskSettings;
  labelPrefixes: Record<GearCategory, { prefix: string; seqWidth: number; includeSize: boolean }>;
  essentialsTemplate: Array<{ name: string; quantity: number; ownerMemberId: string | null; leadTimeDays: number }>;
  spareOptions: string[];
  createdAt: number;
  createdBy: string;
}

export interface SetupEntry { source: SetupSource; description: string | null }

export interface Member {
  uid: string | null;            // null for kiosk-only members
  displayName: string;
  role: MemberRole;
  tier: RiderTier;
  phone: string | null;
  photoUrl: string | null;
  active: boolean;
  setup: Partial<Record<SetupSlot, SetupEntry>>;
  hasPin: boolean;
  createdAt: number;
}

export interface BatteryType {
  name: string;
  capacityNote: string | null;
  minutesTo80: number;
  minutes80To100: number;
  archivedAt: number | null;
}

export interface BatteryReading { pct: number; at: number; source: ReadingSource; memberId: string | null; eventId: string | null }
export interface ChargingState { sessionId: string; startedAt: number; startPct: number; speedFactor: number; eventId: string | null; startedBy: string | null }

export interface BatteryFields {
  lastReading: BatteryReading | null;
  charging: ChargingState | null;
}

export interface Item {
  category: GearCategory;
  labelCode: string;
  model: string;
  spec: Record<string, unknown>;
  serial: string | null;
  ownerMemberId: string | null;  // null = team-owned
  homeLocationId: string | null;
  locationId: string | null;     // null while with a rider
  holderMemberId: string | null;
  status: ItemStatus;
  statusReason: string | null;
  expectedBackOn: string | null; // ISO date
  batteryTypeId: string | null;
  firmwareVersion: string | null;
  cycleCount: number;
  chargerSpeedFactor: number | null;
  battery: BatteryFields | null; // batteries only
  photos: string[];
  createdAt: number;
  retiredAt: number | null;
  lastMovementAt: number | null;
}

export interface Essential { id: string; name: string; quantity: number; ownerMemberId: string | null; leadTimeDays: number; state: EssentialState }

export interface Event {
  name: string;
  type: EventType;
  locationName: string | null;
  venueNotes: string | null;
  timeZone: string | null;
  startsOn: string;              // ISO date
  endsOn: string;
  phase: EventPhase;
  requestDeadlineOn: string | null;
  chargersAvailable: number | null;
  chargerSpeedFactor: number;
  siteLocationId: string | null;
  essentials: Essential[];
  createdAt: number;
  closedAt: number | null;
}

export interface RosterEntry { status: RosterStatus; invitedAt: number; respondedAt: number | null }

export interface RequestLine {
  id: string;
  kind: RequestLineKind;
  catalogueModelId: string | null;
  text: string | null;
  status: RequestLineStatus;
  plannedItemId: string | null;
  declineReason: string | null;
}

export interface RiderRequest {
  status: RequestStatus;
  batteriesPerDay: number | null;
  firmwareNote: string | null;
  notes: string | null;
  transportOwnGear: boolean;
  setup: Partial<Record<SetupSlot, SetupEntry>>;
  lines: RequestLine[];
  changedSincePlanned: boolean;
  declineReason: string | null;
  submittedAt: number;
  updatedAt: number;
}

export interface Reservation { itemId: string; memberId: string; createdBy: string | null; createdAt: number; releasedAt: number | null; releaseReason: string | null }
export interface ManifestEntry { state: PackingState; fromLineId: string | null; createdAt: number; updatedAt: number }

export interface Movement {
  eventId: string | null;
  itemId: string | null;
  kind: MovementKind;
  actorMemberId: string | null;
  subjectMemberId: string | null;
  fromLocationId: string | null;
  toLocationId: string | null;
  fromStatus: ItemStatus | null;
  toStatus: ItemStatus | null;
  conditionFlags: string[];
  readingPct: number | null;
  payload: Record<string, unknown>;
  conflictReason: string | null;
  rejectedReason: string | null;
  recordedOffline: boolean;
  deviceId: string | null;
  occurredAt: number;
  receivedAt: number | null;
  applied: boolean;
  appliedAt: number | null;
}

export interface KioskDevice { memberId: string; name: string; boundEventId: string | null; lastSyncAt: number | null; unsyncedCount: number; signedOutAt: number | null }
export interface Notification { memberId: string; kind: string; title: string; body: string | null; link: Record<string, string>; readAt: number | null; createdAt: number }
