# Product Outline (draft v0.2)

A working structure for the gear tracking and rider management app, derived from the [initial brief](00-brief.md). Everything here is a proposal to be refined together, view by view. Decisions taken so far are in section 5; remaining open points are marked **Open**.

## 1. Who uses it

| Role | Person(s) | Primary device | Primary need |
|---|---|---|---|
| Logistics manager | Axel | Laptop (web) and iPad | Know where every item is, what state it is in, and what each rider needs for the next event |
| Core rider | Manel, Antti, Pete, Carmine | iPhone | Reserved gear is guaranteed; state needs ahead of time; quick check-out at the tent |
| Team / guest rider | Other riders at an event | iPhone, shared iPad | Find out what is available; check gear out and back in |
| Kiosk | Shared iPad at the event tent | iPad (mounted, possibly offline) | Large-button check-out / check-in; rider identifies with a PIN |

Riders are assigned a **tier** (core, team, guest). Tier drives allocation rules, not screen access.

## 2. Core concepts (data model, first pass)

- **Team.** The tenant. Every other record belongs to exactly one team. Lift Foils is the first team; other teams join later through efoil.racing. A person can belong to more than one team (e.g. a rider who is also on a national squad).
- **Member.** A person's membership in a team: role (manager, rider), tier (core, team, guest), display name, and a kiosk PIN (4 digits, unique within the team, set by the manager).
- **Rider setup.** A member's declared default setup, one slot each for board, mast and fuselage, front wing, stabilizer, propulsion, battery, controller. Each slot is "own" (with a short description) or "from the team". Some riders bring their own board and propulsion and only need batteries; others use the full team setup. The setup drives packing and demand counts, and can be overridden per event in the rider's request.
- **Event.** Name, location, start/end dates, type (race, training camp, testing day, demo), status (planned, packing, live, wrap-up, closed). Every operational action belongs to an event, except standing inventory at HQ.
- **Location.** HQ Martinchel; an event site (e.g. Menton); a vehicle / in transit; "with rider". A gear item has exactly one current location.
- **Gear item.** One physical, labeled object. Has an **owner**: the team, or a named member for rider-owned gear that travels with the team. Rider-owned items are never offered on the kiosk, cannot be reserved, and are excluded from stock counts; they exist so they can appear on a manifest for transport. Category: board, mast, front wing, stabilizer / rear wing, fuselage, propulsion unit (motor + prop), battery, controller / remote, charger, spare part. Fields: label code (what is printed on the item; short, human-readable, and stable so the same code can later be etched as a QR), model / spec (e.g. "170 front wing"), serial, home base, condition status (ready, needs check, in repair, retired), notes, photo. Batteries and propulsion units also carry firmware version and, for batteries, charge state and cycle count.
- **Kit (optional grouping).** A named set of items that usually travel together, e.g. "Antti race setup". Riders swap wings constantly, so tracking stays at item level; a kit is only a convenience for packing and reservations.
- **Reservation.** Gear item × rider × event, set by the manager while planning the event. This is the "priority tier" lock from the brief: a reserved item can only be checked out by its rider, or released by the manager. Reservations expire when the event closes. The manager can copy last event's reservations as a starting point.
- **Rider request (pre-event inquiry).** Rider × event: the rider's setup for this event (defaults from their declared setup), wanted gear for the team-supplied slots (from the catalogue or free text), firmware preferences, spare parts, notes. Status: submitted, seen by Axel, planned, fulfilled, declined with reason.
- **Event manifest.** The list of gear items and non-gear essentials that go to a given event, with packed / loaded / on site / returned states. Built from reservations, rider requests, and Axel's judgement.
- **Essentials checklist.** Non-gear items per event (tents, water, lunch, tools, first aid, generator, ...) from a reusable template so the routine is standardized.
- **Movement log.** Append-only record of every check-out, check-in, transfer, and status change: who, which item, which event, when, from where to where. This replaces the Excel sheet as the source of truth.
- **Battery reading.** Time-stamped charge level per battery, reported by the rider at return (and optionally at take), plus charging sessions with start and end times. Combined with per-type charge times this gives an estimated charge and ready time without charger integration. See [05-battery-charge-estimation.md](05-battery-charge-estimation.md).
- **Battery type.** Model name plus charge model: time from 0 to 80 % and from 80 to 100 %.

## 3. Views (first pass)

### Calendar / events
- List and month view of upcoming and past events.
- Tapping an event opens its **event hub**. Everything below is scoped to the selected event unless noted.

### Event hub (Axel)
- **Status strip:** days to go, riders confirmed, requests open, items packed vs planned, batteries charged.
- **Roster:** who is coming, tier, and their open requests.
- **Requests:** inbox of rider requests; Axel marks each planned / fulfilled / declined.
- **Manifest:** what is going; packing progress; essentials checklist.
- **Live board (during the event):** every item at the site with its current holder; out-of-place and overdue items highlighted; batteries by charge state.

### Inventory (Axel, not event-scoped)
- All items grouped by category, filterable by location, status, reservation.
- Item detail: history from the movement log, condition notes, photos, reservations.
- Maintenance queue: items marked needs check / in repair.

### Kiosk (shared iPad at the tent)
- Two big actions: **Take gear** and **Return gear**.
- Identify rider: tap your name on the roster grid, then enter your 4-digit PIN.
- Identify item: pick from a large-tile list by category and label code, filtered to what this rider may take. QR scanning is a later addition once labels are etched.
- Confirmation screen, then back to idle. No login, no menus. Works offline and syncs later.
- Reserved items either do not appear for other riders or show a locked state with the owner's name.

### Rider app (iPhone)
- **My events:** upcoming events and whether I am on the roster.
- **My requests:** submit and edit the pre-event inquiry per event.
- **My gear:** what I currently hold, what is reserved for me, quick return.
- Notifications: request answered; item overdue; battery ready.

## 4. Allocation rules (from the brief, made explicit)

1. If the item is reserved for a rider, only that rider (or Axel) can check it out.
2. Otherwise, if the item is at the event site and status is ready, any rostered rider can check it out.
3. Otherwise the kiosk shows "ask Axel" and the request is logged for Axel to see.
4. Every check-out and check-in writes a movement log entry with rider, item, event, and timestamp.
5. Reservations are per event and expire when the event closes. The manager sets them while planning, typically by copying the previous event's reservations and adjusting.

## 5. Decisions

| # | Question | Decision | Consequence |
|---|---|---|---|
| 1 | Platform | Native iOS / iPadOS for riders and the kiosk. Axel also gets a web dashboard for the laptop. | One shared backend with an API; two client codebases (SwiftUI app, web app). The web dashboard is the primary planning surface, the iPad the primary event-day surface. |
| 2 | Rider identity at kiosk | 4-digit PIN | Roster grid then PIN pad. No accounts needed on the shared iPad. PINs are per team and set by the manager. |
| 3 | Labels | No scanning in v1. Etched QR codes later. | Label codes must be short, readable, and stable. The kiosk picks items from tiles now; scanning slots in as an alternative input later without changing the flow. |
| 4 | Reservations | Set per event by Axel | Reservation is event-scoped. Planning view needs a fast "copy from last event" action. |
| 5 | Tenancy | Other teams should be able to use it later | Team is the top-level entity from day one. All data is partitioned by team; people can belong to several teams. Authentication and roles are per team. |
| 6 | Gear categories | Confirmed | Category list in section 2 stands. |
| 8 | Rider-owned gear | Declared, not tracked. Riders state which slots they bring themselves; the movement log covers team gear only. | "My setup" in the rider profile, setup review at the top of the request, a setup matrix with demand totals in the hub roster, and an owner field on gear items for transport-only entries. |
| 7 | Battery charge tracking | Estimate from rider-reported percentage at return, charging start time, and known charge times per battery type | No charger Bluetooth dependency. Kiosk asks one extra tap per battery at return. Charger integration is no longer planned. |

## 5b. Remaining open points

- **Open: offline.** Race sites often have poor connectivity. Proposal: the kiosk and rider app work offline and sync; the movement log is designed to merge without conflicts. Assumed yes unless told otherwise.
- **Open: technology stack.** Recommendation: a hosted Postgres backend with built-in auth and per-team row-level security (Supabase or similar), SwiftUI for iPhone and iPad, and a web dashboard sharing the same API. To be confirmed before build starts.

## 6. Suggested phasing

1. **Phase 1, replace the spreadsheet:** teams and members, events, inventory, manifest, essentials checklist, per-event reservations, movement log, kiosk check-out / check-in with PIN, rider requests. Web dashboard for Axel plus iPad kiosk.
2. **Phase 2, rider self-service:** rider app with notifications, reservations visible to riders, battery ready times visible to riders.
3. **Phase 3, hardware and scale:** QR scanning at the kiosk, label etching workflow, per-battery charge calibration, onboarding for additional teams.
