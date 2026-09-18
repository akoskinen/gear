# gear

Gear tracking and rider management for an eFoil racing team.

## Specification

- [docs/00-brief.md](docs/00-brief.md) — the original brief.
- [docs/01-product-outline.md](docs/01-product-outline.md) — roles, data model, views, allocation rules, decisions, and phasing.
- [docs/02-event-hub-spec.md](docs/02-event-hub-spec.md) — detailed spec of the manager's per-event hub view.
- [docs/03-kiosk-spec.md](docs/03-kiosk-spec.md) — the shared iPad check-out / check-in kiosk flow.
- [docs/04-inventory-spec.md](docs/04-inventory-spec.md) — inventory list, item detail, label codes, locations, and status lifecycle.
- [docs/05-battery-charge-estimation.md](docs/05-battery-charge-estimation.md) — battery charge and ready-time estimation from rider readings and charge times, no charger integration.
- [docs/06-rider-app-spec.md](docs/06-rider-app-spec.md) — the rider's iPhone app: events, pre-event requests, my gear, notifications.
- [docs/07-team-settings-spec.md](docs/07-team-settings-spec.md) — roles, members, PINs, team defaults, kiosk devices, and onboarding a new team.
- [docs/08-build-plan.md](docs/08-build-plan.md) — stack, repository layout, milestones.
- [docs/09-firestore-data-model.md](docs/09-firestore-data-model.md) — collections, roles, the movement pipeline, callables and triggers.
- [docs/10-inventory-ux.md](docs/10-inventory-ux.md) — Axel's inventory experience, redesigned around his real warehouse sheet: places, walks, two tracking modes, reorder, import.

## Backend

Firebase, in the `efoilracingprofiles` project. Everything lives under `gearTeams/{teamId}` in Firestore.

- `packages/shared/` — types, the battery estimate, and `applyMovement()`, shared by functions and the web app.
- `functions/` — Cloud Functions: the movement processor, event defaults, log rows, and callables.
- `firestore.rules`, `firestore.indexes.json` — security rules and composite indexes.
- `tests/rules/` — rules tests against the Firestore emulator.

```
npm install
npm test              # shared unit tests + rules tests (rules tests start the emulator; needs Java)
npm run build         # type-check and compile shared + functions
```

## Data

- `data/axel-inventory-2026-09.csv` — Axel's warehouse sheet as exported, the source for the import and the demo data.
- `data/axel-inventory-mapping.json` — the same rows classified into category, tracking mode and size; the importer's seed.

## Prototypes

- `prototypes/inventory.html` — clickable prototype of Axel's inventory experience (docs/10), built on the real sheet. Open the file in a browser; nothing is saved.
