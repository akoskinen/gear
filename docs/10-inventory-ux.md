# Axel's Inventory Experience (draft v0.1)

A redesign of the inventory side of the app, grounded in Axel's real warehouse sheet (`data/axel-inventory-2026-09.csv`, exported September 2026). It supersedes the list-and-detail parts of [04-inventory-spec.md](04-inventory-spec.md); the label scheme, status lifecycle and multi-team rules there still stand.

The goal is not a prettier spreadsheet. It is to make keeping the inventory true feel like a fifteen-minute walk rather than an evening of typing.

## 1. What the sheet tells us

| Finding | Evidence | Design consequence |
|---|---|---|
| **Axel runs a warehouse, not a race kit.** | 83 SKUs, 316 units, laid out by physical spot: Row 1 to Row 5-2, Board wall, Wing wall, Cabana. | Organise by place, the way he walks, not by category, the way a database thinks. |
| **Two kinds of things live in it.** | 165 units are individual assets (boards, propulsion, batteries, masts, wings, controllers, chargers). 151 units are counted spares: 35 AC cords, 20 isolator rings, 14 battery cases, 12 surf covers, subassemblies. | Two tracking modes. Serialized items get a label and a card. Counted stock gets a quantity and a reorder level. Never force a label on an AC cord. |
| **Reordering is part of his job.** | 30 rows carry a reorder quantity; 5 are flagged Reorder right now. | A low-stock view that turns into an order to Lift in one tap. |
| **Identity is visual for boards, numeric for wings.** | Boards: "LIFTX 4'7 Florence Red", "5'4 Sun Kissed". Wings: "130 Florence X", "21 Flow M30". | Photo-first cards for boards. Size-first labels for wings (FW-130-07). |
| **The same thing sits in two places.** | Lift Foil Stand: 3 in Row 4-1, 2 in Cabana. Sun Kissed 5'4: one on the Board wall, one in Cabana. | Counted stock is per SKU per place. Serialized items have one place each. |
| **Race wings are deep stock.** | 15 × 130 Florence X, 15 × 110 Florence X. | Bulk creation with auto-incremented labels; the picker groups identical items so the list stays short. |
| **Some things are lost or unnamed.** | 5 rows have no location. "unknown" SKU. "PYZEL wingboard (5'9?)". | An explicit Unknown place that nags gently, and free-text allowed where a SKU does not exist. |
| **Cost columns are unused.** | Every value is $0.00. | Drop money from v1 entirely. |
| **Typos accumulate.** | "Fron Wing" ×3, "OCHO MAST LCS SUBASSEMBLY" in caps. | A catalogue of models picked from a list, typed once, corrected once. |
| **Cabana is a different place.** | Four rows, mixed items, next to warehouse rows. | Locations have kinds; Cabana is its own top-level place, not a warehouse row. Confirm with Axel. |

## 2. The model change: two tracking modes

Every catalogue model has a **tracking mode**, set once and inherited by everything created from it.

- **Serialized.** One record per physical object, with a label code, a place, a status, and a history. This is what goes to events, gets reserved, and passes through the kiosk. Boards, propulsion units, batteries, masts, front wings, stabilizers, controllers, chargers.
- **Counted.** One record per model per place, with a quantity and a reorder level. No labels, no kiosk, no reservations. Spares, cables, cases, covers, stands, subassemblies. Counted stock can still go on an event manifest as "10 × AC cord", the way essentials do.

The kiosk, reservations, movement log and battery logic apply to serialized items only, unchanged. Counted stock has its own small write path: set quantity, move quantity between places, adjust reorder level, each one logged.

## 3. Design principles

1. **Place is the primary axis.** The warehouse has rows and walls; the app shows rows and walls. Category is a filter, not a hierarchy.
2. **Confirm, don't type.** Most of Axel's updates are "yes, still there" or "one fewer". Those are taps, not text fields. Text entry is reserved for genuinely new information.
3. **Camera before keyboard.** A board is identified by its colour. Take a photo, pick the model, done. The photo is the identity on every card from then on.
4. **Pick from the catalogue.** Every model Lift makes that the team owns is in a list with its SKU. Adding gear is choosing, not describing.
5. **Calm is the default state.** When everything is home and counted, the screen says so in one line. Only exceptions ask for attention: away from home, needs check, below reorder, unknown place, not seen since the last stocktake.
6. **Everything is undoable.** Every change writes history and the last change can be undone with one tap. This is the single biggest difference from a spreadsheet, where a wrong cell is silent forever.
7. **Works one-handed on a phone in the warehouse**, with the laptop for bulk work and printing.

## 4. The screens

### 4.1 Inventory home

The first screen when Axel opens Inventory. Four tiles, then places.

```
┌──────────────────────────────────────────────────────────────┐
│ Inventory                                   🔍  [+ Add]      │
│                                                              │
│ ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐ │
│ │ 165 items  │ │ 4 away     │ │ 3 need     │ │ 5 to       │ │
│ │ 151 spares │ │ from home  │ │ a look     │ │ reorder    │ │
│ │ all home ✓ │ │ Menton     │ │            │ │            │ │
│ └────────────┘ └────────────┘ └────────────┘ └────────────┘ │
│                                                              │
│ PLACES                            last walk: 12 days ago     │
│ ┌──────────────────────────────────────────────────────────┐ │
│ │ Wing wall              69 wings · 34 stabs        ›      │ │
│ │ Board wall             4 boards                   ›      │ │
│ │ Row 1                  3 controllers · 5 spare lines  ›  │ │
│ │ Row 3-1                8 propulsion               ›      │ │
│ │ Row 3-2                7 batteries · 7 chargers · … ›    │ │
│ │ Row 5-0                5 batteries                ›      │ │
│ │ Cabana                 2 boards · 2 stands        ›      │ │
│ │ …                                                        │ │
│ │ Unknown                5 items                    ⚠ ›    │ │
│ └──────────────────────────────────────────────────────────┘ │
│                                                              │
│                    [ Start a walk ]                          │
└──────────────────────────────────────────────────────────────┘
```

- Tiles are tappable filters. The first tile is the calm indicator: when nothing is away and nothing needs attention it reads "all home".
- Places are ordered by warehouse layout (sort order Axel sets once by dragging), with a one-line summary of contents.
- "Unknown" is always last and always visible while it holds anything.
- "Start a walk" begins a stocktake session (4.3). The "last walk" date nags gently after 30 days.

### 4.2 A place

Tapping a place shows what is there, serialized items as cards, counted stock as rows with steppers.

```
┌──────────────────────────────────────────────────────────────┐
│ ‹ Places        Row 3-2                     [Move all] [⋯]   │
│                                                              │
│ BATTERIES                                                    │
│ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐       │
│ │ BAT-01 │ │ BAT-02 │ │ BAT-03 │ │ BAT-04 │ │ BAT-05 │       │
│ │ LiftX  │ │ LiftX  │ │ LiftX  │ │ LiftX  │ │ LiftX  │       │
│ │ Light  │ │ Light  │ │ Light  │ │ Light  │ │ Light  │       │
│ │ ● ready│ │ ● ready│ │ ◐ check│ │ ● ready│ │ ● ready│       │
│ └────────┘ └────────┘ └────────┘ └────────┘ └────────┘       │
│ ┌────────┐ ┌────────┐                                        │
│ │ BAT-06 │ │ BAT-07 │                                        │
│ │ LiftX  │ │ LiftX  │                                        │
│ └────────┘ └────────┘                                        │
│                                                              │
│ CHARGERS                                                     │
│ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ …                │
│                                                              │
│ SPARES                                                       │
│  AC Cord – Euro                       35   [ − ] [ + ]       │
│  LIFTX Battery Adapter                 4   [ − ] [ + ]       │
│  Lift Foil Stand                       3   [ − ] [ + ]  (+2 in Cabana) │
└──────────────────────────────────────────────────────────────┘
```

- Cards: label code large, model, status dot. Boards show their photo instead of text. Long-press or checkbox to multi-select, then Move or Set status for the selection.
- Counted rows: a stepper. Tapping − or + writes immediately and shows a 5-second undo toast. Tapping the number opens a keypad for a full recount.
- A counted line that also exists elsewhere says so inline, and tapping that opens a "move quantity" sheet.
- Below the reorder level the row gets an amber count and joins the Reorder list.

### 4.3 A walk (stocktake)

The replacement for the evening with the spreadsheet. A guided pass through the places in layout order.

1. **Start.** "Walk all places" or pick a subset (just the wing wall before an event).
2. **Per place.** The place screen in confirm mode: every card has a large check. Tap to confirm present; tap again to unconfirm. Counted rows show the expected number with a stepper. "Everything here" confirms the whole place in one tap when it matches. Items found here that belong elsewhere are added with "Found here" and moved.
3. **Missing.** Anything unconfirmed when leaving a place is asked about once: "BAT-03 not here. Where is it?" with the quick answers: With a rider, At an event, Somewhere else, Don't know. Don't know sends it to Unknown.
4. **Done.** A summary: places walked, items confirmed, moved, missing, counts changed, with an undo for the whole walk for the next hour. The "last walk" date updates. Each item stores its last-seen date, which the home screen uses to flag things not seen in 90 days.

A walk of the full warehouse at 165 items and 16 stock lines is under fifteen minutes on a phone when nothing has changed, because "Everything here" is one tap per place.

### 4.4 Item card and detail

A card is enough for the warehouse; the detail is for the desk. Detail follows the earlier spec (state, notes, photos, history) with these changes:

- **Photo is the header** when one exists. For boards, the add flow insists on one.
- **Last seen** shows the date of the last walk that confirmed the item, next to its current place.
- **Siblings** row: "one of 15 × 130 Florence X" with a link to the group, so Axel can see the whole set's state at once.
- **Undo** on the most recent history entry, when it was made by the current user within the hour.

### 4.5 Stock list and reorder

A dedicated view for counted things across all places, because Axel thinks about spares as a whole, not by shelf.

- Rows: description, SKU, total quantity, reorder level, per-place breakdown on expand.
- **Reorder list**: everything at or below its level, with the shortfall. "Copy as order" produces a plain-text list with SKUs and quantities to paste into an email to Lift. "Mark ordered" records the date so the row stops nagging until the goods arrive; "Received" adds the quantity.
- Reorder levels default from the sheet; Axel adjusts them inline.

### 4.6 Adding gear

Two paths, both under twenty seconds.

**One thing arrives** (a new board): tap Add, camera opens, take the photo, pick the model from the catalogue (search "florence" shows the LIFTX 4'7 Florence Red), confirm the suggested label (BRD-15), pick the place (defaults to the one the camera was opened from, or the last used). Saved.

**A box arrives** (six 130 Florence X wings): tap Add, pick the model, enter 6, the app creates FW-130-16 to FW-130-21 in the chosen place. For a counted model the same screen simply adds 6 to the quantity.

The catalogue is seeded from Axel's sheet: every SKU with its corrected description, category, tracking mode and size. A model that is not in the catalogue yet can be typed in free text and becomes a catalogue entry on save, so the second time it is a pick.

### 4.7 Search

One search box on every inventory screen. Matches label code, SKU, model, size and colour words. "florence" returns 130 and 110 Florence X wings, the 20 Florence X stabilizers and the two Florence boards, grouped by category. "bat-0" returns batteries 01 to 09. Results are cards with their place, so search is also the fastest way to answer "where is…".

### 4.8 Away from home

A view of every serialized item whose place is not its home place: at an event site, in the van, with a rider, or unknown. Grouped by where it is. This is what Axel checks after an event to make sure everything came back, and it is empty in the calm state.

## 5. Importing the sheet

The importer is built for this file specifically and then generalised.

1. **Upload** the CSV. The parser skips the header rows and the empty tail, and reads SKU, description, location, quantity and reorder quantity.
2. **Places.** The distinct locations become places: warehouse rows as sub-locations of HQ in the sheet's order, Board wall and Wing wall likewise, Cabana as its own top-level place, blank as Unknown. Axel can rename or re-nest before committing.
3. **Catalogue.** Each distinct SKU becomes a catalogue model with the classification from `data/axel-inventory-mapping.json`: category, tracking mode and size, with obvious typos corrected in the display name and the original kept as an alias. The preview shows the classification and lets Axel flip any row (for example, if he prefers to count rather than label the 15 identical race wings).
4. **Items.** For serialized rows, quantity N creates N items with sequential label codes in the row's place, status Ready, last seen today. For counted rows, one stock record per SKU per place with the quantity and reorder level.
5. **Duplicates.** Rows with the same SKU in two places are merged into one catalogue model with two stock records or two sets of items.
6. **Commit** writes everything with an `import` history entry and shows the home screen already populated: 165 items, 16 stock lines, 14 places, 5 items in Unknown.
7. **Labels.** The same screen offers "Print all labels" for the new items, sized for the label stock the team chooses.

## 6. Data model changes

Additions to [09-firestore-data-model.md](09-firestore-data-model.md), to be implemented with the import slice:

- `catalogue/{modelId}` gains `sku`, `trackingMode` (`serialized` | `counted`), `size`, `aliases[]`.
- New `stock/{stockId}` under the team: `modelId`, `locationId`, `qty`, `reorderQty`, `orderedAt`, `updatedAt`. Managers read and write; every change appends a `stock_adjusted` movement with `payload.delta`.
- `items/{itemId}` gains `modelId`, `lastSeenAt`, and `photos[0]` becomes the card image.
- `locations/{locationId}` keeps `sortOrder` for the walk order and gains `lastWalkedAt`.
- New `walks/{walkId}` under the team: `startedAt`, `finishedAt`, `placeIds[]`, counts of confirmed, moved, missing, adjusted, and `undoneAt`.
- Movement kinds gain `seen` (confirmed in a walk) and `stock_adjusted`.

## 7. Questions for Axel

1. Is Cabana a separate building or a corner of the warehouse?
2. The 15 + 15 Florence X race wings: label each one, or count them as stock and only label the ones assigned to core riders? The design supports both; labelling is the default.
3. Which label material is realistic to print or order now, so "Print all labels" targets the right size?
4. Are the five items without a location really unaccounted for, or just not entered?
5. Do the reorder levels in the sheet reflect what he actually wants, or are they placeholders?
