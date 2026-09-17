# Battery Charge Estimation Without Charger Integration (draft v0.1)

Instead of reading chargers over Bluetooth, the app estimates each battery's charge from three things it can know cheaply: the percentage the rider reports when returning the battery, the moment it goes on a charger, and the known charge time for that battery type. This is accurate enough to answer the only question anyone asks at the tent: "which battery can I take, and when will the next one be ready?"

Related: [kiosk](03-kiosk-spec.md) section 3.7 for the return prompt, [event hub](02-event-hub-spec.md) section 6.5 for the battery strip, [inventory](04-inventory-spec.md) section 10 for battery fields.

## 1. Inputs

| Input | Source | When | Effort |
|---|---|---|---|
| Remaining charge at return | Rider, one tap on the kiosk | Every battery return | One tap on a 0–100 % row |
| Went on charger | Rider at return ("On charger") or Axel from the Live board | When the battery is plugged in | One tap |
| Came off charger | Axel from the Live board, or implied by the next check-out | When unplugged | One tap or none |
| Charge time per battery type | Team setting, entered once | Setup | Two numbers per type |
| Actual charge at take (optional) | Rider on the kiosk, skippable | Battery check-out | One tap or skip |

No hardware, no firmware access, no manufacturer conversation needed. Charger integration stays on the list as a later refinement, no longer a dependency.

## 2. Battery types and charge curves

Each battery in inventory has a **battery type** (for example "Lift 100 Ah", "Lift 60 Ah light"). The type carries the charge model:

- **Time from 0 to 80 %** (the fast, roughly linear part of a lithium charge).
- **Time from 80 to 100 %** (the slow tail).
- Optional **charger speed factor** per charger type, default 1.0, for teams that mix standard and fast chargers. In v1 the factor is chosen once per event ("chargers at this event: standard") rather than per battery, to avoid asking which charger a battery went on.

Estimation is piecewise linear:

```
start %  →  80 %   at rate  (80 / t_0_80) per minute
80 %     →  100 %  at rate  (20 / t_80_100) per minute
```

Given a start percentage and the time on charger, the current estimate and the "ready at" time fall out directly. The team's readiness threshold (default 80 %) gives a "ready for racing at" time that arrives well before "full at".

Ballpark values from the team seed the model. They only need to be roughly right; section 6 explains how the numbers improve on their own.

## 3. Battery states

```
 In use ──return, report %──▶ Returned (x %) ──on charger──▶ Charging (est. rising)
                                    │                              │
                                    │                       reaches threshold
                                    │                              ▼
                                    └────── low, not charging ──▶ Ready (est. or confirmed)
                                                                   │
                                                              taken by rider
                                                                   ▼
                                                                 In use
```

- **In use:** with a rider. Shows the percentage it left with, if known.
- **Returned, not charging:** shows the reported percentage. If below threshold it is greyed on the kiosk as "low" and flagged in the hub if no charger is free.
- **Charging:** shows the estimated percentage, marked "est.", and "ready ~15:40". The estimate updates every minute.
- **Ready:** estimate at or above threshold. Shows "≥80 % est." until confirmed, "100 % est." once full time has elapsed. A rider's actual reading at take converts it to a confirmed number.

The kiosk offers a battery for check-out when it is Ready by estimate. A rider may still take a Charging battery that is above threshold; the tile says so.

## 4. Where it appears

### Kiosk, return (extends 03-kiosk-spec 3.7)

When the return selection includes a battery, one extra step per battery, before the condition prompt:

```
   BAT-07 — how much was left?

   [ 0 ] [10] [20] [30] [40] [50] [60] [70] [80] [90] [100]   [ Don't know ]

   Where is it going?      [ On charger ]   [ On the shelf ]
```

- The percentage row is a single tap. Ten-percent steps match what riders remember from the remote and keep the row to eleven large targets.
- "Don't know" records no reading; the battery becomes "returned, unknown %" and is highlighted for Axel to check.
- "On charger" starts the estimate immediately. "On the shelf" leaves it returned and not charging.
- With several batteries in one return, the steps repeat per battery with the label code large at the top. This is the one place the kiosk allows more than one question per action, because the information is only available from the rider and only right now.

### Kiosk, take (extends 03-kiosk-spec 3.6)

After confirming a take that includes a battery, one optional line on the confirmation screen: "BAT-02 shows:" with the same percentage row and a "Skip" button. Skipped by default after the 4-second auto-dismiss. When answered, it confirms the estimate and feeds calibration.

### Hub, Live board battery strip (extends 02-event-hub-spec 6.5)

Each battery tile shows label code, state, percentage (with "est." when estimated), and for charging batteries the ready time. Tiles are ordered: ready first (by percentage descending), then charging (by ready time ascending), then returned low, then in use.

Tap actions on a tile: **On charger**, **Off charger**, **Set reading** (manual percentage, for when Axel looks at the charger display), **Needs check**.

A charger row above the tiles shows the number of chargers at the event and how many are occupied, derived from batteries in Charging state. When every charger is occupied and low batteries are waiting, Needs attention gets "3 batteries waiting for a charger, next free at ~14:20".

### Hub, planning (extends 02-event-hub-spec 6.3)

The manifest's battery section shows a projected timeline for race day: given the number of chargers, the charge times, and the roster size, a simple bar per battery estimates whether the fleet can cycle fast enough. This is a planning aid, not a promise, and it is a candidate for v2 if it proves more than a few hours of work.

### Inventory, battery detail (extends 04-inventory-spec 10)

- Battery type field with a link to the type's charge model.
- History shows return readings and charging sessions as entries, so a battery that keeps coming back low or charging slow stands out.
- Cycle count becomes automatic: each return adds (100 − reported %) / 100 full-cycle equivalents. Manual adjustment stays available.

## 5. Team settings

- Battery types with the two charge times and an optional note about which charger they assume.
- Readiness threshold (default 80 %).
- Chargers available per event, set in the event details, default from team settings.
- Whether the kiosk asks for the percentage at take (default on, always skippable).

## 6. Calibration over time

Every time a rider answers the optional "shows:" question at take, the app has a pair: estimated versus actual after a known charging duration from a known start. With a handful of pairs per battery type, the two charge times can be nudged toward reality.

- v1: collect the pairs and show Axel the average error per battery type in team settings, with a one-tap "Use observed times" that replaces the seed values. No automatic changes.
- v2: adjust per battery rather than per type, so an ageing battery that charges faster (smaller usable capacity) and drains faster is modelled individually. Observed drain per session, from the take reading and the return reading, becomes a health indicator that would otherwise need a battery management system connection.

## 7. Accuracy and honesty

- Estimates are always labelled "est." and shown with a ready time rather than a false precision percentage. A tile saying "≥80 % est., ready" is more useful than "83 %".
- The estimate never exceeds 100 % and never claims more than the charge model allows.
- If a battery in Charging state is taken without a reading, the estimate is frozen at the moment of take and marked "left charger at ~72 % est."
- A manual reading from Axel or a rider always overrides the estimate and restarts the model from that point.
- Temperature, charger faults, and a battery that was never actually plugged in are invisible to the model. The mitigation is social: the tile shows how long a battery has been "charging", and one that has been charging for twice its full time is flagged for a look.

## 8. What this replaces

- Charger Bluetooth integration moves from phase 3 to "nice to have, not planned". The technical discovery item in the brief is closed by this approach.
- Manual bulk charge entry from the inventory spec remains for the overnight case, but becomes rare: an "all on charger" bulk action at end of day does the same through the model.

## 9. Open points

- Whether riders reliably know the percentage. On the Lift remote it is on screen during the whole session, so the last number seen should be close. The "Don't know" option keeps the flow honest when they do not.
- Ten-percent steps versus five. Ten is faster and the remaining uncertainty in the charge model is larger than five percent anyway.
- Whether to ask for the percentage at take by default. It costs nothing when skipped and improves the model when answered; default on, revisit after the first event.
