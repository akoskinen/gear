# Rider App — iPhone (draft v0.1)

The rider app is each rider's personal window into the team's logistics. It answers three questions: which events am I going to, what do I need for them, and what gear do I have right now. It is deliberately small. The kiosk handles the moment of taking and returning gear; the rider app handles everything before and after.

Related: [product outline](01-product-outline.md), [event hub](02-event-hub-spec.md), [kiosk](03-kiosk-spec.md), [battery charge estimation](05-battery-charge-estimation.md).

## 1. Purpose and principles

- **Ask early, not at the tent.** The pre-event request is the main job. If riders state needs a week out, Axel packs the right gear and race morning is calm.
- **Show, don't manage.** Riders see their gear, reservations, and battery ready times. They do not edit inventory or events. Anything that changes shared state goes through the kiosk or Axel.
- **Same identity everywhere.** The rider signs in once on their phone. The PIN is only for the shared kiosk. A rider who belongs to two teams switches teams in the app; the kiosk never needs to know.
- **Quiet by default.** Notifications are few and each one is actionable.

## 2. Structure

Three tabs. No more.

```
┌────────────────────────────────────────┐
│  Menton Open · in 6 days               │  ← next event card, always on top
│  You're confirmed · 2 requests open    │
├────────────────────────────────────────┤
│                                        │
│   (tab content)                        │
│                                        │
├──────────┬──────────────┬──────────────┤
│  Events  │   Requests   │   My gear    │
└──────────┴──────────────┴──────────────┘
```

The next event card is pinned above every tab until that event closes. Tapping it opens the event.

## 3. Events tab

- List of the team's events, upcoming first, with the rider's status on each: Invited, Confirmed, Declined, Not on roster.
- Tap an event to see: dates, location with a map link, venue notes from Axel, the rider's status with **Confirm** and **Can't make it** buttons, their requests for this event, their reservations once Axel has set them, and the essentials Axel has marked as "bring your own" (for example lunch on Sunday).
- Invited events show a gentle badge on the tab until answered. This is how Axel gets roster confirmations without chasing.
- Past events show what the rider took and returned, useful for remembering which wing worked in which conditions.
- Riders cannot create events. If a rider belongs to several teams, the list is filtered to the selected team with a switcher at the top.

## 4. Requests tab

This is the pre-event inquiry from the brief, made into a form that takes under a minute.

### 4.1 Request list

- One card per upcoming event the rider is confirmed or invited for, showing the request status: Not started, Submitted, Seen by Axel, Planned, Fulfilled, Partly declined.
- A request deadline per event, set by Axel (default: 5 days before start). The card shows "requests close in 2 days" and turns amber inside 48 hours. After the deadline the form still works but the card says "late requests may not be possible".

### 4.2 Request form

One request per rider per event, editable until Axel marks it Planned. It has four sections, each optional:

```
┌────────────────────────────────────────┐
│  Menton Open — what do you need?       │
│                                        │
│  GEAR                                  │
│  [ Front wing 170 ]  [ Mast 72 ]  [+]  │
│  Picked from the team's catalogue.     │
│  Type a size or name to add.           │
│                                        │
│  BATTERIES                             │
│  How many per day?   [ 2 ] [ 3 ] [ 4 ] │
│  Firmware note:  "2.3 please"          │
│                                        │
│  SPARES                                │
│  [ Prop ]  [ Fuse ]  [ Mast bolts ] [+]│
│                                        │
│  ANYTHING ELSE                         │
│  "Testing the new fuselage if it's     │
│   back from repair"                    │
│                                        │
│            [ Send to Axel ]            │
└────────────────────────────────────────┘
```

- **Gear** is picked from the team's catalogue of models, not specific items. A rider asks for "a 170 front wing"; Axel decides which one and reserves it. Core riders may name a specific item ("FW-170-02, the one I used in Portugal") in the free text.
- **Batteries** asks for a count per race day rather than specific batteries, plus a firmware note. This feeds Axel's charger planning.
- **Spares** are chips from a short team list plus free text.
- **Anything else** is free text.
- Sending creates the request in the hub inbox. Editing after sending resets its status to Submitted and notifies Axel of the change.
- "Same as last event" pre-fills the form from the rider's previous request. Most requests are repeats with one change.

### 4.3 After sending

- Status updates arrive as notifications: "Axel planned your Menton gear" or "Axel couldn't do the 200 wing: only one and it's Manel's".
- Planned requests show the specific items Axel reserved, with their label codes, so the rider knows what to look for on the kiosk.

## 5. My gear tab

What the rider holds and what is reserved for them, live.

- **Out with me:** items currently checked out to the rider, with label code, model, and elapsed time. During an event this is the most-looked-at screen. Tapping an item shows its detail (model, notes Axel has left, last condition) but returning is done at the kiosk, not here.
- **Reserved for me:** items Axel reserved for the current or next event, with location (still at HQ, in the van, at the tent) so the rider knows if their board has arrived.
- **Batteries:** the event's battery strip in read-only form, the same ordering as the hub: ready first with percentage, charging with ready time, then low. This lets a rider decide whether to wait or grab a different one without walking to the tent. Estimates are marked "est." as everywhere.
- **Overdue reminder:** at the team's end-of-day time, if the rider still has gear out, one notification: "You still have BAT-07 and BRD-03 out. Return them at the kiosk." No nagging beyond that.

### 5.1 What My gear does not do in v1

- No check-in or check-out from the phone. Two reasons: the kiosk's physical presence at the tent is what makes the log reliable, and a phone-based return would skip the battery percentage and condition prompts or duplicate them. Revisit for v2 with QR scanning, where a rider could scan a battery on the shelf to return it.
- No rider-to-rider transfer.

## 6. Profile and settings

Reached from the rider's avatar on the next event card.

- Name, photo (optional, used on the kiosk roster grid), phone number for Axel.
- Teams the rider belongs to, with the active one marked. Joining a team is by invitation link from that team's manager.
- Kiosk PIN: shown once after Axel sets it, and changeable here with the old PIN. This keeps Axel out of the loop for PIN changes while keeping the manager's reset path.
- Notification toggles: request updates, event invitations, reservation changes, end-of-day reminder. All on by default.
- Preferred wing sizes and mast length, used to pre-fill the request form.

## 7. Notifications

| Trigger | Message | Tap goes to |
|---|---|---|
| Invited to an event | "Axel invited you to Menton Open, 3–5 Oct" | Event, with Confirm button |
| Request deadline in 48 h and no request | "Requests for Menton close in 2 days" | Request form |
| Request planned / declined / changed by Axel | "Axel planned your Menton gear" | Request with reserved items |
| Reservation added or released | "BRD-03 is reserved for you at Menton" | My gear |
| Reserved item arrived on site | "Your gear is at the tent" | My gear |
| End of day with gear out | "You still have 2 items out" | My gear |
| Battery reserved for you is ready | "BAT-09 is ready (est. 85 %)" | Batteries |

Manager broadcast messages ("briefing at 08:30 at the tent") are a v2 candidate; teams have chat apps for that today.

## 8. Sign-in and identity

- Sign in with Apple, or email link. No passwords.
- A rider joins a team through an invitation link or QR from Axel. The invitation carries the team and the initial tier; Axel can adjust later.
- One account, several teams. The team switcher is only shown when there is more than one.
- The kiosk PIN is separate and team-specific, set by the manager and changeable by the rider in the app.

## 9. Offline

- The app caches the rider's events, requests, reservations, and the last battery strip. Everything is readable offline.
- Confirming attendance and editing a request queue and send when back online, with a "will send when online" note.
- The battery strip shows its age when offline ("as of 12 min ago") since estimates keep moving on the server.

## 10. Edge cases

- **Rider is invited to two overlapping events from two teams.** Both show; the app does not arbitrate. Confirming one does not decline the other.
- **Axel declines the whole request.** The rider sees the reason and can edit and resend if the deadline allows.
- **Rider changes their request after Axel planned it.** Allowed until the event goes Live; the request drops back to Submitted with a "changed" marker in the hub so Axel re-plans consciously rather than silently.
- **Rider leaves a team.** They lose access to that team's data in the app immediately; their history stays with the team.
- **Guest rider without the app.** Fully supported: Axel adds them from the hub, sets a PIN, and they use only the kiosk. The app is optional for guests and expected for core and team riders.

## 11. Out of scope for v1

- Check-in or check-out from the phone.
- Chat or broadcast messages.
- Race results, timing, or anything from the sporting side; that belongs to the efoil.racing platform, which this app may link to later.

## 12. Next spec

1. Team and member settings, including onboarding a second team.
