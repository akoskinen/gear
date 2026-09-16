# Product Outline (draft v0.1)

A working structure for the gear tracking and rider management app, derived from the [initial brief](00-brief.md). Everything here is a proposal to be refined together, view by view. Sections marked **Open** need a decision before screens are designed.

## 1. Who uses it

| Role | Person(s) | Primary device | Primary need |
|---|---|---|---|
| Logistics manager | Axel | iPad / laptop | Know where every item is, what state it is in, and what each rider needs for the next event |
| Core rider | Manel, Antti, Pete, Carmine | iPhone | Reserved gear is guaranteed; state needs ahead of time; quick check-out at the tent |
| Team / guest rider | Other riders at an event | iPhone, shared iPad | Find out what is available; check gear out and back in |
| Kiosk | Shared iPad at the event tent | iPad (mounted, possibly offline) | Large-button check-out / check-in, no login friction |

Riders are assigned a **tier** (core, team, guest). Tier drives allocation rules, not screen access.

## 2. Core concepts (data model, first pass)

- **Event.** Name, location, start/end dates, type (race, training camp, testing day, demo), status (planned, packing, live, wrap-up, closed). Every operational action belongs to an event, except standing inventory at HQ.
- **Location.** HQ Martinchel; an event site (e.g. Menton); a vehicle / in transit; "with rider". A gear item has exactly one current location.
- **Gear item.** One physical, labeled object. Category: board, mast, front wing, stabilizer / rear wing, fuselage, propulsion unit (motor + prop), battery, controller / remote, charger, spare part. Fields: label code (what is printed on the item), model / spec (e.g. "170 front wing"), serial, home base, condition status (ready, needs check, in repair, retired), notes, photo. Batteries and propulsion units also carry firmware version and, for batteries, charge state and cycle count.
- **Kit (optional grouping).** A named set of items that usually travel together, e.g. "Antti race setup". Riders swap wings constantly, so tracking stays at item level; a kit is only a convenience for packing and reservations.
- **Reservation.** Gear item × rider × scope (standing, or one event). This is the "priority tier" lock from the brief: a reserved item can only be checked out by its rider, or released by Axel.
- **Rider request (pre-event inquiry).** Rider × event: wanted gear (from the catalogue or free text), firmware preferences, spare parts, notes. Status: submitted, seen by Axel, planned, fulfilled, declined with reason.
- **Event manifest.** The list of gear items and non-gear essentials that go to a given event, with packed / loaded / on site / returned states. Built from reservations, rider requests, and Axel's judgement.
- **Essentials checklist.** Non-gear items per event (tents, water, lunch, tools, first aid, generator, ...) from a reusable template so the routine is standardized.
- **Movement log.** Append-only record of every check-out, check-in, transfer, and status change: who, which item, which event, when, from where to where. This replaces the Excel sheet as the source of truth.
- **Battery reading.** Time-stamped charge level per battery, entered manually first, from chargers via Bluetooth later if feasible.

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
- Identify rider (tap name, or scan a rider badge; see Open questions).
- Identify item (scan label, or pick from a large-tile list filtered to what this rider may take).
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
5. Core riders' standing reservations carry over between events; event-only reservations expire when the event closes.

## 5. Open questions

- **Open: platform.** Native iOS / iPadOS for riders and the kiosk is the natural fit. Does Axel also need a web dashboard on a laptop for packing at HQ, or is iPad enough?
- **Open: offline.** Race sites often have poor connectivity. Proposal: the kiosk and rider app work offline and sync; the movement log is designed to merge without conflicts.
- **Open: labels and scanning.** iPads do not read NFC tags, iPhones do. Options: engraved or laser-etched QR codes read by the iPad camera; NFC tags read by iPhones only; or no scanning at the kiosk and riders pick from large tiles by label code. This decision shapes the kiosk flow.
- **Open: rider identity at the kiosk.** Tap your name from a roster grid, a short PIN, or a personal QR / NFC badge.
- **Open: gear granularity.** Confirm the category list above matches how the team actually thinks about a setup, and whether kits are worth having in v1.
- **Open: reservations.** Are core riders' reservations standing (always) or set per event by Axel?
- **Open: tenancy.** Built for the Lift Foils team only, or as a tool other teams could use through efoil.racing later? This affects data design from day one.
- **Open: charger integration.** Keep as a phase-2 item behind manual charge entry until the Bluetooth firmware question is answered.

## 6. Suggested phasing

1. **Phase 1, replace the spreadsheet:** events, inventory, manifest, essentials checklist, movement log, kiosk check-out / check-in, rider requests.
2. **Phase 2, rider self-service:** rider app with notifications, reservations visible to riders, battery state entered manually.
3. **Phase 3, hardware:** charger Bluetooth integration, scanning improvements, label printing workflow.
