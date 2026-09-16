# Initial Brief — eFoil Racing Team Gear & Rider Management

Source: initial brief from Antti, September 2026. This is the original intent and is kept as-is; the evolving specification lives in the other documents in `docs/`.

## Core thesis

The current logistics management for the Lift Foils racing team, handled by Axel, relies on a manual Excel system that is prone to error and high stress. To optimize operations, a dedicated dashboard and rider-facing interface are required to track equipment status, location, and specific rider needs in real time.

## The logistics engine: Axel

Axel serves as the team's logistics manager, responsible for:

- **Gear maintenance:** fixing and preparing equipment.
- **Battery logistics:** managing the transport and charging of batteries to race locations.
- **Inventory management:** overseeing gear stored at the European headquarters in Martinchel, Portugal, and mobile event setups (e.g. Menton).

## Proposed solution: the Racing Dashboard

A minimalistic app with large, easy-to-use buttons designed for high-pressure race environments.

### Management dashboard (Axel's view)

- **Real-time inventory:** tracking the location and status of all boards, masts, wings, and batteries.
- **Charging status:** integration with battery chargers to monitor charge levels (pending technical feasibility of Bluetooth firmware access).
- **Priority tiers:** ability to reserve specific high-performance gear for core team members (Manel, Antti, Pete, and Carmine) to ensure others cannot take or touch dedicated equipment.

### Rider interface

- **Pre-race inquiries:** riders specify their equipment needs (custom firmware, specific wings, spare parts) ahead of the event.
- **Self check-in/out:** an iPad-based station where riders tap to log when they take or return specific labeled gear (e.g. "Battery XYZ").

## Operational requirements and constraints

- **Labeling:** equipment must be labeled with a waterproof solution more durable than Dymo stickers, which fail in the water.
- **Hardware integration:** the app ideally connects to chargers via Bluetooth. This requires consultation with the Chinese manufacturer regarding firmware access.
- **Event logistics:** the system must also account for non-racing essentials like tents, water, and lunch to ensure a standardized routine.

## Events as the unit of work

Each management session is tied to an event on a calendar of events, because equipment needs vary from event to event.

## Strategic triage: equipment allocation logic

```
Rider requests gear
├─ Core team member  → Is specific gear reserved for them?
│   ├─ Yes → Gear is locked: only the assigned rider can check out this item
│   └─ No  → check general stock
└─ Guest / other rider → check general stock

Check general stock: is the gear available?
├─ Yes → Allow check-out: rider taps iPad; log rider ID + gear ID + timestamp
└─ No  → Notify Axel
```

## Next steps

- **Technical discovery:** determine if the charger's Bluetooth connection can be tapped for real-time data.
- **Brief development:** formalize the requirements for the dashboard and rider interfaces to begin development.
