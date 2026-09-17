# Build Plan (v0.2)

How the specification becomes a shipped product: the stack, the repository layout, the backend that now exists, and the milestones in the order that gets the kiosk to a real event soonest.

Related: all of `docs/00` to `docs/07`, and the [Firestore data model](09-firestore-data-model.md).

## 1. Stack

| Layer | Choice | Why |
|---|---|---|
| Database, auth, hosting, functions | Firebase, in the existing `efoilracingprofiles` project | Free at this scale with no idle pausing. Riders can share one login with efoil.racing, which is the path to other teams later. Firestore's built-in offline persistence and write queue is what the kiosk needs. |
| Business rules | Cloud Functions (TypeScript, Node 22, europe-west1) plus a shared pure-logic package | The movement log is the source of truth; the function that applies it is the only writer of item state. The same pure function runs in the kiosk to derive offline state. |
| Clients | One web app (TypeScript, React, Vite, Tailwind), installable as a PWA | Serves the iPad kiosk, the rider's phone on iOS or Android, and Axel's laptop from one codebase. No app store. Guided Access on the iPad works with an installed web app. |
| Offline | Firestore persistence for reads and queued writes; service worker for the app shell | Movement ids are client event ids, so replay is idempotent. |
| Notifications | Firebase Cloud Messaging web push | Android and desktop immediately; iPhone once the app is added to the home screen. |

## 2. Repository layout

```
gear/
├── docs/                    specification and this plan
├── packages/shared/         types, battery estimate, applyMovement — used by functions and the web app
├── functions/               Cloud Functions
├── tests/rules/             Firestore rules tests (emulator)
├── apps/web/                (M1) the web app: manager hub, kiosk, rider views
├── firestore.rules          security rules
├── firestore.indexes.json   composite indexes
├── firebase.json, .firebaserc
└── package.json             npm workspaces; `npm test` runs everything
```

## 3. Backend (done, milestone 0)

- Data model, roles, and the movement pipeline: see [09-firestore-data-model.md](09-firestore-data-model.md).
- `packages/shared`: 29 tests on the battery estimate and movement application.
- `firestore.rules`: 20 emulator tests on isolation and the write boundaries.
- `functions`: movement processor, event defaults, log rows, user team list, and six callables.

Not yet done: deploying to the project. That is the first task of M1 and needs the Blaze plan enabled for Cloud Functions, with a budget alert set.

## 4. Milestones

### M0 Foundations (done)
Specification, data model, rules, functions, tests.

### M1 Manager web, minimum to plan an event
- Deploy rules, indexes, and functions. Enable Sign in with Google and Apple, and email link.
- Web app shell: sign in, create team, team switcher, invite by link, set PINs.
- Inventory: list with filters, add, "add another like this", spreadsheet import, item detail with history.
- Events: create, roster, requests inbox (Axel enters requests on behalf until M4), manifest with packing states, reservations, essentials checklist.
- Live board with the battery strip and On charger / Off charger / Set reading.
- Done when Axel plans the next event in the app and the spreadsheet is retired for inventory.

### M2 Kiosk, the piece that proves it
- Kiosk route in the same app, full-screen, installed on the iPad: pairing, idle, roster grid, PIN, rider home, take with tile states, return with battery percentage and condition chips, confirmation, manager menu.
- Offline: cached roster, PIN hashes, manifest, reservations and items; local queue with `applyMovement()` for derived state; sync indicator.
- Guided Access setup notes.
- Done when one event runs with every take and return through the kiosk and the Live board following in real time.

### M3 Hub polish from the first event
- Needs attention panel with all sources, setup matrix with demand totals, conflict records, whatever the event taught us.

### M4 Rider views
- Rider routes: events with confirm, request form with setup review and "same as last event", my gear, battery strip.
- Web push notifications; the kiosk's optional "shows:" reading at take.

### M5 Settings, onboarding, second team
- Full settings, device management, export, onboarding checklist. A second team through efoil.racing as the tenancy test. Battery type calibration from observed pairs.

## 5. Working method

- Specs stay the source of truth: spec, then shared logic and rules with tests, then screens.
- `npm test` runs shared and rules tests; it goes into CI on every push.
- Design each view in Figma against its spec, kiosk first, then build the React screens from those designs.
- Deploy the web app with Firebase Hosting from the main branch; the team uses it from a URL and installs it to the home screen.

## 6. Before M1 starts

- Blaze plan on `efoilracingprofiles` with a budget alert.
- Auth providers enabled (Google, Apple, email link) and the app's domain authorized.
- Axel's spreadsheet, to shape the import and seed demo data.
- Ballpark charge times per battery type.
