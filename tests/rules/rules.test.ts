import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { assertFails, assertSucceeds, initializeTestEnvironment, type RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, collection, getDocs } from 'firebase/firestore';

const TEAM = 'teamA';
const OTHER = 'teamB';
let env: RulesTestEnvironment;

const member = (uid: string, role: string, tier = 'team') => ({ uid, displayName: uid, role, tier, phone: null, photoUrl: null, active: true, setup: {}, hasPin: false, createdAt: 1 });
const item = (over: Record<string, unknown> = {}) => ({
  category: 'board', labelCode: 'BRD-03', model: 'Lift 4\'4', spec: {}, serial: null, ownerMemberId: null,
  homeLocationId: 'hq', locationId: 'site', holderMemberId: null, status: 'ready', statusReason: null, expectedBackOn: null,
  batteryTypeId: null, firmwareVersion: null, cycleCount: 0, chargerSpeedFactor: null, battery: null, photos: [],
  createdAt: 1, retiredAt: null, lastMovementAt: null, ...over,
});
const movement = (over: Record<string, unknown> = {}) => ({
  eventId: 'ev', itemId: 'brd3', kind: 'checkout', actorMemberId: 'kioskA', subjectMemberId: 'pete',
  fromLocationId: null, toLocationId: null, fromStatus: null, toStatus: null, conditionFlags: [], readingPct: null,
  payload: {}, conflictReason: null, rejectedReason: null, recordedOffline: false, deviceId: null,
  occurredAt: 1, receivedAt: null, applied: false, appliedAt: null, ...over,
});

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-gear',
    firestore: { rules: readFileSync(resolve(__dirname, '../../firestore.rules'), 'utf8'), host: '127.0.0.1', port: 8080 },
  });
});
afterAll(async () => { await env.cleanup(); });

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `gearTeams/${TEAM}`), { name: 'Lift Foils Racing', shortName: 'LIFT', batteryReadyPct: 80, createdBy: 'axel', createdAt: 1 });
    await setDoc(doc(db, `gearTeams/${TEAM}/members/axel`), member('axel', 'owner', 'core'));
    await setDoc(doc(db, `gearTeams/${TEAM}/members/pete`), member('pete', 'rider', 'core'));
    await setDoc(doc(db, `gearTeams/${TEAM}/members/kioskA`), member('kioskA', 'kiosk', 'guest'));
    await setDoc(doc(db, `gearTeams/${TEAM}/members/gina`), { ...member('gina', 'rider', 'guest'), uid: null });
    await setDoc(doc(db, `gearTeams/${TEAM}/pins/pete`), { salt: 'abc', hash: 'def', setAt: 1 });
    await setDoc(doc(db, `gearTeams/${TEAM}/items/brd3`), item());
    await setDoc(doc(db, `gearTeams/${TEAM}/events/ev`), { name: 'Menton Open', phase: 'planned', startsOn: '2026-10-03', endsOn: '2026-10-05', createdAt: 1, closedAt: null });
    await setDoc(doc(db, `gearTeams/${TEAM}/events/ev/roster/pete`), { status: 'invited', invitedAt: 1, respondedAt: null });
    await setDoc(doc(db, `gearTeams/${TEAM}/movements/m1`), movement({ applied: true }));
    await setDoc(doc(db, `gearTeams/${OTHER}`), { name: 'Other', shortName: 'OTHR', createdBy: 'zed', createdAt: 1 });
    await setDoc(doc(db, `gearTeams/${OTHER}/members/zed`), member('zed', 'owner'));
  });
});

const as = (uid: string | null) => (uid ? env.authenticatedContext(uid).firestore() : env.unauthenticatedContext().firestore());

describe('team isolation', () => {
  it('a member of another team sees nothing', async () => {
    const db = as('zed');
    await assertFails(getDoc(doc(db, `gearTeams/${TEAM}`)));
    await assertFails(getDoc(doc(db, `gearTeams/${TEAM}/items/brd3`)));
    await assertFails(getDocs(collection(db, `gearTeams/${TEAM}/members`)));
    await assertFails(getDocs(collection(db, `gearTeams/${TEAM}/movements`)));
    await assertFails(setDoc(doc(db, `gearTeams/${TEAM}/movements/x`), movement({ actorMemberId: 'zed' })));
  });
  it('anonymous sees nothing', async () => {
    await assertFails(getDoc(doc(as(null), `gearTeams/${TEAM}/items/brd3`)));
  });
  it('an inactive member is locked out', async () => {
    await env.withSecurityRulesDisabled((c) => updateDoc(doc(c.firestore(), `gearTeams/${TEAM}/members/pete`), { active: false }));
    await assertFails(getDoc(doc(as('pete'), `gearTeams/${TEAM}/items/brd3`)));
  });
});

describe('items', () => {
  it('rider reads but cannot write', async () => {
    const db = as('pete');
    await assertSucceeds(getDoc(doc(db, `gearTeams/${TEAM}/items/brd3`)));
    await assertFails(updateDoc(doc(db, `gearTeams/${TEAM}/items/brd3`), { model: 'hacked' }));
  });
  it('manager edits metadata but not state fields', async () => {
    const db = as('axel');
    await assertSucceeds(updateDoc(doc(db, `gearTeams/${TEAM}/items/brd3`), { model: 'Lift 4\'2 Race', serial: 'X1' }));
    await assertFails(updateDoc(doc(db, `gearTeams/${TEAM}/items/brd3`), { holderMemberId: 'pete' }));
    await assertFails(updateDoc(doc(db, `gearTeams/${TEAM}/items/brd3`), { status: 'retired' }));
    await assertFails(updateDoc(doc(db, `gearTeams/${TEAM}/items/brd3`), { locationId: 'van' }));
    await assertFails(deleteDoc(doc(db, `gearTeams/${TEAM}/items/brd3`)));
  });
  it('manager creates items, not already in someone\'s hands', async () => {
    const db = as('axel');
    await assertSucceeds(setDoc(doc(db, `gearTeams/${TEAM}/items/new`), item({ labelCode: 'BRD-04' })));
    await assertFails(setDoc(doc(db, `gearTeams/${TEAM}/items/new2`), item({ labelCode: 'BRD-05', holderMemberId: 'pete' })));
  });
  it('kiosk cannot edit inventory', async () => {
    await assertFails(updateDoc(doc(as('kioskA'), `gearTeams/${TEAM}/items/brd3`), { model: 'hacked' }));
  });
});

describe('movements', () => {
  it('kiosk appends its own kinds with itself as actor', async () => {
    const db = as('kioskA');
    await assertSucceeds(setDoc(doc(db, `gearTeams/${TEAM}/movements/k1`), movement()));
    await assertSucceeds(setDoc(doc(db, `gearTeams/${TEAM}/movements/k2`), movement({ kind: 'checkin', readingPct: 30, payload: { on_charger: true } })));
    await assertSucceeds(setDoc(doc(db, `gearTeams/${TEAM}/movements/k3`), movement({ kind: 'availability_request' })));
  });
  it('kiosk cannot write manager kinds, impersonate, or pre-apply', async () => {
    const db = as('kioskA');
    await assertFails(setDoc(doc(db, `gearTeams/${TEAM}/movements/x1`), movement({ kind: 'status_change', toStatus: 'ready' })));
    await assertFails(setDoc(doc(db, `gearTeams/${TEAM}/movements/x2`), movement({ kind: 'force_checkin' })));
    await assertFails(setDoc(doc(db, `gearTeams/${TEAM}/movements/x3`), movement({ actorMemberId: 'axel' })));
    await assertFails(setDoc(doc(db, `gearTeams/${TEAM}/movements/x4`), movement({ applied: true })));
    await assertFails(setDoc(doc(db, `gearTeams/${TEAM}/movements/x5`), movement({ conflictReason: 'none' })));
  });
  it('manager writes manager kinds but not function-only kinds', async () => {
    const db = as('axel');
    await assertSucceeds(setDoc(doc(db, `gearTeams/${TEAM}/movements/a1`), movement({ kind: 'force_checkin', actorMemberId: 'axel' })));
    await assertSucceeds(setDoc(doc(db, `gearTeams/${TEAM}/movements/a2`), movement({ kind: 'status_change', actorMemberId: 'axel', toStatus: 'in_repair', payload: { reason: 'cracked' } })));
    await assertFails(setDoc(doc(db, `gearTeams/${TEAM}/movements/a3`), movement({ kind: 'reservation_set', actorMemberId: 'axel' })));
    await assertFails(setDoc(doc(db, `gearTeams/${TEAM}/movements/a4`), movement({ kind: 'event_closed', actorMemberId: 'axel' })));
  });
  it('riders read the log but cannot write it', async () => {
    const db = as('pete');
    await assertSucceeds(getDoc(doc(db, `gearTeams/${TEAM}/movements/m1`)));
    await assertFails(setDoc(doc(db, `gearTeams/${TEAM}/movements/p1`), movement({ actorMemberId: 'pete' })));
  });
  it('nobody updates or deletes log rows', async () => {
    await assertFails(updateDoc(doc(as('axel'), `gearTeams/${TEAM}/movements/m1`), { conflictReason: null }));
    await assertFails(deleteDoc(doc(as('axel'), `gearTeams/${TEAM}/movements/m1`)));
  });
});

describe('pins', () => {
  it('staff and kiosk read hashes, riders do not, nobody writes', async () => {
    await assertSucceeds(getDoc(doc(as('kioskA'), `gearTeams/${TEAM}/pins/pete`)));
    await assertSucceeds(getDoc(doc(as('axel'), `gearTeams/${TEAM}/pins/pete`)));
    await assertFails(getDoc(doc(as('pete'), `gearTeams/${TEAM}/pins/pete`)));
    await assertFails(setDoc(doc(as('axel'), `gearTeams/${TEAM}/pins/gina`), { salt: 'x', hash: 'y', setAt: 1 }));
  });
});

describe('members and profile', () => {
  it('rider edits own setup and phone, not role or tier', async () => {
    const db = as('pete');
    await assertSucceeds(updateDoc(doc(db, `gearTeams/${TEAM}/members/pete`), { setup: { board: { source: 'own', description: 'custom' } }, phone: '+351' }));
    await assertFails(updateDoc(doc(db, `gearTeams/${TEAM}/members/pete`), { role: 'manager' }));
    await assertFails(updateDoc(doc(db, `gearTeams/${TEAM}/members/pete`), { tier: 'guest', phone: 'x' }));
    await assertFails(updateDoc(doc(db, `gearTeams/${TEAM}/members/gina`), { setup: {} }));
  });
  it('manager manages members', async () => {
    const db = as('axel');
    await assertSucceeds(setDoc(doc(db, `gearTeams/${TEAM}/members/newguest`), { ...member('newguest', 'rider', 'guest'), uid: null }));
    await assertSucceeds(updateDoc(doc(db, `gearTeams/${TEAM}/members/pete`), { tier: 'team' }));
  });
  it('only the owner renames the team; a manager may change settings', async () => {
    await assertFails(updateDoc(doc(as('pete'), `gearTeams/${TEAM}`), { batteryReadyPct: 90 }));
    await env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), `gearTeams/${TEAM}/members/mgr`), member('mgr', 'manager')));
    await assertSucceeds(updateDoc(doc(as('mgr'), `gearTeams/${TEAM}`), { batteryReadyPct: 90 }));
    await assertFails(updateDoc(doc(as('mgr'), `gearTeams/${TEAM}`), { name: 'Renamed' }));
    await assertSucceeds(updateDoc(doc(as('axel'), `gearTeams/${TEAM}`), { name: 'Renamed' }));
  });
  it('a user owns their profile but not their team list', async () => {
    const db = as('pete');
    await assertSucceeds(setDoc(doc(db, 'gearUsers/pete'), { displayName: 'Pete' }));
    await assertFails(updateDoc(doc(db, 'gearUsers/pete'), { teams: { teamA: { role: 'owner' } } }));
    await assertFails(getDoc(doc(db, 'gearUsers/axel')));
  });
});

describe('events, roster, requests', () => {
  it('rider answers own invitation only', async () => {
    const db = as('pete');
    await assertSucceeds(updateDoc(doc(db, `gearTeams/${TEAM}/events/ev/roster/pete`), { status: 'confirmed', respondedAt: 2 }));
    await assertFails(updateDoc(doc(db, `gearTeams/${TEAM}/events/ev/roster/pete`), { invitedAt: 0 }));
    await assertFails(setDoc(doc(db, `gearTeams/${TEAM}/events/ev/roster/gina`), { status: 'confirmed', invitedAt: 1, respondedAt: 1 }));
  });
  it('rider submits and edits own request, never its status', async () => {
    const db = as('pete');
    const req = { status: 'submitted', batteriesPerDay: 3, firmwareNote: null, notes: null, transportOwnGear: true, setup: {}, lines: [], changedSincePlanned: false, declineReason: null, submittedAt: 1, updatedAt: 1 };
    await assertSucceeds(setDoc(doc(db, `gearTeams/${TEAM}/events/ev/requests/pete`), req));
    await assertSucceeds(updateDoc(doc(db, `gearTeams/${TEAM}/events/ev/requests/pete`), { batteriesPerDay: 2 }));
    await assertFails(updateDoc(doc(db, `gearTeams/${TEAM}/events/ev/requests/pete`), { status: 'planned' }));
    await assertFails(setDoc(doc(db, `gearTeams/${TEAM}/events/ev/requests/gina`), req));
    await assertFails(setDoc(doc(db, `gearTeams/${TEAM}/events/ev/requests/pete2`), { ...req, status: 'planned' }));
    await assertSucceeds(updateDoc(doc(as('axel'), `gearTeams/${TEAM}/events/ev/requests/pete`), { status: 'planned' }));
  });
  it('managers plan; closing goes through the callable', async () => {
    const db = as('axel');
    await assertSucceeds(setDoc(doc(db, `gearTeams/${TEAM}/events/ev/reservations/brd3`), { itemId: 'brd3', memberId: 'pete', createdBy: 'axel', createdAt: 1, releasedAt: null, releaseReason: null }));
    await assertSucceeds(setDoc(doc(db, `gearTeams/${TEAM}/events/ev/manifest/brd3`), { state: 'planned', fromLineId: null, createdAt: 1, updatedAt: 1 }));
    await assertFails(setDoc(doc(as('pete'), `gearTeams/${TEAM}/events/ev/reservations/brd3`), { itemId: 'brd3', memberId: 'pete', createdBy: 'pete', createdAt: 1, releasedAt: null, releaseReason: null }));
    await assertSucceeds(updateDoc(doc(db, `gearTeams/${TEAM}/events/ev`), { phase: 'packing' }));
    await assertFails(updateDoc(doc(db, `gearTeams/${TEAM}/events/ev`), { phase: 'closed' }));
    await assertFails(setDoc(doc(db, `gearTeams/${TEAM}/events/ev2`), { name: 'x', phase: 'live', startsOn: '2026-10-03', endsOn: '2026-10-05', createdAt: 1, closedAt: null }));
  });
});
