# Team and Member Settings (draft v0.1)

Settings is where a team is created, its people are managed, and the defaults that the other views rely on are set: label scheme, locations, battery types, essentials template, thresholds. It is also the onboarding path for a second team, which is why it is specified now even though Lift Foils is the only team for a while.

Related: [product outline](01-product-outline.md), [event hub](02-event-hub-spec.md), [kiosk](03-kiosk-spec.md), [inventory](04-inventory-spec.md), [battery charge estimation](05-battery-charge-estimation.md), [rider app](06-rider-app-spec.md).

## 1. Principles

- **Set once, forget.** Most settings are entered during setup and touched a few times a year. The screens can be plain; correctness and good defaults matter more than speed.
- **Defaults do the work.** A new team gets a sensible label scheme, location set, essentials template, and thresholds out of the box, and only changes what is different for them.
- **The team owns its data.** Everything is partitioned by team. A manager of two teams sees two separate worlds. Nothing is shared between teams except a person's account.
- **Managers are few.** Settings are for managers; riders see only their own profile, specified in the rider app.

## 2. Roles and permissions

| Capability | Owner | Manager | Rider |
|---|---|---|---|
| Team settings, billing, delete team | yes | | |
| Invite and remove members, set roles | yes | yes | |
| Set tiers, PINs, rider setups on behalf | yes | yes | |
| Events, manifest, reservations, requests inbox | yes | yes | |
| Inventory, locations, battery types, templates | yes | yes | |
| Kiosk manager menu | yes | yes | |
| Own profile, own setup, own PIN, own requests | yes | yes | yes |
| See team events, own reservations, battery strip | yes | yes | yes |

- **Owner** is the person who created the team, transferable. One or more per team. Axel or Antti for Lift Foils.
- **Manager** is Axel's role. There can be several, for example a second logistics person at a large event.
- **Rider** is everyone else, with a tier (core, team, guest) that affects allocation rules, not permissions.
- A person can hold different roles in different teams.

## 3. Settings structure

```
Settings
├── Team               name, short name, logo, home base, time zone, end-of-day time
├── Members            list, invite, roles, tiers, PINs, setups
├── Locations          HQ sub-locations, vehicles
├── Labels             prefixes per category, sequence width, print layout
├── Battery types      charge times, readiness threshold
├── Catalogue          models riders can request from
├── Essentials template  default checklist for events
├── Kiosk              timeouts, ask-at-take, theme, sound, devices
├── Notifications      request deadline default, overdue window
└── Data               import, export, delete team
```

## 4. Team

- Name and short name (shown on the kiosk idle screen and labels).
- Logo, optional.
- Home base: the HQ location, created automatically with the team (Martinchel for Lift Foils).
- Time zone, used for end-of-day and ready-time display. Events can override with the venue's time zone.
- End-of-day time (default 19:00), which triggers the overdue reminder and the kiosk's end-of-day summary for the manager.

## 5. Members

### 5.1 List

- One row per member: name, role, tier, PIN set or not, setup declared or not, last active.
- Filters: role, tier, no PIN, no setup. The last two are what a manager checks a week before an event.
- Sorted by role then name.

### 5.2 Inviting

- **Invite link or QR:** the manager creates an invitation with a role and a tier. The link opens the app (or the App Store if not installed) and joins the person to the team after sign-in. Links expire after 14 days and can be revoked.
- **Add without the app:** for guests who will only use the kiosk. The manager enters a name and sets a PIN. The member has no account until they later accept an invitation, at which point the record merges so kiosk history is kept.
- **Bulk add:** paste a list of names to create kiosk-only members quickly on a race morning. PINs are generated and shown once on screen for the manager to hand out.

### 5.3 Member detail

- Role and tier, editable.
- **PIN:** set, reset, or generate. The manager sees the PIN only at the moment it is set. Riders change their own PIN in the app. Three wrong attempts lock the rider on the kiosk for 60 seconds and notify the manager here and in the hub.
- **Setup:** the rider's declared setup, editable by the manager on the rider's behalf. Useful when a guest tells Axel on the phone what they are bringing.
- **Reservations and history:** current reservations and a link to their movement log entries.
- **Remove from team:** history stays; access ends immediately; any reservations are released; if they hold gear, the hub flags it.

## 6. Locations

- HQ sub-locations: a flat list (Rack A, Rack B, Workshop, Charging bay). Reorder by drag on the web.
- Vehicles: name and note (the van, the trailer). Each vehicle is a location.
- Event sites are created and archived by events and do not appear here.
- Deleting a sub-location that holds items asks where to move them first.

## 7. Labels

- Prefix per category, prefilled: BRD, MST, FW, STB, FUS, PRP, BAT, CTL, CHG, SPR. Editable before the first item in a category exists; locked after.
- Sequence width: two digits by default, three for batteries if the team has more than 99.
- Front wing size in the code: on or off (FW-170-02 or FW-02).
- Print layout: label stock size, whether to include the QR, the team short name, and the logo. Output is a PDF; the physical label technology is chosen outside the app.
- Rider-owned items: prefix rule is the owner's initials followed by the category prefix, not editable.

## 8. Battery types

- List of types with name, capacity note, time to 80 %, time to 100 %. Prefilled with the team's ballpark figures at setup.
- Per type, the observed error from take readings, and "Use observed times" when at least ten pairs exist.
- Readiness threshold for the team, default 80 %.
- Default number of chargers per event, overridable per event.
- Charger speed factor per charger type, only shown if the team has more than one charger type registered in inventory.

## 9. Catalogue

The models riders pick from in the request form. Kept short on purpose.

- One entry per model per category: "Front wing 170", "Front wing 200", "Mast 72", "Lift 100 Ah battery".
- Built automatically from the models present in inventory, with a toggle per model to hide it from riders (for example prototypes reserved for core riders).
- Free text in the request covers anything not in the catalogue.
- Spares chips: a short list (Prop, Fuse, Mast bolts, Wing screws, Controller strap) edited here.

## 10. Essentials template

- The default checklist copied into every new event: name, quantity, default owner, lead time in days.
- Prefilled for a race team: tents, tables, chairs, water, lunch per day, fuel, generator, tools, first aid, signage, flags, buoys for the speed track, timing gear, chargers, extension leads.
- Editing the template changes future events only; open events keep their own copy.

## 11. Kiosk

- Session timeout (default 20 s), confirmation auto-dismiss (default 4 s).
- Ask for battery percentage at take: on or off (default on).
- Percentage steps: 10 or 5 (default 10).
- Theme default: light or dark; sound on or off.
- Manager PIN for the kiosk manager menu, separate from any rider PIN.
- **Devices:** each iPad that signs in as a kiosk appears here with a name, last sync, and unsynced action count. A device is bound to one event at a time from the hub. A lost device can be signed out remotely, which wipes its cache on next contact.

## 12. Notifications

- Request deadline default (days before event start, default 5).
- Overdue window during Live (default 6 h) and whether end-of-day counts as overdue (default yes).
- Manager notifications: new request, changed request, kiosk PIN lockout, conflicting record, battery charging too long. Each on or off, default on. Delivered as push to the manager's phone and shown in the hub.

## 13. Data

- **Import:** the spreadsheet import from the inventory spec, plus a members import (name, tier) for the first setup.
- **Export:** inventory, members, movement log for a date range, as CSV. This is the team's data and they can always take it out.
- **Delete team:** owner only, typed confirmation, 30-day grace period during which an owner can restore. Everything under the team is removed after that.

## 14. Onboarding a new team

The path a second team follows, designed to take under an hour with a spreadsheet at hand.

1. **Create team.** Name, short name, home base, time zone. The creator becomes owner and manager.
2. **Defaults applied.** Label scheme, essentials template, kiosk settings, thresholds, and a starter set of battery types are created. The team edits rather than builds.
3. **Import inventory.** Upload the spreadsheet, fix the preview's complaints, commit. Or add items by hand with "Add another like this".
4. **Invite people.** Send the invite link to core and team riders. Add kiosk-only guests by name.
5. **Set battery charge times.** Confirm or adjust the starter values per battery type.
6. **First event.** Create it, invite the roster, and the rest of the app takes over.

A setup checklist on the hub's empty state tracks these six steps until each is done, then disappears.

## 15. Multi-team account behaviour

- A person's account holds their name, photo, sign-in, and a list of team memberships. Everything else is per membership: role, tier, PIN, setup, requests, history.
- The team switcher appears in the web dashboard, the rider app, and nowhere on the kiosk (a kiosk device is bound to one team's event).
- Notifications carry the team's short name when the person is in more than one team.
- No cross-team visibility of inventory, riders, or events. Lending between teams is a manual note in v1.
- Billing, if it comes, is per team and is the owner's concern. Not designed here.

## 16. Edge cases

- **Manager removes themselves.** Blocked if they are the last owner or manager.
- **Two members with the same PIN.** Blocked at set time; PINs are unique within a team.
- **Rider joins by link with a different name than the kiosk-only record Axel created.** The manager gets a "merge with existing member?" prompt listing kiosk-only members with similar names.
- **Label prefix change after items exist.** Not allowed; the code is identity. A new prefix can be added as a new category alias if the team really needs it.
- **Team time zone differs from event time zone.** Event times display in the event's zone; the end-of-day reminder uses the event's zone during Live.

## 17. Out of scope for v1

- Billing and plans.
- Team-to-team lending or shared inventory.
- Riders registering their own gear items from the app (managers do it).
- Audit log of settings changes beyond the movement log (candidate for v2 once there are several managers).

## 18. Specification set complete

With this document the v1 specification covers the brief end to end:

| Doc | Covers |
|---|---|
| 00 | Original brief |
| 01 | Roles, data model, views, allocation rules, decisions, phasing |
| 02 | Manager event hub |
| 03 | Kiosk |
| 04 | Inventory and item detail |
| 05 | Battery charge estimation |
| 06 | Rider app |
| 07 | Team and member settings, onboarding |

Next steps are the build plan: confirm the stack, define the backend schema from the data model, and start with the backend plus kiosk so the first event can run on the real thing.
