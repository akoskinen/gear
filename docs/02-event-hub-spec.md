# Event Hub — Manager View (draft v0.1)

The event hub is where the logistics manager (Axel) plans, packs, runs, and closes one event. It is the primary screen of the web dashboard and is also available on the iPad. This document specifies its structure, states, and interactions so it can be designed screen by screen.

Related: [product outline](01-product-outline.md) for the data model and decisions.

## 1. Purpose and principles

- **One event at a time.** The hub is always scoped to a selected event. Switching events is a single control in the header, never a deep navigation.
- **Phase-aware.** The event moves through Planned → Packing → Live → Wrap-up → Closed. The hub keeps the same tabs throughout but changes what is prominent in each phase, so Axel always lands on the thing that matters today.
- **Exceptions first.** Anything that needs a decision (an unanswered request, an item missing from the manifest, a battery below threshold, an item out overnight) surfaces at the top. Everything that is fine stays quiet.
- **Big targets, few words.** Even on the laptop, controls follow the "large buttons under pressure" principle from the brief, since the same layout runs on the iPad in the tent.

## 2. Layout

```
┌───────────────────────────────────────────────────────────────────────┐
│ Team ▾   │  Menton Open  ·  3–5 Oct 2026  ·  Menton, FR  │ Phase: Packing ▾ │  ← event header
├───────────────────────────────────────────────────────────────────────┤
│  Riders 9/10   Requests 3 open   Manifest 42/61 packed   Batteries 8/12 ≥80% │  ← status strip
├───────────────────────────────────────────────────────────────────────┤
│  Needs attention (4)                                                  │  ← exceptions
│  • Pete asked for firmware 2.3 on Battery B07 — not planned           │
│  • Board L-03 reserved for Carmine is marked "needs check"            │
│  • Manifest has 2 wings with no location                              │
│  • Essentials: lunch not confirmed for Sunday                         │
├────────────┬────────────┬────────────┬────────────┬───────────────────┤
│  Roster    │  Requests  │  Manifest  │ Essentials │  Live board       │  ← tabs
├────────────┴────────────┴────────────┴────────────┴───────────────────┤
│                                                                       │
│  (active tab content)                                                 │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘
```

On the iPad in landscape the same layout applies. In portrait the status strip wraps to two rows and the tabs become a segmented control.

## 3. Event header

- Team switcher (only shown when the user belongs to more than one team).
- Event name, dates, location. Tapping opens the event details sheet (edit name, dates, location, type, notes, venue contact).
- Phase control. Shows the current phase and the next action as a button: "Start packing", "Go live", "Start wrap-up", "Close event". Moving backwards is allowed from a menu, with a confirmation.
- Event switcher: previous / next event arrows and a dropdown of upcoming events. Opening the calendar is one step away.

## 4. Status strip

Four tiles. Each is tappable and jumps to the relevant tab with the matching filter applied.

| Tile | Shows | Turns amber when | Turns red when |
|---|---|---|---|
| Riders | confirmed / invited | any rider is unconfirmed 7 days before start | a confirmed rider has no PIN |
| Requests | open count | any request older than 48 h is unanswered | a request is open 24 h before start |
| Manifest | packed / planned | packing started and less than 50% packed 2 days before departure | departure day and items not packed |
| Batteries | count at or above threshold / total on manifest | any battery below threshold on departure or race morning | a battery on the manifest is in repair |

Thresholds are team settings with sensible defaults (battery ready at 80%).

## 5. Needs attention

A short list, at most eight items, sorted by urgency. Each row has one primary action that resolves it in place (e.g. "Plan it", "Swap item", "Set location", "Confirm"). Resolved rows animate out. When the list is empty the panel collapses to a single calm line: "Nothing needs attention."

Sources of attention items:

- Rider request submitted or changed and not yet planned.
- Reserved item whose status is not ready.
- Manifest item with no location, or located at HQ after departure.
- Setup matrix demand for a category exceeds the number of ready items on the manifest.
- Battery below threshold in the current phase context; batteries waiting for a free charger; a battery charging for twice its expected time.
- Essentials checklist item unconfirmed within its lead time.
- During Live: item checked out for longer than the team's overdue window (default 6 hours), or checked out at end of day.
- During Wrap-up: item still checked out; item not yet marked returned to vehicle / HQ.

## 6. Tabs

### 6.1 Roster

- Grid of member cards: name, tier badge (Core / Team / Guest), status (Invited, Confirmed, Declined, Not coming), request count, reserved item count.
- Actions: invite member, add a guest rider for this event, confirm on behalf of a rider, set or reset PIN.
- Tapping a card opens the rider drawer: their requests for this event, their reservations, their current check-outs (during Live), and their history.
- Sorted core riders first, then by name.
- **Setup matrix** view toggle: riders down the side, slots across the top (board, mast and fuselage, front wing, stabilizer, propulsion, battery, controller), each cell "own" or "team" taken from the rider's request for this event (defaulting to their declared setup). Column totals show demand: "Boards 4 · Wings 7 · Batteries 10 riders × 3/day". The matrix is the first thing to check when starting the manifest, and its totals are compared against the manifest's counts per category so under-packing shows up before departure.

### 6.2 Requests

- Inbox grouped by rider. Each request shows what was asked (catalogue item or free text), any firmware note, spare parts, rider's note, and time submitted.
- Status chips: Submitted, Seen, Planned, Fulfilled, Declined.
- Actions per request: **Plan** (pick a specific item; this adds it to the manifest and creates the reservation for that rider in one step), **Fulfil** (already covered), **Decline** with a short reason that the rider sees.
- A request can be turned into a reservation directly; this is the main way reservations get created.
- Filter: open only (default before Live), all.

### 6.3 Manifest

The list of everything going to this event.

- Sections by category (Boards, Masts, Front wings, Stabilizers, Fuselages, Propulsion units, Batteries, Controllers, Chargers, Spares).
- Each row: label code, model, reserved-for (rider name or blank), current location, packing state (Planned → Packed → Loaded → On site → Returned).
- Row actions: change packing state (tap advances one step, long press shows all), set reservation, remove from manifest, open item detail.
- Bulk actions: mark all in a category as Packed; mark all as Loaded when the vehicle leaves.
- Header actions: **Add items** (search inventory with filters by category and location, multi-select), **Copy from event…** (pull the manifest and reservations from a previous event, then adjust), **Print packing list**.
- The packed counter in the status strip is derived from this tab.
- Locked rows: an item reserved for a rider shows a small lock and the rider's name. Only the manager can change or release it.
- **Rider-owned items for transport** appear in a separate section at the bottom, marked with the owner's name. They have packing states like any other row so Axel knows they are in the van, but they never count toward stock or reach the kiosk. Added via "Add items" with an owner filter, or from a request where the rider asked for transport.

### 6.4 Essentials

Non-gear checklist for a standardized routine.

- Built from a team template (tents, tables, water, lunch per day, fuel, tools, first aid, generator, signage, flags, buoys for the speed track, timing gear).
- Each item: name, quantity, owner (a member), lead time (how many days before the event it must be confirmed), state (To do, Confirmed, Packed, On site).
- Actions: check off, assign owner, add one-off item for this event, edit the template for future events.
- Unconfirmed items inside their lead time appear in Needs attention.

### 6.5 Live board

Prominent during the Live phase; available in other phases for reference.

- Two columns on wide screens: **Out with riders** and **At the tent**. Each item shows label code, model, and for checked-out items the rider name and elapsed time.
- Batteries have their own row of tiles at the top with charge level and state (Charging, Ready, Low, In use). Charge comes from the rider's reading at return plus the charge-time estimate while on a charger, marked "est." with a ready time. Tile actions: On charger, Off charger, Set reading, Needs check. A charger row shows occupied versus available chargers. See [battery charge estimation](05-battery-charge-estimation.md).
- Manager actions: force return an item (when a rider forgot the kiosk), check out to a rider on their behalf, mark an item as damaged or needs check (removes it from kiosk availability immediately), release a reservation.
- Feed: the last twenty movement log entries for this event, live-updating.
- Overdue items pulse gently and are listed in Needs attention.

## 7. Phase behaviour

| Phase | Landing tab | What is emphasized | Entry action | Exit condition |
|---|---|---|---|---|
| Planned | Requests | Roster confirmations, incoming requests, reservations | Event created | Manager taps "Start packing" |
| Packing | Manifest | Packing state, essentials, battery charge before departure | "Start packing" | "Go live" (all manifest items Loaded or On site is recommended, not enforced) |
| Live | Live board | Check-outs, batteries, overdue | "Go live" | "Start wrap-up" |
| Wrap-up | Manifest | Items returned, damage notes, batteries for transport | "Start wrap-up" | "Close event" (blocked while any item is still checked out) |
| Closed | Manifest (read-only) | History and summary | "Close event" | Reopen from menu |

Closing an event releases all reservations, sets returned items' location to the destination chosen in the close dialog (usually HQ or the vehicle), and writes a summary entry to the movement log.

## 8. Kiosk interaction with the hub

The kiosk is a separate iPad screen but it depends on hub data:

- Only members on the roster with status Confirmed appear on the kiosk roster grid.
- Only manifest items with location On site and status Ready are offered for check-out.
- Reserved items are offered only to their rider. Other riders see them greyed with the rider's name.
- Every kiosk action appears in the Live board feed within seconds when online, or on the next sync when offline.

## 9. Empty and edge states

- No events yet: the hub shows a single "Create your first event" action and an offer to import inventory.
- Event with no roster: Requests and Live board tabs show a hint to invite riders first.
- Item on two manifests: allowed only if the events do not overlap; otherwise the second add is blocked with the conflicting event named.
- Rider on the roster leaves the team mid-event: their check-outs remain in the log; their reservations are released; the manager is notified.
- Offline iPad: hub tabs show a "last synced" timestamp; write actions queue and show a pending indicator.

## 10. Out of scope for this view

- Inventory management outside an event (separate Inventory view).
- Team settings, member management, PIN policy (separate Settings view).
- Rider-facing screens (separate rider app spec).
- Charger hardware integration (not planned; replaced by the charge estimate).

## 11. Next specs to write

1. Kiosk flow (iPad): see [03-kiosk-spec.md](03-kiosk-spec.md).
2. Inventory view and item detail.
3. Rider app: my events, my requests, my gear.
4. Team and member settings, including onboarding a second team.
