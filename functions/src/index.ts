// Cloud Functions for the Gear app (Firebase project efoilracingprofiles).
// All data lives under /gearTeams/{teamId}. See docs/09-firestore-data-model.md.

import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { initializeApp } from 'firebase-admin/app';
import { FieldValue, getFirestore, type DocumentReference, type Transaction } from 'firebase-admin/firestore';
import { setGlobalOptions } from 'firebase-functions/v2';
import { onDocumentCreated, onDocumentWritten } from 'firebase-functions/v2/firestore';
import { HttpsError, onCall, type CallableRequest } from 'firebase-functions/v2/https';
import {
  applyMovement, DEFAULT_ESSENTIALS, DEFAULT_KIOSK_SETTINGS, DEFAULT_LABEL_PREFIXES, DEFAULT_SPARE_OPTIONS,
  STATEFUL_MOVEMENT_KINDS,
  type BatteryType, type Event, type Item, type Member, type MemberRole, type Movement, type MovementKind, type RiderTier, type Team,
} from '@gear/shared';

initializeApp();
setGlobalOptions({ region: 'europe-west1', maxInstances: 10 });
const db = getFirestore();

const teamRef = (teamId: string) => db.doc(`gearTeams/${teamId}`);
const now = () => Date.now();

// ---------------------------------------------------------------------------
// Auth and role helpers for callables
// ---------------------------------------------------------------------------
function uidOf(req: CallableRequest): string {
  if (!req.auth?.uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  return req.auth.uid;
}

async function memberOf(teamId: string, uid: string): Promise<(Member & { id: string }) | null> {
  const snap = await teamRef(teamId).collection('members').doc(uid).get();
  if (!snap.exists) return null;
  const m = snap.data() as Member;
  return m.active ? { ...m, id: snap.id } : null;
}

async function requireRole(teamId: string, uid: string, roles: MemberRole[]): Promise<Member & { id: string }> {
  const m = await memberOf(teamId, uid);
  if (!m || !roles.includes(m.role)) throw new HttpsError('permission-denied', 'Not allowed.');
  return m;
}

const str = (v: unknown, name: string, max = 200): string => {
  if (typeof v !== 'string' || v.trim() === '' || v.length > max) throw new HttpsError('invalid-argument', `${name} is required.`);
  return v.trim();
};

// ---------------------------------------------------------------------------
// Movement log: apply each stateful movement to its item, exactly once
// ---------------------------------------------------------------------------
export const onMovementCreated = onDocumentCreated('gearTeams/{teamId}/movements/{movementId}', async (event) => {
  const snap = event.data;
  if (!snap) return;
  const { teamId } = event.params;
  const movement = snap.data() as Movement;
  if (movement.applied) return;

  if (!STATEFUL_MOVEMENT_KINDS.includes(movement.kind) || !movement.itemId) {
    await snap.ref.update({ applied: true, appliedAt: now(), receivedAt: movement.receivedAt ?? now() });
    return;
  }

  const itemRef = teamRef(teamId).collection('items').doc(movement.itemId);
  await db.runTransaction(async (tx) => {
    const [mSnap, iSnap, tSnap] = await Promise.all([tx.get(snap.ref), tx.get(itemRef), tx.get(teamRef(teamId))]);
    if (!mSnap.exists || (mSnap.data() as Movement).applied) return;
    const at = now();
    if (!iSnap.exists) {
      tx.update(snap.ref, { applied: true, appliedAt: at, receivedAt: at, rejectedReason: 'item not found' });
      return;
    }
    const item = iSnap.data() as Item;
    const team = tSnap.data() as Team;

    let ev: Event | null = null;
    let reservedFor: string | null = null;
    if (movement.eventId) {
      const evRef = teamRef(teamId).collection('events').doc(movement.eventId);
      const [eSnap, rSnap] = await Promise.all([tx.get(evRef), tx.get(evRef.collection('reservations').doc(movement.itemId!))]);
      ev = eSnap.exists ? (eSnap.data() as Event) : null;
      if (rSnap.exists && rSnap.data()!.releasedAt == null) reservedFor = rSnap.data()!.memberId as string;
    }
    let batteryType: BatteryType | null = null;
    if (item.category === 'battery' && item.batteryTypeId) {
      const btSnap = await tx.get(teamRef(teamId).collection('batteryTypes').doc(item.batteryTypeId));
      batteryType = btSnap.exists ? (btSnap.data() as BatteryType) : null;
    }

    const result = applyMovement({
      item, movement,
      event: ev ? { siteLocationId: ev.siteLocationId, chargerSpeedFactor: ev.chargerSpeedFactor ?? 1 } : null,
      reservedForMemberId: reservedFor,
      batteryType,
      readyPct: team.batteryReadyPct ?? 80,
    });

    const movementPatch: Record<string, unknown> = { ...result.movementPatch, applied: true, appliedAt: at, receivedAt: movement.receivedAt ?? at };
    if (result.rejectedReason) {
      tx.update(snap.ref, { ...movementPatch, rejectedReason: result.rejectedReason });
      return;
    }
    movementPatch.conflictReason = result.conflictReason;
    tx.update(snap.ref, movementPatch);
    if (Object.keys(result.itemPatch).length > 0) tx.update(itemRef, result.itemPatch as Record<string, unknown>);

    for (const r of result.readings) tx.set(itemRef.collection('readings').doc(), { ...r, movementId: snap.id });
    if (result.sessionEnded) {
      const s = result.sessionEnded;
      tx.set(itemRef.collection('chargingSessions').doc(s.session.sessionId),
        { ...s.session, endedAt: s.endedAt, endPct: s.endPct, endedBy: s.endedBy }, { merge: true });
    }
    if (result.sessionStarted) {
      const s = result.sessionStarted;
      tx.set(itemRef.collection('chargingSessions').doc(s.sessionId), { ...s, endedAt: null, endPct: null, endedBy: null });
    }
    if (result.releaseReservations) {
      const open = await tx.get(db.collectionGroup('reservations').where('itemId', '==', movement.itemId).where('releasedAt', '==', null));
      for (const d of open.docs) {
        if (d.ref.path.startsWith(`gearTeams/${teamId}/`)) tx.update(d.ref, { releasedAt: at, releaseReason: 'item retired' });
      }
    }
  });
});

// ---------------------------------------------------------------------------
// Informational log rows from reservations and manifest changes
// ---------------------------------------------------------------------------
function logRow(teamId: string, row: Partial<Movement> & { kind: MovementKind }): Promise<unknown> {
  const at = now();
  const full: Movement = {
    eventId: null, itemId: null, actorMemberId: null, subjectMemberId: null, fromLocationId: null, toLocationId: null,
    fromStatus: null, toStatus: null, conditionFlags: [], readingPct: null, payload: {}, conflictReason: null, rejectedReason: null,
    recordedOffline: false, deviceId: null, occurredAt: at, receivedAt: at, applied: true, appliedAt: at, ...row,
  };
  return teamRef(teamId).collection('movements').doc(randomUUID()).set(full);
}

export const onReservationWritten = onDocumentWritten('gearTeams/{teamId}/events/{eventId}/reservations/{itemId}', async (event) => {
  const { teamId, eventId, itemId } = event.params;
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (after && (!before || before.memberId !== after.memberId || (before.releasedAt != null && after.releasedAt == null))) {
    await logRow(teamId, { kind: 'reservation_set', eventId, itemId, actorMemberId: after.createdBy ?? null, subjectMemberId: after.memberId });
  } else if (before && (!after || (before.releasedAt == null && after.releasedAt != null))) {
    await logRow(teamId, { kind: 'reservation_released', eventId, itemId, subjectMemberId: before.memberId, payload: { reason: after?.releaseReason ?? 'removed' } });
  }
});

export const onManifestWritten = onDocumentWritten('gearTeams/{teamId}/events/{eventId}/manifest/{itemId}', async (event) => {
  const { teamId, eventId, itemId } = event.params;
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before && after) await logRow(teamId, { kind: 'manifest_added', eventId, itemId });
  else if (before && !after) await logRow(teamId, { kind: 'manifest_removed', eventId, itemId });
  else if (before && after && before.state !== after.state) {
    await logRow(teamId, { kind: 'packing_state', eventId, itemId, payload: { from: before.state, to: after.state } });
  }
});

// ---------------------------------------------------------------------------
// Event defaults on creation
// ---------------------------------------------------------------------------
export const onEventCreated = onDocumentCreated('gearTeams/{teamId}/events/{eventId}', async (event) => {
  const snap = event.data;
  if (!snap) return;
  const { teamId, eventId } = event.params;
  const ev = snap.data() as Event;
  const team = (await teamRef(teamId).get()).data() as Team;

  const patch: Record<string, unknown> = {};
  if (!ev.siteLocationId) {
    const loc = teamRef(teamId).collection('locations').doc();
    await loc.set({ kind: 'event_site', name: ev.locationName || ev.name, parentId: null, eventId, sortOrder: 50, archivedAt: null });
    patch.siteLocationId = loc.id;
  }
  if (!ev.requestDeadlineOn) {
    const d = new Date(ev.startsOn + 'T00:00:00Z');
    d.setUTCDate(d.getUTCDate() - (team.requestDeadlineDays ?? 5));
    patch.requestDeadlineOn = d.toISOString().slice(0, 10);
  }
  if (ev.chargersAvailable == null) patch.chargersAvailable = team.defaultChargers ?? 4;
  if (!ev.essentials || ev.essentials.length === 0) {
    patch.essentials = (team.essentialsTemplate ?? []).map((e) => ({ id: randomUUID(), ...e, state: 'todo' }));
  }
  if (Object.keys(patch).length > 0) await snap.ref.update(patch);
});

// ---------------------------------------------------------------------------
// Keep each user's team list in sync with their memberships
// ---------------------------------------------------------------------------
export const onMemberWritten = onDocumentWritten('gearTeams/{teamId}/members/{memberId}', async (event) => {
  const { teamId } = event.params;
  const before = event.data?.before.data() as Member | undefined;
  const after = event.data?.after.data() as Member | undefined;
  const uid = after?.uid ?? before?.uid;
  if (!uid) return;
  const userRef = db.doc(`gearUsers/${uid}`);
  if (after && after.active) {
    const team = (await teamRef(teamId).get()).data() as Team | undefined;
    await userRef.set({ teams: { [teamId]: { name: team?.name ?? teamId, shortName: team?.shortName ?? '', role: after.role, tier: after.tier } } }, { merge: true });
  } else {
    await userRef.set({ teams: { [teamId]: FieldValue.delete() } }, { merge: true });
  }
});

// ---------------------------------------------------------------------------
// Callables
// ---------------------------------------------------------------------------
export const createTeam = onCall(async (req) => {
  const uid = uidOf(req);
  const name = str(req.data?.name, 'name');
  const shortName = str(req.data?.shortName, 'shortName', 12);
  const homeName = typeof req.data?.homeName === 'string' && req.data.homeName.trim() ? req.data.homeName.trim() : 'HQ';
  const displayName = typeof req.data?.displayName === 'string' && req.data.displayName.trim() ? req.data.displayName.trim() : (req.auth?.token.name as string | undefined) ?? 'Owner';

  const tRef = db.collection('gearTeams').doc();
  const at = now();
  const team: Team = {
    name, shortName, logoUrl: null, timeZone: 'Europe/Lisbon', endOfDay: '19:00', batteryReadyPct: 80,
    requestDeadlineDays: 5, overdueHours: 6, defaultChargers: 4, kiosk: DEFAULT_KIOSK_SETTINGS,
    labelPrefixes: DEFAULT_LABEL_PREFIXES,
    essentialsTemplate: DEFAULT_ESSENTIALS.map((e) => ({ ...e, ownerMemberId: null })),
    spareOptions: DEFAULT_SPARE_OPTIONS, createdAt: at, createdBy: uid,
  };
  const owner: Member = { uid, displayName, role: 'owner', tier: 'core', phone: null, photoUrl: null, active: true, setup: {}, hasPin: false, createdAt: at };

  const batch = db.batch();
  batch.set(tRef, team);
  batch.set(tRef.collection('members').doc(uid), owner);
  const hq = tRef.collection('locations').doc();
  batch.set(hq, { kind: 'hq', name: homeName, parentId: null, eventId: null, sortOrder: 0, archivedAt: null });
  batch.set(tRef.collection('locations').doc(), { kind: 'hq_sub', name: 'Workshop', parentId: hq.id, eventId: null, sortOrder: 1, archivedAt: null });
  batch.set(tRef.collection('locations').doc(), { kind: 'hq_sub', name: 'Charging bay', parentId: hq.id, eventId: null, sortOrder: 2, archivedAt: null });
  batch.set(tRef.collection('locations').doc(), { kind: 'unknown', name: 'Unknown', parentId: null, eventId: null, sortOrder: 99, archivedAt: null });
  batch.set(db.doc(`gearUsers/${uid}`), { displayName }, { merge: true });
  await batch.commit();
  return { teamId: tRef.id, homeLocationId: hq.id };
});

const pinHash = (salt: string, pin: string) => createHash('sha256').update(salt + pin).digest('hex');

export const setMemberPin = onCall(async (req) => {
  const uid = uidOf(req);
  const teamId = str(req.data?.teamId, 'teamId');
  const memberId = str(req.data?.memberId, 'memberId');
  const pin = str(req.data?.pin, 'pin', 4);
  if (!/^[0-9]{4}$/.test(pin)) throw new HttpsError('invalid-argument', 'PIN must be 4 digits.');

  const caller = await memberOf(teamId, uid);
  if (!caller) throw new HttpsError('permission-denied', 'Not allowed.');
  const isManager = caller.role === 'owner' || caller.role === 'manager';
  const pinsRef = teamRef(teamId).collection('pins');

  if (!isManager) {
    if (memberId !== uid) throw new HttpsError('permission-denied', 'Not allowed.');
    const current = await pinsRef.doc(memberId).get();
    const oldPin = typeof req.data?.oldPin === 'string' ? req.data.oldPin : '';
    if (current.exists && current.data()!.hash !== pinHash(current.data()!.salt, oldPin)) {
      throw new HttpsError('permission-denied', 'Old PIN does not match.');
    }
  }
  const target = await teamRef(teamId).collection('members').doc(memberId).get();
  if (!target.exists) throw new HttpsError('not-found', 'No such member.');

  const all = await pinsRef.get();
  for (const d of all.docs) {
    if (d.id !== memberId && d.data().hash === pinHash(d.data().salt, pin)) {
      throw new HttpsError('already-exists', 'PIN already in use in this team.');
    }
  }
  const salt = randomBytes(8).toString('hex');
  const batch = db.batch();
  batch.set(pinsRef.doc(memberId), { salt, hash: pinHash(salt, pin), setAt: now() });
  batch.update(target.ref, { hasPin: true });
  await batch.commit();
  return { ok: true };
});

/** A manager redeems the code shown on the iPad; the iPad's anonymous uid becomes a kiosk member. */
export const pairKiosk = onCall(async (req) => {
  const uid = uidOf(req);
  const teamId = str(req.data?.teamId, 'teamId');
  const code = str(req.data?.code, 'code', 8).toUpperCase();
  const deviceName = str(req.data?.deviceName, 'deviceName', 60);
  await requireRole(teamId, uid, ['owner', 'manager']);

  const pairing = await db.doc(`gearPairings/${code}`).get();
  if (!pairing.exists || (pairing.data()!.expiresAt as number) < now()) throw new HttpsError('not-found', 'Pairing code not found or expired.');
  const kioskUid = pairing.data()!.uid as string;

  const batch = db.batch();
  const member: Member = { uid: kioskUid, displayName: deviceName, role: 'kiosk', tier: 'guest', phone: null, photoUrl: null, active: true, setup: {}, hasPin: false, createdAt: now() };
  batch.set(teamRef(teamId).collection('members').doc(kioskUid), member);
  const device = teamRef(teamId).collection('devices').doc();
  batch.set(device, { memberId: kioskUid, name: deviceName, boundEventId: null, lastSyncAt: null, unsyncedCount: 0, signedOutAt: null, createdAt: now() });
  batch.update(pairing.ref, { teamId, deviceId: device.id, redeemedAt: now() });
  await batch.commit();
  return { deviceId: device.id };
});

export const createInvitation = onCall(async (req) => {
  const uid = uidOf(req);
  const teamId = str(req.data?.teamId, 'teamId');
  const role = (req.data?.role ?? 'rider') as MemberRole;
  const tier = (req.data?.tier ?? 'team') as RiderTier;
  if (!['manager', 'rider'].includes(role)) throw new HttpsError('invalid-argument', 'Role must be manager or rider.');
  if (!['core', 'team', 'guest'].includes(tier)) throw new HttpsError('invalid-argument', 'Bad tier.');
  await requireRole(teamId, uid, ['owner', 'manager']);
  const token = randomBytes(12).toString('base64url');
  await teamRef(teamId).collection('invitations').doc(token).set({
    role, tier, createdBy: uid, createdAt: now(), expiresAt: now() + 14 * 24 * 3600 * 1000, acceptedBy: null, acceptedAt: null, revokedAt: null,
  });
  return { token };
});

export const acceptInvitation = onCall(async (req) => {
  const uid = uidOf(req);
  const teamId = str(req.data?.teamId, 'teamId');
  const token = str(req.data?.token, 'token', 64);
  const displayName = str(req.data?.displayName ?? (req.auth?.token.name as string | undefined) ?? 'Rider', 'displayName');
  const invRef = teamRef(teamId).collection('invitations').doc(token);

  return db.runTransaction(async (tx) => {
    const inv = await tx.get(invRef);
    if (!inv.exists) throw new HttpsError('not-found', 'Invitation not found.');
    const d = inv.data()!;
    if (d.revokedAt || d.acceptedAt || d.expiresAt < now()) throw new HttpsError('failed-precondition', 'Invitation is no longer valid.');
    const memberRef = teamRef(teamId).collection('members').doc(uid);
    const existing = await tx.get(memberRef);
    if (!existing.exists) {
      const member: Member = { uid, displayName, role: d.role, tier: d.tier, phone: null, photoUrl: null, active: true, setup: {}, hasPin: false, createdAt: now() };
      tx.set(memberRef, member);
    } else {
      tx.update(memberRef, { active: true });
    }
    tx.update(invRef, { acceptedBy: uid, acceptedAt: now() });
    return { memberId: uid };
  });
});

/** Merge a kiosk-only member (no account) into the caller's account after they join. Manager only. */
export const mergeMember = onCall(async (req) => {
  const uid = uidOf(req);
  const teamId = str(req.data?.teamId, 'teamId');
  const kioskOnlyId = str(req.data?.kioskOnlyMemberId, 'kioskOnlyMemberId');
  const accountMemberId = str(req.data?.accountMemberId, 'accountMemberId');
  await requireRole(teamId, uid, ['owner', 'manager']);
  const members = teamRef(teamId).collection('members');
  const [a, b] = await Promise.all([members.doc(kioskOnlyId).get(), members.doc(accountMemberId).get()]);
  if (!a.exists || !b.exists || a.data()!.uid) throw new HttpsError('failed-precondition', 'Can only merge a kiosk-only member into an account member.');

  const batch = db.batch();
  const logs = await teamRef(teamId).collection('movements').where('subjectMemberId', '==', kioskOnlyId).get();
  // movements are immutable for clients but the function may re-point history on merge
  for (const d of logs.docs) batch.update(d.ref, { subjectMemberId: accountMemberId, payload: { ...(d.data().payload ?? {}), mergedFrom: kioskOnlyId } });
  const pin = await teamRef(teamId).collection('pins').doc(kioskOnlyId).get();
  if (pin.exists) { batch.set(teamRef(teamId).collection('pins').doc(accountMemberId), pin.data()!); batch.delete(pin.ref); batch.update(b.ref, { hasPin: true }); }
  batch.update(a.ref, { active: false, mergedInto: accountMemberId });
  await batch.commit();
  return { moved: logs.size };
});

export const closeEvent = onCall(async (req) => {
  const uid = uidOf(req);
  const teamId = str(req.data?.teamId, 'teamId');
  const eventId = str(req.data?.eventId, 'eventId');
  const destination = typeof req.data?.destinationLocationId === 'string' ? req.data.destinationLocationId : null;
  await requireRole(teamId, uid, ['owner', 'manager']);

  const evRef = teamRef(teamId).collection('events').doc(eventId);
  const ev = await evRef.get();
  if (!ev.exists) throw new HttpsError('not-found', 'No such event.');
  if ((ev.data() as Event).phase === 'closed') return { ok: true, alreadyClosed: true };
  const siteId = (ev.data() as Event).siteLocationId;

  const manifest = await evRef.collection('manifest').get();
  const itemRefs = manifest.docs.map((d) => teamRef(teamId).collection('items').doc(d.id));
  const items = itemRefs.length ? await db.getAll(...itemRefs) : [];
  const stillOut = items.filter((s) => s.exists && (s.data() as Item).holderMemberId).map((s) => (s.data() as Item).labelCode);
  if (stillOut.length) throw new HttpsError('failed-precondition', `${stillOut.length} item(s) still checked out: ${stillOut.join(', ')}`);

  const at = now();
  const batch = db.batch();
  const reservations = await evRef.collection('reservations').where('releasedAt', '==', null).get();
  for (const r of reservations.docs) batch.update(r.ref, { releasedAt: at, releaseReason: 'event closed' });
  for (const s of items) {
    if (!s.exists) continue;
    const it = s.data() as Item;
    const dest = destination ?? it.homeLocationId;
    if (it.locationId === siteId && dest) {
      batch.update(s.ref, { locationId: dest, lastMovementAt: at });
      batch.set(teamRef(teamId).collection('movements').doc(randomUUID()), {
        eventId, itemId: s.id, kind: 'location_change', actorMemberId: uid, subjectMemberId: null, fromLocationId: siteId, toLocationId: dest,
        fromStatus: null, toStatus: null, conditionFlags: [], readingPct: null, payload: { reason: 'event closed' }, conflictReason: null,
        rejectedReason: null, recordedOffline: false, deviceId: null, occurredAt: at, receivedAt: at, applied: true, appliedAt: at,
      } satisfies Movement);
    }
  }
  for (const m of manifest.docs) batch.update(m.ref, { state: 'returned', updatedAt: at });
  if (siteId) batch.update(teamRef(teamId).collection('locations').doc(siteId), { archivedAt: at });
  batch.update(evRef, { phase: 'closed', closedAt: at });
  batch.set(teamRef(teamId).collection('movements').doc(randomUUID()), {
    eventId, itemId: null, kind: 'event_closed', actorMemberId: uid, subjectMemberId: null, fromLocationId: null, toLocationId: null,
    fromStatus: null, toStatus: null, conditionFlags: [], readingPct: null, payload: {}, conflictReason: null, rejectedReason: null,
    recordedOffline: false, deviceId: null, occurredAt: at, receivedAt: at, applied: true, appliedAt: at,
  } satisfies Movement);
  await batch.commit();
  return { ok: true, itemsMoved: items.length };
});

// keep the unused-import checker honest about types used only in annotations
export type { DocumentReference, Transaction };
