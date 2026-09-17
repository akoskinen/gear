# Firestore Data Model (v0.1)

The concrete shape of the data in the `efoilracingprofiles` Firebase project. It implements the model from the [product outline](01-product-outline.md) and the rules from the view specs. Types are in `packages/shared/src/types.ts`; the security rules in `firestore.rules`; the server-side logic in `functions/src/index.ts`.

## 1. Principles

- **Everything lives under `gearTeams/{teamId}`.** The project is shared with efoil.racing profiles, so the app's collections are namespaced and never touch existing ones. A person's own document is `gearUsers/{uid}`.
- **Team isolation is enforced in the rules**, per document, by reading the caller's member document for that team. A member of another team sees nothing.
- **Item state changes only through the movement log.** Clients append to `movements`; a Cloud Function applies each row to the item in a transaction. Rules forbid clients from touching holder, location, status, or battery fields on an item directly.
- **Timestamps are epoch milliseconds** as plain numbers everywhere, so the browser, the kiosk's offline queue, and the functions share one representation. Dates without time (event days) are ISO strings.
- **Document ids carry meaning where it removes a class of bugs.** Member id is the auth uid for account holders. Request and roster docs are keyed by member. Reservation and manifest docs are keyed by item, which gives one active reservation per item per event for free. Movement ids are the client's event id, which makes offline replay idempotent.
- **Battery state is denormalized onto the item** (last reading and open charging session), so the estimate needs only the item document. History goes to subcollections.

## 2. Collections

```
gearUsers/{uid}                       displayName, photoUrl, phone, teams: { [teamId]: { name, shortName, role, tier } }
gearPairings/{code}                   uid, createdAt, expiresAt, teamId?, deviceId?, redeemedAt?     (kiosk pairing)

gearTeams/{teamId}                    Team: name, shortName, timeZone, endOfDay, batteryReadyPct, requestDeadlineDays,
                                      overdueHours, defaultChargers, kiosk{}, labelPrefixes{}, essentialsTemplate[], spareOptions[]
  members/{memberId}                  Member: uid|null, displayName, role, tier, phone, photoUrl, active, setup{slot: {source, description}}, hasPin
  pins/{memberId}                     salt, hash (sha256(salt+pin)), setAt              read: staff only; write: function only
  invitations/{token}                 role, tier, createdBy, expiresAt, acceptedBy, acceptedAt, revokedAt
  locations/{locationId}              kind (hq | hq_sub | vehicle | event_site | unknown), name, parentId, eventId, sortOrder, archivedAt
  batteryTypes/{typeId}               name, capacityNote, minutesTo80, minutes80To100, archivedAt
  catalogue/{modelId}                 category, name, visibleToRiders, sortOrder
  devices/{deviceId}                  memberId (the kiosk member), name, boundEventId, lastSyncAt, unsyncedCount, signedOutAt
  notifications/{id}                  memberId, kind, title, body, link, readAt, createdAt

  items/{itemId}                      Item: category, labelCode, model, spec{}, serial, ownerMemberId|null, homeLocationId,
                                      locationId|null, holderMemberId|null, status, statusReason, expectedBackOn, batteryTypeId,
                                      firmwareVersion, cycleCount, chargerSpeedFactor, photos[], retiredAt, lastMovementAt,
                                      battery: { lastReading: {pct, at, source, memberId, eventId} | null,
                                                 charging: {sessionId, startedAt, startPct, speedFactor, eventId, startedBy} | null }
    notes/{id}                        authorMemberId, body, createdAt
    readings/{id}                     pct, at, source, memberId, eventId, movementId        history, function-written
    chargingSessions/{sessionId}      startedAt, startPct, speedFactor, eventId, startedBy, endedAt, endPct, endedBy

  events/{eventId}                    Event: name, type, locationName, venueNotes, timeZone, startsOn, endsOn, phase,
                                      requestDeadlineOn, chargersAvailable, chargerSpeedFactor, siteLocationId, essentials[], closedAt
    roster/{memberId}                 status, invitedAt, respondedAt
    requests/{memberId}               status, batteriesPerDay, firmwareNote, notes, transportOwnGear, setup{}, lines[],
                                      changedSincePlanned, declineReason, submittedAt, updatedAt
    reservations/{itemId}             itemId, memberId, createdBy, createdAt, releasedAt, releaseReason
    manifest/{itemId}                 state (planned | packed | loaded | on_site | returned), fromLineId, createdAt, updatedAt

  movements/{clientEventId}           Movement: eventId, itemId, kind, actorMemberId, subjectMemberId, fromLocationId, toLocationId,
                                      fromStatus, toStatus, conditionFlags[], readingPct, payload{}, conflictReason, rejectedReason,
                                      recordedOffline, deviceId, occurredAt, receivedAt, applied, appliedAt
```

Small lists that are read together are embedded rather than made into collections: the essentials template and per-event essentials, request lines, label prefixes, kiosk settings, and a rider's setup. Each stays well under Firestore's document size limit at any realistic team size.

## 3. Roles and what each may do

| | owner | manager | rider | kiosk |
|---|---|---|---|---|
| Read team data | yes | yes | yes | yes |
| Rename team, transfer ownership | yes | | | |
| Team settings, members, inventory metadata, events, reservations, manifest | yes | yes | | |
| Read PIN hashes and devices | yes | yes | | yes |
| Append manager movement kinds (force, location, status, readings) | yes | yes | | |
| Append kiosk movement kinds (checkout, checkin, readings, availability) | yes | yes | | as itself |
| Own profile, own setup, own roster answer, own request, own notifications | yes | yes | yes | |
| Update item state directly | | | | |
| Write pins, readings, charging sessions, informational log rows | | | | |

The last two rows are function-only. Functions run with admin privileges and are the only path for those writes.

## 4. The movement pipeline

1. A client writes `movements/{clientEventId}` with `applied: false` and no conflict or rejection fields. The rules check the caller's role against the kind and, for the kiosk, that it names itself as actor.
2. `onMovementCreated` runs. Informational kinds are marked applied. Stateful kinds open a transaction that reads the item, the team's readiness threshold, the event (for the site location and charger speed factor), the active reservation for that item, and the battery type.
3. `applyMovement()` from the shared package computes the result: an item patch, movement fields (from/to), readings to append, a charging session to close or open, and either a `conflictReason` (applied but disagreed with state) or a `rejectedReason` (not applied, kept as a record).
4. The transaction writes everything and marks the movement applied. A second delivery of the same event finds `applied: true` and stops.

Offline, the kiosk queues movements locally, applies them to its cached copy of the items with the same `applyMovement()` so its screens stay right, and lets Firestore's persistence replay the writes on reconnect. Because the document id is the client event id, a replayed write is a no-op.

## 5. Kiosk identity

The iPad signs in with anonymous auth and writes `gearPairings/{code}` with its uid and a short code shown on screen. A manager enters the code in the hub, which calls `pairKiosk`. The function creates a `kiosk` member whose id is that uid and a `devices` document. From then on the iPad reads the team like any member, reads PIN hashes for offline verification, and appends kiosk movements as itself. Signing the device out sets `signedOutAt`, and the next launch clears its cache and returns to pairing.

## 6. PINs

`setMemberPin` hashes the 4-digit PIN with a random salt using SHA-256. The kiosk verifies locally against `pins/{memberId}` so PIN entry works offline, and tracks failed attempts and the 60-second lockout on the device. A rider changes their own PIN by supplying the old one; a manager can set anyone's. Uniqueness within the team is checked by the function. As the specs say, a 4-digit PIN is a convenience lock for a shared iPad, not a security boundary.

## 7. Callables

| Function | Who | Does |
|---|---|---|
| `createTeam` | any signed-in user | Team with defaults, owner membership, HQ and standard locations. Onboarding steps 1 and 2. |
| `createInvitation`, `acceptInvitation` | manager / invitee | Invite link tokens with role and tier, 14-day expiry. |
| `setMemberPin` | manager, or the member with the old PIN | Salted hash, uniqueness check, `hasPin` flag. |
| `pairKiosk` | manager | Turns an iPad's anonymous uid into a kiosk member and device. |
| `mergeMember` | manager | Folds a kiosk-only member's history and PIN into an account member. |
| `closeEvent` | manager | Refuses while anything is checked out; releases reservations; sends items home or to a chosen location; archives the site; logs the close. |

## 8. Triggers

| Trigger | Does |
|---|---|
| `onMovementCreated` | The pipeline above. |
| `onEventCreated` | Site location, request deadline, charger count, essentials from the template. |
| `onReservationWritten`, `onManifestWritten` | Informational log rows so item history is complete. |
| `onMemberWritten` | Keeps `gearUsers/{uid}.teams` in sync for the team switcher. |

## 9. Indexes

`firestore.indexes.json` declares composite indexes for the queries the views need: movements by item, event, and rider ordered by time; items by category and label and by holder; reservations across events by item and by member (collection group); notifications by member.

## 10. Tests

- `packages/shared/test/` — 29 unit tests on the estimate and on `applyMovement`, mirroring the scenarios in the kiosk and battery specs.
- `tests/rules/rules.test.ts` — 20 rules tests against the Firestore emulator: team isolation, the item state lock, kiosk and manager movement kinds, PIN visibility, self-service boundaries for riders, and event and request rules.

```
npm test          # both
npm run test:shared
npm run test:rules   # starts the emulator, needs Java
```
