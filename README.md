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
- [docs/08-build-plan.md](docs/08-build-plan.md) — stack, repository layout, schema overview, milestones.

## Backend

The schema lives in `supabase/migrations/` and is tested by `supabase/tests/`. Run both against any local Postgres 15+ (as a superuser) with:

```
scripts/db-test.sh
```
