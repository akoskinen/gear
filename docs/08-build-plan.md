# Build Plan (draft v0.1)

How the specification becomes a shipped product: the stack, the repository layout, the backend schema that now exists, and the milestones in the order that gets the kiosk to a real event soonest.

Related: all of `docs/00` to `docs/07`. The schema is in `supabase/migrations/`, its tests in `supabase/tests/`.

## 1. Stack

| Layer | Choice | Why |
|---|---|---|
| Database, auth, realtime, storage | Supabase (Postgres 15+) | Row-level security gives per-team isolation in the database itself, which is what makes multi-team safe from day one. Auth covers Sign in with Apple and email links. Realtime feeds the Live board and the kiosk. Hosted, so no servers to run. |
| Business rules | SQL functions and triggers in Postgres | The movement log is the source of truth, so the rules that apply a movement live next to it and cannot be bypassed by a client. Tested with plain SQL. |
| Kiosk and rider app | SwiftUI, one Xcode project, two targets (iPad kiosk, iPhone rider) | Native gives offline storage, Guided Access, and the large-touch performance the tent needs. Shared models and sync code between targets. |
| Manager web dashboard | TypeScript, React, Vite, Tailwind | Axel's laptop surface. A plain single-page app against the Supabase API with no server of its own. |
| Offline sync | Local queue of movements with client event ids, replayed on reconnect | The movement log's idempotency key makes replay safe; the database flags conflicts instead of rejecting. |
| Notifications | Supabase database webhooks to an edge function that sends APNs pushes | Small, and only needed from milestone 4. |

To confirm before milestone 1: an Apple Developer account for the team, and a Supabase project (free tier is enough until the second team).

## 2. Repository layout

```
gear/
├── docs/                    specification (this set)
├── supabase/
│   ├── migrations/          schema, one file per change, applied in order
│   ├── tests/               SQL behaviour tests, run by scripts/db-test.sh
│   ├── seed.sql             (M1) demo team for local development
│   └── functions/           (M4) edge functions: push notifications
├── apps/
│   ├── ios/                 (M2, M4) Xcode project: Kiosk and Rider targets, shared package
│   └── web/                 (M1) manager dashboard
└── scripts/
    └── db-test.sh           fresh database, migrations, tests
```

## 3. Backend schema (done, milestone 0)

`supabase/migrations/20260917000000_initial_schema.sql` implements the data model from the outline. 27 tables, 17 enums, and the functions below. `supabase/tests/schema_test.sql` runs 52 assertions against a fresh database.

### 3.1 Tables by area

| Area | Tables |
|---|---|
| Identity | `profiles`, `teams`, `team_members`, `member_pins`, `rider_setups`, `invitations` |
| Team settings | `locations`, `battery_types`, `label_prefixes`, `catalogue_models`, `essentials_template` |
| Events | `events`, `event_roster`, `event_essentials` |
| Gear | `gear_items`, `item_notes`, `item_photos` |
| Planning | `rider_requests`, `request_setup_slots`, `request_lines`, `reservations`, `manifest_items` |
| Batteries | `battery_readings`, `charging_sessions` |
| Log | `movements` (append-only) |
| Devices and messages | `kiosk_devices`, `notifications` |

Every table carries `team_id`, and every policy starts from it.

### 3.2 The movement log is the write path for item state

Clients never update an item's holder, location, or status directly. They insert a row into `movements` and a trigger applies the change:

| kind | Effect |
|---|---|
| `checkout` | Holder set, location cleared. Flags `conflict_reason` if the item was not ready, was with someone else, or is reserved for another rider. Never rejects, so an offline kiosk's record is kept. A battery leaving a charger closes its charging session; an optional reading is stored. |
| `checkin` | Holder cleared, location set to the event site (or home). Condition flags move the item to `needs_check`. A battery reading is stored, the cycle count grows by the fraction used, and `on_charger: true` opens a charging session. |
| `force_checkout`, `force_checkin` | Same, by a manager, without conflict flags. |
| `location_change`, `status_change` | Direct moves and status changes; leaving `ready` requires a reason. Retiring releases reservations. |
| `battery_reading` | Stores a reading and restarts any open charging session from that point. |
| `charging_started`, `charging_ended` | Manager taps on the Live board. |
| `reservation_set`, `manifest_added`, `packing_state`, … | Informational rows written by triggers on those tables, so the item history is complete. |

Offline replay is safe: `(team_id, client_event_id)` is unique, so a duplicate insert fails and the client drops it from the queue.

### 3.3 Battery estimate

`battery_estimate(item_id, at)` implements the piecewise-linear model from the battery spec: a fast segment to 80 % and a slow tail to 100 %, scaled by the event's charger speed factor. It returns the current percentage, whether it is an estimate, and the ready and full times. The `battery_status` view combines it with holder and status into the strip state used by the hub, kiosk, and rider app: `in_use`, `charging`, `ready`, `low`, `unknown`, or the item status when not ready.

### 3.4 Roles and row-level security

Four roles per team membership: `owner`, `manager`, `rider`, `kiosk`. Helper functions `is_member`, `is_manager`, `is_staff`, and `my_member_id` drive the policies.

- Members read their team's data. Managers write it.
- Riders write their own requests, setup, roster answer, and notifications, and nothing else.
- A kiosk device signs in as a `kiosk` member. It may insert only kiosk movement kinds with itself as actor, and can fetch the team's salted PIN hashes through `kiosk_pin_hashes()` for offline PIN entry. It cannot edit inventory.
- `member_pins` has no client access at all; `set_member_pin` and `verify_member_pin` are the only paths. Three failures lock a member for 60 seconds. PINs are 4 digits and are a convenience lock, not a security boundary, as the specs say.
- A member of another team sees zero rows everywhere, tested.

### 3.5 Other rules in the database

- Creating an event creates its site location, defaults the request deadline and charger count from team settings, and copies the essentials template.
- An item cannot be added to two overlapping events' manifests.
- `close_event()` refuses while anything is checked out, releases reservations, sends items home or to a chosen destination, archives the site, and logs the close.
- `create_team()` sets up HQ, label prefixes, and the essentials template, which is onboarding steps 1 and 2.
- Movements cannot be updated or deleted.

### 3.6 Running the schema locally

```
scripts/db-test.sh                      # any local Postgres 15+ as a superuser
PGPORT=54322 PGUSER=postgres scripts/db-test.sh   # against `supabase start`
```

Each schema change is a new migration file. The test file grows with it.

## 4. Milestones

Ordered so that a real event can run on the kiosk as early as possible, with the spreadsheet still available as a fallback.

### M0 Foundations (done)
- Repository, specification, schema, tests.

### M1 Manager web, minimum to plan an event
- Sign in, create team, invite members, set PINs.
- Inventory: list, add, "add another like this", spreadsheet import, item detail with history.
- Events: create, roster, request inbox (read-only until M4 brings the rider app; Axel can enter requests on behalf), manifest with packing states, reservations, essentials checklist.
- Live board with the battery strip and manual On charger / Off charger / Set reading.
- Done when Axel can plan the next event entirely in the web app, with the spreadsheet retired for inventory.

### M2 Kiosk, the piece that proves it
- iPad target: idle, roster grid, PIN, rider home, take flow with tile states, return flow with battery percentage and condition chips, confirmation, manager menu.
- Offline cache of roster, PIN hashes, manifest, reservations, battery strip; movement queue with replay.
- Guided Access setup notes.
- Done when one event runs with every take and return logged through the kiosk and Axel's Live board reflecting it live.

### M3 Hub polish from the first event
- Needs attention panel with all sources from the hub spec.
- Setup matrix and demand totals.
- Conflict records surfaced and resolvable.
- Whatever the first event taught us.

### M4 Rider app
- iPhone target: events with confirm, request form with setup review and "same as last event", my gear with reservations and the battery strip.
- Push notifications via an edge function.
- Kiosk gains the optional "shows:" reading at take, now that calibration pairs are useful.

### M5 Settings, onboarding, second team
- Full settings screens, invitation links, kiosk device management, export.
- Onboarding checklist. Bring in a second team as the test of tenancy.
- Battery type calibration from observed pairs.

## 5. Working method

- **Specs stay the source of truth.** A change in behaviour is a change to the spec first, then the migration, then the clients.
- **Database rules are tested in SQL** before any client code depends on them. `scripts/db-test.sh` runs in CI on every push.
- **Design in Figma against the specs**, one view at a time, then build the SwiftUI or React screens from those designs. The kiosk screens come first since they are the most constrained.
- **Ship to the team through TestFlight** from M2 onwards; the manager web app deploys as a static site.

## 6. Open items before M1 starts

- Supabase project and Apple Developer account in place.
- Axel's current spreadsheet, to shape the import and to seed the demo data.
- Ballpark charge times per battery type, to seed `battery_types`.
- Decision on the web app hosting (any static host works).
