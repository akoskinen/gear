# Kiosk — Shared iPad at the Tent (draft v0.1)

The kiosk is the rider-facing check-out and check-in station. It runs on a shared iPad mounted at the team tent during an event. Riders use it in a hurry, often with wet hands, in bright sunlight, sometimes with no network. This document specifies the flow, each screen, the rules behind it, and the physical constraints.

Related: [product outline](01-product-outline.md) for the data model, [event hub](02-event-hub-spec.md) for what the manager sees on the other side.

## 1. Principles

- **Three taps to take gear.** Name, PIN, item, done. Anything beyond that is friction that riders will route around by not logging at all, which is the failure mode of the spreadsheet.
- **Tap only.** No swipes, no long presses for essential actions, no keyboard. Wet fingers and gloves make gestures unreliable.
- **Big and legible.** Minimum tap target 88 × 88 pt. Label codes at 40 pt or larger. High-contrast light theme by default for sunlight; the screen is often read from a metre away.
- **Never block.** The kiosk always lets a rider log something. If it cannot decide (item reserved, offline conflict), it records what happened and flags it for the manager rather than refusing.
- **Forgets you quickly.** Every session times out and returns to the idle screen so the next rider never acts as the previous one.

## 2. Flow

```
 Idle ──tap anywhere──▶ Who are you? ──tap name──▶ PIN ──4 digits──▶ Your gear
                                                                       │
                              ┌────────────────────────────────────────┤
                              ▼                                        ▼
                         Take gear                                Return gear
                    (category ▸ items,                          (tap held items,
                     multi-select)                                condition chips)
                              │                                        │
                              └───────────────▶ Confirmation ◀─────────┘
                                                     │
                                          auto after 4 s / tap "Done"
                                                     ▼
                                                   Idle
```

Timeouts: 20 seconds without a tap on any screen after Idle returns to Idle. The rider is warned at 15 seconds with a thin countdown bar; a tap resets it.

## 3. Screens

### 3.1 Idle

```
┌──────────────────────────────────────────────────────────────┐
│  LIFT FOILS RACING                                 ● synced  │
│                                                              │
│                        Menton Open                           │
│                     Saturday, day 2 of 3                     │
│                                                              │
│           ┌──────────────────────────────────────┐           │
│           │                                      │           │
│           │          Tap to take or return       │           │
│           │                 gear                 │           │
│           │                                      │           │
│           └──────────────────────────────────────┘           │
│                                                              │
│   Out now: 7 items · 4 riders          Batteries ready: 5    │
└──────────────────────────────────────────────────────────────┘
```

- Whole screen is the tap target.
- Sync indicator top right: synced, syncing, offline with "last synced 12 min ago". Offline is informative, never a warning to the rider.
- Bottom line shows two live facts riders care about: how much gear is out and how many batteries are ready. Nothing else.
- Team name and event come from the hub; the kiosk cannot switch events itself.

### 3.2 Who are you?

- Grid of name tiles, one per confirmed roster member. Core riders first, then alphabetical. Each tile: first name large, last name small, optional photo. Six to eight tiles per row on a 12.9" iPad in landscape.
- With more than 16 riders, an A–Z rail on the right jumps within the grid. Still no keyboard.
- "Not on the list? Ask Axel" as a quiet text button at the bottom. Tapping shows the manager's name and a note that guests are added from the hub.
- Cancel returns to Idle.

### 3.3 PIN

```
┌──────────────────────────────────────────────────────────────┐
│  ◀ Not you?                    Hi Pete                       │
│                                                              │
│                          ● ● ○ ○                             │
│                                                              │
│                  ┌─────┐ ┌─────┐ ┌─────┐                     │
│                  │  1  │ │  2  │ │  3  │                     │
│                  ├─────┤ ├─────┤ ├─────┤                     │
│                  │  4  │ │  5  │ │  6  │                     │
│                  ├─────┤ ├─────┤ ├─────┤                     │
│                  │  7  │ │  8  │ │  9  │                     │
│                  ├─────┤ ├─────┤ ├─────┤                     │
│                  │     │ │  0  │ │  ⌫  │                     │
│                  └─────┘ └─────┘ └─────┘                     │
│                                                              │
│                     Forgot your PIN? Ask Axel                │
└──────────────────────────────────────────────────────────────┘
```

- Four digits, auto-submits on the fourth. Fixed key layout for muscle memory.
- Wrong PIN: dots shake, clear, message "Try again". Three wrong attempts lock this rider's tile for 60 seconds and notify the manager in the hub. The kiosk stays usable for others.
- PINs are verified locally against a cached hash so the kiosk works offline. A PIN change in the hub reaches the kiosk on the next sync.
- "Not you?" returns to the roster grid.

### 3.4 Your gear (rider home)

```
┌──────────────────────────────────────────────────────────────┐
│  ◀ Done                          Pete                  0:18  │
│                                                              │
│  YOU HAVE (3)                          ┌───────────────────┐ │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐│                   │ │
│  │ BAT-07   │ │ BRD-03   │ │ FW-170-2 ││                   │ │
│  │ Battery  │ │ Board    │ │ Front    ││    + Take gear    │ │
│  │ 2h 10m   │ │ 2h 10m   │ │ wing     ││                   │ │
│  │          │ │          │ │ 2h 10m   ││                   │ │
│  └──────────┘ └──────────┘ └──────────┘│                   │ │
│   tap items to return them             └───────────────────┘ │
│                                                              │
│  RESERVED FOR YOU                                            │
│  ┌──────────┐ ┌──────────┐                                   │
│  │ BAT-09 🔒│ │ MST-72 🔒│                                   │
│  │ 92%      │ │ Mast 72  │                                   │
│  └──────────┘ └──────────┘                                   │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

- Left: items the rider currently holds, with elapsed time. Tapping one selects it for return; a "Return selected (n)" bar appears at the bottom, plus "Return all".
- Right: the single big "Take gear" action.
- Below: items reserved for this rider at this event that are on site and not yet taken. Tapping one takes it directly, skipping the picker. This is the fastest path for core riders and the main payoff of reservations.
- Session timer top right so the rider knows the screen will reset.
- Empty state when holding nothing: the left area says "You have nothing out" and the reserved row moves up.

### 3.5 Take gear: category

- Tiles for each category that has at least one item available to this rider: Boards, Masts, Front wings, Stabilizers, Fuselages, Propulsion, Batteries, Controllers, Spares. Each tile shows the available count.
- Categories with nothing available are shown greyed with "none available" rather than hidden, so the rider learns the answer without hunting.
- A "Selected (n)" tray persists at the bottom across categories so a rider can pick a battery, then a wing, then confirm once.

### 3.6 Take gear: items

```
┌──────────────────────────────────────────────────────────────┐
│  ◀ Categories            Batteries                      0:14 │
│                                                              │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐         │
│  │ BAT-09 🔒│ │ BAT-02   │ │ BAT-05   │ │ BAT-11   │         │
│  │ 92%      │ │ 100%     │ │ 85%      │ │ 40% low  │         │
│  │ yours    │ │          │ │          │ │          │         │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘         │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐                      │
│  │ BAT-07   │ │ BAT-01 🔒│ │ BAT-04   │                      │
│  │ with Pete│ │ Manel    │ │ charging │                      │
│  └──────────┘ └──────────┘ └──────────┘                      │
│      grey          grey        grey                          │
│                                                              │
│  Selected (2): BAT-02, FW-170-2            [ Take 2 items ▶ ] │
└──────────────────────────────────────────────────────────────┘
```

Tile states, in priority order:

| State | Appearance | Tap |
|---|---|---|
| Reserved for you | Highlighted border, lock, "yours" | Selects |
| Available | Plain | Selects |
| Below battery threshold | Plain with amber "low" | Selects, with a one-line warning in the tray |
| Reserved for another rider | Grey, lock, that rider's name | Shows "Reserved for Manel. Ask Axel to release it." Logs an availability request for the hub. |
| Checked out | Grey, "with <name>" | Shows who has it and since when. No action. |
| Charging / needs check / in repair | Grey, state label | Shows the state. No action. |
| Not on site (still at HQ or in vehicle) | Not shown | |

- Batteries show charge percentage, marked "est." when estimated from charging time, and a ready time while charging; other items show model or size.
- Sorted: reserved for you, then available by label code, then greyed states.
- Multi-select. The tray shows selected codes and the confirm button reads "Take n items".

### 3.7 Return gear

- Entered by tapping held items on Your gear. Selected items get a check mark.
- Confirm bar: "Return selected (n)". After tapping, one condition prompt covers all selected items:

```
   How was it?      [ All good ]   [ Something's off ]
```

- "All good" completes the return. "Something's off" shows chips per item: Damaged, Leaking, Loose, Low power, Noise, Other. Multiple chips allowed. Items with a chip are set to "needs check" and appear in the hub's Needs attention. Free text is not offered on the kiosk; Axel follows up in person.
- For each battery in the selection, one extra step comes first: the rider taps the remaining percentage on a 0–100 row in ten-percent steps (or "Don't know"), then "On charger" or "On the shelf". "On charger" starts the charge estimate. See [battery charge estimation](05-battery-charge-estimation.md).

### 3.8 Confirmation

- Full-screen, one sentence, large: "Pete took BAT-02 and FW-170-2" or "Pete returned 3 items". Green check for a completed action, amber for a return with a flagged condition.
- Offline: a small line "Saved on this iPad, will sync when online". Never a warning tone.
- If the take included a battery, the confirmation carries one optional line, "BAT-02 shows:" with the percentage row and Skip. Skipping is the default when the screen auto-dismisses.
- Auto-returns to Idle after 4 seconds, or on tapping Done. There is intentionally no "take more" from here; the rider taps their name again if they forgot something. Sessions must end cleanly.

## 4. Rules

1. Only members on the event roster with status Confirmed appear on the roster grid.
2. Only manifest items with location On site and status Ready are offered. A reserved item is offered only to its rider.
3. Every take and return writes one movement log entry per item: team, event, item, rider, direction, timestamp, kiosk device id, condition chips, and whether it was recorded offline.
4. A take moves the item's location to "with rider"; a return moves it to "event site".
5. Taking an item reserved for someone else is not possible from the kiosk. The attempt is logged as an availability request so the manager sees demand.
6. The manager can always override from the hub: force return, check out on behalf, release a reservation. Those actions appear in the movement log with the manager's name.
7. Handing gear directly from one rider to another is not supported in v1. The manager fixes it from the Live board. This is listed as a candidate for v2.

## 5. Manager access on the kiosk

A quiet "Manager" text button on the Idle screen opens a manager PIN pad. It exists for the cases where the laptop is not at hand:

- Force a sync and see the queue of unsynced actions.
- Force return an item or take on behalf of a rider.
- Lock the kiosk (shows "Kiosk closed, see Axel") at the end of the day.
- Exit to iPad settings.

Nothing else. Planning stays in the hub.

## 6. Offline behaviour

- The kiosk caches the event roster, PIN hashes, manifest, reservations, and latest battery readings. It keeps working with no network for the whole event.
- Actions queue locally in order and sync when a connection returns. The Idle screen shows the count of unsynced actions once it is above zero.
- Conflicts: v1 assumes one kiosk per event. If the hub and the kiosk disagree (for example Axel force-returned an item while the kiosk was offline and a rider then took it), the movement log keeps both entries in timestamp order and the item's current holder is whoever acted last. The disagreement is surfaced in the hub's Needs attention as "conflicting record" for Axel to confirm.
- Two kiosks at one event is a v2 topic and needs the same conflict handling plus device labelling.

## 7. Device and environment

- Recommended: iPad 11" or 13", landscape, in a waterproof case on a stand or strap-mounted to the tent pole at chest height. Portrait is supported with tiles reflowing to fewer per row.
- Run in iPadOS Guided Access so riders cannot leave the app. Auto-lock off while the kiosk is active; the app dims the screen after 5 minutes idle and wakes on tap.
- Light, high-contrast theme by default. Dark theme available for indoor or evening use; the manager toggles it from the kiosk manager menu.
- Wet touch: tap targets are large and spaced 16 pt apart at minimum. No drag, no swipe-to-delete, no pull-to-refresh anywhere in the kiosk.
- Audio: a short confirming tick on take and return so the rider does not need to look at the screen. Muted from the manager menu.

## 8. Edge cases

- **Rider takes something without the kiosk.** The item shows as available while it is gone. When someone else tries to take it, they will not find it and ask. Axel checks it out on their behalf from the Live board. Over time, the fact that reserved gear only unlocks through the kiosk encourages logging.
- **Rider returns someone else's gear.** Not possible from their own session in v1. They tap the other rider's name and would need that PIN. Instead, Axel force-returns from the hub. Considered for v2 as "return any item" restricted to non-reserved gear.
- **Item breaks on the water.** Rider returns it with the Damaged chip. It leaves availability immediately and appears in Needs attention.
- **Rider forgets to return at end of day.** Overdue rule in the hub flags it. Kiosk itself does nothing special.
- **Battery percentage unknown.** A battery returned with "Don't know" and not charging shows "? %" and is greyed until Axel sets a reading.
- **Guest rider arrives on race morning.** Axel adds them on the roster from the hub or iPad, sets a PIN, and they appear on the kiosk grid after sync. Offline, Axel does this from the kiosk manager menu; the record syncs later.

## 9. Out of scope for v1

- QR or NFC scanning (label codes are chosen so etched QR codes can be added later without changing the flow; a scan simply pre-selects a tile).
- Rider-to-rider transfer.
- Multiple kiosks per event.
- Rider photos beyond an optional avatar for the roster grid.
- Charger integration; battery percentages come from rider readings at return and the charge-time estimate, see [05-battery-charge-estimation.md](05-battery-charge-estimation.md).

## 10. Next specs

1. Inventory view and item detail: see [04-inventory-spec.md](04-inventory-spec.md).
2. Rider app: my events, my requests, my gear.
3. Team and member settings, including onboarding a second team.
