# Inventory and Item Detail — Manager View (draft v0.1)

Inventory is the team's complete gear register, independent of any event. It is where items are created, labeled, maintained, and retired, and where the manager answers "where is X and what state is it in" at any moment. The event hub draws from it; the kiosk never touches it directly.

Related: [product outline](01-product-outline.md), [event hub](02-event-hub-spec.md), [kiosk](03-kiosk-spec.md).

## 1. Purpose and principles

- **One row per physical object.** If it has its own label, it has its own record. Sets and setups are groupings on top, never a substitute.
- **Team gear first.** Rider-owned gear can be registered, with the rider as owner, so it can ride in the van on a manifest. It is otherwise invisible: not on the kiosk, not reservable, not in stock counts, hidden from the default list.
- **Location and status are always known.** Every item has exactly one current location and one condition status. Both change only through logged actions, so the history is complete.
- **Fast to scan, deep on demand.** The list is dense and filterable. The detail view holds everything about one item, including its full history.
- **Label code is the identity riders use.** It is short, readable from across the tent, and stable for the life of the item so it can be etched later.

## 2. Layout (web, laptop)

```
┌──────────────────────────────────────────────────────────────────────┐
│ Team ▾   Inventory                          [+ Add item]  [Import]   │
├──────────────┬───────────────────────────────────────────────────────┤
│ CATEGORY     │  Search label or model…        Location ▾  Status ▾   │
│ All      184 │  ┌─────────────────────────────────────────────────┐  │
│ Boards    14 │  │ BRD-01  Lift 4'2 Race     HQ · Rack A    Ready  │  │
│ Masts     11 │  │ BRD-02  Lift 4'2 Race     Menton · site  Ready  │  │
│ Front w.  32 │  │ BRD-03  Lift 4'4          Menton · Pete  Ready  │  │
│ Stabs     19 │  │ BRD-04  Lift 4'2 Race     HQ · Workshop  Repair │  │
│ Fuselages  9 │  │ …                                                │  │
│ Propulsion 8 │  └─────────────────────────────────────────────────┘  │
│ Batteries 28 │                                                       │
│ Controll. 12 │  Showing 14 · Sorted by label                          │
│ Chargers   6 │                                                       │
│ Spares    45 │                                                       │
├──────────────┤                                                       │
│ Needs check 3│                                                       │
│ In repair  2 │                                                       │
│ Retired    7 │                                                       │
└──────────────┴───────────────────────────────────────────────────────┘
```

On the iPad the category rail collapses into a segmented filter above the list. Item detail opens as a side panel on wide screens and a full screen on narrow ones.

## 3. Item list

Columns: label code, model / spec, owner (blank for team gear, rider name otherwise), current location (place and, when with a rider, the rider's name), status, reserved-for at the current or next event, last movement. Batteries add charge and cycle count; propulsion units and batteries add firmware version.

Filters:

- **Category** from the rail. Counts update with other filters applied.
- **Location:** HQ (with sub-locations such as racks or workshop), a named event site, a vehicle, with rider, unknown.
- **Status:** Ready, Needs check, In repair, Retired.
- **Owner:** Team (default), or a member. The default list shows team gear only; choosing a member shows their registered gear.
- **Search** matches label code and model. Typing "170" finds all 170 front wings; typing "BAT-0" finds batteries 01 to 09.
- Saved views: "Going to next event", "At HQ and ready", "Maintenance queue". Saved views are per team and editable.

Sort by label, model, last movement, status. Default is label.

Bulk actions on a multi-selection: set location (for moving a rack of items to the vehicle), set status, add to an event manifest, print labels, export to CSV.

## 4. Item detail

```
┌──────────────────────────────────────────────────────────────┐
│ BAT-07                                    Ready   ● Menton   │
│ Lift 100 Ah battery · serial LF-2025-0342                    │
├──────────────────────────────────────────────────────────────┤
│ [ Set location ]  [ Set status ]  [ Add to event ]  [ ⋯ ]    │
├──────────────────────────────────────────────────────────────┤
│ STATE                                                        │
│  Charge 92 % · read 40 min ago         Cycles 118            │
│  Firmware 2.3                          Home base: HQ Rack B  │
│  Reserved: Pete · Menton Open                                │
│                                                              │
│ NOTES                                                        │
│  "Slight scuff on rear corner, cosmetic." · Axel · 12 Aug    │
│                                                              │
│ PHOTOS  [ ][ ][ + ]                                          │
│                                                              │
│ HISTORY                                                      │
│  Today 14:02   Taken by Pete (kiosk)              Menton     │
│  Today 09:15   Charge reading 92 %                Axel       │
│  Yesterday     Returned by Pete, all good (kiosk) Menton     │
│  Yesterday     Taken by Pete (kiosk)              Menton     │
│  2 Oct         Loaded to vehicle                  Axel       │
│  1 Oct         Added to Menton Open manifest      Axel       │
│  …                                                           │
└──────────────────────────────────────────────────────────────┘
```

Sections:

- **Header:** label code large, model, serial, status pill, current location. Location shows the rider's name when out.
- **Actions:** Set location, Set status (with a required short reason when moving to Needs check or In repair), Add to event (choose an upcoming event; adds to its manifest), and a menu with Edit details, Print label, Duplicate (for adding several identical items), Retire.
- **State:** the category-specific fields. Batteries: charge, reading age, cycles, firmware. Propulsion: firmware, prop fitted, hours if known. Wings: size and any custom modification. Boards: length, volume, any repairs. Home base is the location the item returns to when an event closes.
- **Notes:** dated, attributed, append-only.
- **Photos:** a few images for identification and damage records.
- **History:** the movement log filtered to this item, newest first, with the source of each entry (kiosk, hub, import). This is the audit trail that replaces the spreadsheet.

## 5. Adding items

- **Add item:** pick category first, then the form shows only that category's fields. Label code is suggested from the team's scheme (see section 6) and can be overridden if unique. Location defaults to HQ. Status defaults to Ready. Owner defaults to Team; choosing a member marks the item rider-owned, and label codes for rider-owned items take the owner's initials as a prefix (for example AK-BRD-01) so they are never confused with team stock. The rider-owned add flow is a manager action in v1; riders registering their own gear from the app is a later addition.
- **Add several:** after saving, "Add another like this" pre-fills model and location and increments the label code. Adding twelve identical batteries takes twelve taps, not twelve forms.
- **Import:** CSV with columns matching the list. This is how Axel's existing spreadsheet comes in. Import shows a preview with detected problems (duplicate codes, unknown categories) before committing. Imported items get a history entry "Imported from spreadsheet".

## 6. Label codes

The code is what a rider reads on the item and on a kiosk tile, so the scheme matters.

- Format: category prefix, hyphen, two-digit sequence. Prefixes: BRD, MST, FW, STB, FUS, PRP, BAT, CTL, CHG, SPR. Front wings may include size: FW-170-02.
- Two digits allow 99 per category; batteries can move to three digits when needed without changing the scheme for other categories.
- Codes are unique per team, immutable once the item has any history, and never reused after retirement.
- Codes are chosen to be etched later as text plus a QR code containing the item's stable id. The QR payload is the id, not the code, so a relabelled item still resolves.
- **Print label** produces a PDF sheet sized for the team's chosen label stock. The label itself carries the code in large type, the team name, and the QR. The waterproof material decision (etched aluminium tag, laser-marked polymer, or cast-in vinyl) is outside the app; the app only needs to output the artwork.

## 7. Locations

A small hierarchy per team:

- **HQ** with optional sub-locations (Rack A, Rack B, Workshop, Charging bay).
- **Event sites**, created automatically from events and archived when the event closes.
- **Vehicles** (the van, a trailer), so "loaded" has a real place.
- **With rider**, set automatically by kiosk check-out.
- **Unknown**, a deliberate state Axel can set when an item cannot be found, which puts it in Needs attention until resolved.

Moving items between locations is a logged action. Bulk moves are the common case: select a rack, move to the van.

## 8. Status lifecycle

```
 Ready ──▶ Needs check ──▶ In repair ──▶ Ready
   │            │              │
   └────────────┴──────────────┴──▶ Retired
```

- **Ready:** available for manifests and kiosk check-out.
- **Needs check:** set by a rider's condition chips at return, or by Axel. Not offered by the kiosk. Appears in the maintenance queue.
- **In repair:** Axel is working on it or it is away for service. Optional expected-back date.
- **Retired:** kept for history, excluded from all lists by default.

Status changes require a reason when leaving Ready. The reason is shown in history and in the maintenance queue.

## 9. Maintenance queue

A saved view with extra columns: reason, days in state, expected back. Sorted by days in state. Each row has "Mark ready" and "Move to repair" so Axel can work through the queue on a workshop day. Items reserved for an upcoming event are flagged so they get priority.

## 10. Battery specifics

- Each battery has a **battery type**; the type holds the charge model (time to 80 %, time to 100 %). See [battery charge estimation](05-battery-charge-estimation.md).
- Charge comes from the rider's reading at return and the estimate while charging. Axel can still set a manual reading here or on the Live board; a manual reading always overrides the estimate. The list shows the percentage, whether it is estimated, and the reading age.
- Bulk "On charger" for the end-of-day case: select several batteries, one tap, all start charging from their last reading.
- Cycle count accumulates automatically from return readings as full-cycle equivalents, with manual adjustment available.
- Transport flag: a battery can be marked "storage charge" for shipping, with the target percentage, so the packing view can show which batteries still need discharging or charging before travel.

## 11. Multi-team considerations

- Inventory is strictly per team. A person who manages two teams switches with the team switcher and never sees a merged list.
- Label code schemes and location hierarchies are per team settings.
- Lending gear between teams is not supported in v1. If it happens, the lending team sets the location to a vehicle or event site with a note.
- A rider-owned item belongs to the team's inventory it was registered in, even though the owner is a person. A rider in two teams who wants their board transported by both registers it in both; there is no cross-team item in v1.

## 12. Edge cases

- **Duplicate label code on import or add:** blocked, with the existing item shown so Axel can pick a new code or merge.
- **Item on an open event's manifest is retired:** allowed with a warning; it is removed from the manifest and any reservation is released with a Needs attention entry.
- **Location says HQ but the kiosk says a rider took it:** the kiosk entry wins for the current location, and the hub shows a conflicting record for Axel to confirm.
- **Item with no movement for a long time:** a saved view "Idle over 90 days" helps spot gear that could be sold or lent.

## 13. Out of scope for v1

- Purchase price, depreciation, insurance values (a candidate for v2 as a simple cost field).
- Scanning to look up an item (arrives with etched labels).
- Automatic firmware detection.
- Charger hardware integration; not needed with the charge estimate.

## 14. Next specs

1. Rider app: see [06-rider-app-spec.md](06-rider-app-spec.md).
2. Team and member settings, including onboarding a second team.
