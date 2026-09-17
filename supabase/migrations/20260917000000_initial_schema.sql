-- Gear: initial schema
-- Derived from docs/01-product-outline.md and the view specs 02–07.
-- Target: Supabase (Postgres 15+, auth.uid(), RLS). Everything is partitioned by team.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
create type member_role        as enum ('owner','manager','rider','kiosk');
create type rider_tier         as enum ('core','team','guest');
create type setup_slot         as enum ('board','mast_fuselage','front_wing','stabilizer','propulsion','battery','controller');
create type setup_source       as enum ('own','team');
create type gear_category      as enum ('board','mast','front_wing','stabilizer','fuselage','propulsion','battery','controller','charger','spare');
create type item_status        as enum ('ready','needs_check','in_repair','retired');
create type location_kind      as enum ('hq','hq_sub','vehicle','event_site','unknown');
create type event_type         as enum ('race','training','testing','demo');
create type event_phase        as enum ('planned','packing','live','wrap_up','closed');
create type roster_status      as enum ('invited','confirmed','declined','not_coming');
create type request_status     as enum ('submitted','seen','planned','fulfilled','declined');
create type request_line_kind  as enum ('gear','spare','free_text');
create type request_line_status as enum ('open','planned','fulfilled','declined');
create type packing_state      as enum ('planned','packed','loaded','on_site','returned');
create type essential_state    as enum ('todo','confirmed','packed','on_site');
create type movement_kind      as enum (
  'checkout','checkin','force_checkout','force_checkin',
  'location_change','status_change',
  'battery_reading','charging_started','charging_ended',
  'reservation_set','reservation_released',
  'manifest_added','manifest_removed','packing_state',
  'availability_request','import','event_closed','note');
create type reading_source     as enum ('rider_return','rider_take','manager','import','estimate_freeze');

-- ---------------------------------------------------------------------------
-- Profiles (one per auth user)
-- ---------------------------------------------------------------------------
create table profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  display_name  text not null default '',
  photo_url     text,
  phone         text,
  created_at    timestamptz not null default now()
);

-- Every auth user gets a profile row (Supabase convention).
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', split_part(coalesce(new.email, ''), '@', 1)))
  on conflict (id) do nothing;
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
for each row execute function handle_new_user();

-- ---------------------------------------------------------------------------
-- Teams and membership
-- ---------------------------------------------------------------------------
create table teams (
  id                    uuid primary key default gen_random_uuid(),
  name                  text not null,
  short_name            text not null,
  logo_url              text,
  time_zone             text not null default 'Europe/Lisbon',
  end_of_day            time not null default '19:00',
  battery_ready_pct     int  not null default 80 check (battery_ready_pct between 1 and 100),
  request_deadline_days int  not null default 5,
  overdue_hours         int  not null default 6,
  default_chargers      int  not null default 4,
  kiosk_settings        jsonb not null default '{"session_timeout_s":20,"confirm_dismiss_s":4,"ask_pct_at_take":true,"pct_step":10,"theme":"light","sound":true}',
  created_at            timestamptz not null default now(),
  deleted_at            timestamptz
);

create table team_members (
  id            uuid primary key default gen_random_uuid(),
  team_id       uuid not null references teams(id) on delete cascade,
  profile_id    uuid references profiles(id) on delete set null,   -- null = kiosk-only member
  display_name  text not null,
  role          member_role not null default 'rider',
  tier          rider_tier  not null default 'team',
  phone         text,
  active        boolean not null default true,
  created_at    timestamptz not null default now(),
  unique (team_id, profile_id)
);
create index on team_members (team_id, role);

-- PINs live apart from team_members so RLS can hide them entirely.
create table member_pins (
  member_id       uuid primary key references team_members(id) on delete cascade,
  team_id         uuid not null references teams(id) on delete cascade,
  pin_salt        text not null,
  pin_hash        text not null,           -- sha256(salt || pin), verifiable offline on the kiosk
  failed_attempts int  not null default 0,
  locked_until    timestamptz,
  set_at          timestamptz not null default now()
);

create table rider_setups (
  member_id   uuid not null references team_members(id) on delete cascade,
  team_id     uuid not null references teams(id) on delete cascade,
  slot        setup_slot not null,
  source      setup_source not null default 'team',
  description text,
  primary key (member_id, slot)
);

create table invitations (
  id           uuid primary key default gen_random_uuid(),
  team_id      uuid not null references teams(id) on delete cascade,
  token        text not null unique default encode(gen_random_bytes(18), 'base64'),
  role         member_role not null default 'rider',
  tier         rider_tier  not null default 'team',
  created_by   uuid references team_members(id),
  expires_at   timestamptz not null default now() + interval '14 days',
  accepted_by  uuid references team_members(id),
  accepted_at  timestamptz,
  revoked_at   timestamptz
);

-- ---------------------------------------------------------------------------
-- Locations
-- ---------------------------------------------------------------------------
create table locations (
  id          uuid primary key default gen_random_uuid(),
  team_id     uuid not null references teams(id) on delete cascade,
  kind        location_kind not null,
  name        text not null,
  parent_id   uuid references locations(id) on delete set null,
  event_id    uuid,                          -- set for event_site; FK added after events exists
  sort_order  int not null default 0,
  archived_at timestamptz
);
create index on locations (team_id, kind);

-- ---------------------------------------------------------------------------
-- Battery types, label prefixes, catalogue
-- ---------------------------------------------------------------------------
create table battery_types (
  id                 uuid primary key default gen_random_uuid(),
  team_id            uuid not null references teams(id) on delete cascade,
  name               text not null,
  capacity_note      text,
  minutes_to_80      int not null check (minutes_to_80 > 0),
  minutes_80_to_100  int not null check (minutes_80_to_100 > 0),
  archived_at        timestamptz,
  unique (team_id, name)
);

create table label_prefixes (
  team_id      uuid not null references teams(id) on delete cascade,
  category     gear_category not null,
  prefix       text not null,
  seq_width    int  not null default 2 check (seq_width between 2 and 4),
  include_size boolean not null default false,
  primary key (team_id, category)
);

create table catalogue_models (
  id                uuid primary key default gen_random_uuid(),
  team_id           uuid not null references teams(id) on delete cascade,
  category          gear_category not null,
  name              text not null,
  visible_to_riders boolean not null default true,
  sort_order        int not null default 0,
  unique (team_id, category, name)
);

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
create table events (
  id                   uuid primary key default gen_random_uuid(),
  team_id              uuid not null references teams(id) on delete cascade,
  name                 text not null,
  event_type           event_type not null default 'race',
  location_name        text,
  venue_notes          text,
  time_zone            text,
  starts_on            date not null,
  ends_on              date not null check (ends_on >= starts_on),
  phase                event_phase not null default 'planned',
  request_deadline_on  date,
  chargers_available   int,
  charger_speed_factor numeric(4,2) not null default 1.0 check (charger_speed_factor > 0),
  site_location_id     uuid references locations(id),
  created_at           timestamptz not null default now(),
  closed_at            timestamptz
);
create index on events (team_id, starts_on);
alter table locations add constraint locations_event_fk foreign key (event_id) references events(id) on delete cascade;

create table event_roster (
  event_id     uuid not null references events(id) on delete cascade,
  member_id    uuid not null references team_members(id) on delete cascade,
  team_id      uuid not null references teams(id) on delete cascade,
  status       roster_status not null default 'invited',
  invited_at   timestamptz not null default now(),
  responded_at timestamptz,
  primary key (event_id, member_id)
);

create table event_essentials (
  id              uuid primary key default gen_random_uuid(),
  event_id        uuid not null references events(id) on delete cascade,
  team_id         uuid not null references teams(id) on delete cascade,
  name            text not null,
  quantity        int not null default 1,
  owner_member_id uuid references team_members(id) on delete set null,
  lead_time_days  int not null default 2,
  state           essential_state not null default 'todo',
  sort_order      int not null default 0
);

create table essentials_template (
  id              uuid primary key default gen_random_uuid(),
  team_id         uuid not null references teams(id) on delete cascade,
  name            text not null,
  quantity        int not null default 1,
  owner_member_id uuid references team_members(id) on delete set null,
  lead_time_days  int not null default 2,
  sort_order      int not null default 0
);

-- ---------------------------------------------------------------------------
-- Gear
-- ---------------------------------------------------------------------------
create table gear_items (
  id                uuid primary key default gen_random_uuid(),
  team_id           uuid not null references teams(id) on delete cascade,
  category          gear_category not null,
  label_code        text not null,
  model             text not null default '',
  spec              jsonb not null default '{}',           -- size, length, volume, prop, etc.
  serial            text,
  owner_member_id   uuid references team_members(id) on delete set null,  -- null = team-owned
  home_location_id  uuid references locations(id) on delete set null,
  location_id       uuid references locations(id) on delete set null,
  holder_member_id  uuid references team_members(id) on delete set null,
  status            item_status not null default 'ready',
  status_reason     text,
  expected_back_on  date,
  battery_type_id   uuid references battery_types(id) on delete set null,
  firmware_version  text,
  cycle_count       numeric(8,2) not null default 0,
  charger_speed_factor numeric(4,2),                       -- chargers only
  created_at        timestamptz not null default now(),
  retired_at        timestamptz,
  unique (team_id, label_code),
  check (location_id is not null or holder_member_id is not null or status = 'retired')
);
create index on gear_items (team_id, category, status);
create index on gear_items (holder_member_id) where holder_member_id is not null;

create table item_notes (
  id               uuid primary key default gen_random_uuid(),
  item_id          uuid not null references gear_items(id) on delete cascade,
  team_id          uuid not null references teams(id) on delete cascade,
  author_member_id uuid references team_members(id) on delete set null,
  body             text not null,
  created_at       timestamptz not null default now()
);

create table item_photos (
  id           uuid primary key default gen_random_uuid(),
  item_id      uuid not null references gear_items(id) on delete cascade,
  team_id      uuid not null references teams(id) on delete cascade,
  storage_path text not null,
  created_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Requests, reservations, manifest
-- ---------------------------------------------------------------------------
create table rider_requests (
  id                    uuid primary key default gen_random_uuid(),
  event_id              uuid not null references events(id) on delete cascade,
  member_id             uuid not null references team_members(id) on delete cascade,
  team_id               uuid not null references teams(id) on delete cascade,
  status                request_status not null default 'submitted',
  batteries_per_day     int,
  firmware_note         text,
  notes                 text,
  transport_own_gear    boolean not null default false,
  changed_since_planned boolean not null default false,
  decline_reason        text,
  submitted_at          timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  unique (event_id, member_id)
);

-- Per-event setup override; absent rows fall back to rider_setups.
create table request_setup_slots (
  request_id  uuid not null references rider_requests(id) on delete cascade,
  team_id     uuid not null references teams(id) on delete cascade,
  slot        setup_slot not null,
  source      setup_source not null,
  description text,
  primary key (request_id, slot)
);

create table request_lines (
  id                  uuid primary key default gen_random_uuid(),
  request_id          uuid not null references rider_requests(id) on delete cascade,
  team_id             uuid not null references teams(id) on delete cascade,
  kind                request_line_kind not null,
  catalogue_model_id  uuid references catalogue_models(id) on delete set null,
  text                text,
  status              request_line_status not null default 'open',
  planned_item_id     uuid references gear_items(id) on delete set null,
  decline_reason      text
);

create table reservations (
  id              uuid primary key default gen_random_uuid(),
  event_id        uuid not null references events(id) on delete cascade,
  item_id         uuid not null references gear_items(id) on delete cascade,
  member_id       uuid not null references team_members(id) on delete cascade,
  team_id         uuid not null references teams(id) on delete cascade,
  created_by      uuid references team_members(id) on delete set null,
  created_at      timestamptz not null default now(),
  released_at     timestamptz,
  release_reason  text
);
create unique index reservations_one_active_per_item on reservations (event_id, item_id) where released_at is null;
create index on reservations (member_id) where released_at is null;

create table manifest_items (
  id            uuid primary key default gen_random_uuid(),
  event_id      uuid not null references events(id) on delete cascade,
  item_id       uuid not null references gear_items(id) on delete cascade,
  team_id       uuid not null references teams(id) on delete cascade,
  state         packing_state not null default 'planned',
  from_line_id  uuid references request_lines(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (event_id, item_id)
);

-- ---------------------------------------------------------------------------
-- Batteries: readings and charging sessions
-- ---------------------------------------------------------------------------
create table battery_readings (
  id         uuid primary key default gen_random_uuid(),
  item_id    uuid not null references gear_items(id) on delete cascade,
  team_id    uuid not null references teams(id) on delete cascade,
  event_id   uuid references events(id) on delete set null,
  pct        int not null check (pct between 0 and 100),
  source     reading_source not null,
  member_id  uuid references team_members(id) on delete set null,
  read_at    timestamptz not null default now()
);
create index on battery_readings (item_id, read_at desc);

create table charging_sessions (
  id            uuid primary key default gen_random_uuid(),
  item_id       uuid not null references gear_items(id) on delete cascade,
  team_id       uuid not null references teams(id) on delete cascade,
  event_id      uuid references events(id) on delete set null,
  started_at    timestamptz not null default now(),
  start_pct     int not null check (start_pct between 0 and 100),
  speed_factor  numeric(4,2) not null default 1.0,
  ended_at      timestamptz,
  end_pct       int check (end_pct between 0 and 100),
  started_by    uuid references team_members(id) on delete set null,
  ended_by      uuid references team_members(id) on delete set null
);
create unique index charging_one_active on charging_sessions (item_id) where ended_at is null;

-- ---------------------------------------------------------------------------
-- Movement log (append-only). Item state changes go through here.
-- ---------------------------------------------------------------------------
create table movements (
  id                 uuid primary key default gen_random_uuid(),
  team_id            uuid not null references teams(id) on delete cascade,
  event_id           uuid references events(id) on delete set null,
  item_id            uuid references gear_items(id) on delete cascade,
  kind               movement_kind not null,
  actor_member_id    uuid references team_members(id) on delete set null,  -- who tapped
  subject_member_id  uuid references team_members(id) on delete set null,  -- the rider it concerns
  from_location_id   uuid references locations(id) on delete set null,
  to_location_id     uuid references locations(id) on delete set null,
  from_status        item_status,
  to_status          item_status,
  condition_flags    text[] not null default '{}',
  reading_pct        int check (reading_pct between 0 and 100),
  payload            jsonb not null default '{}',   -- e.g. {"on_charger": true}, {"reason": "..."}
  conflict_reason    text,                          -- set by the trigger when the log disagrees with state
  recorded_offline   boolean not null default false,
  device_id          uuid,
  client_event_id    uuid,                          -- idempotency key for offline replay
  occurred_at        timestamptz not null default now(),
  received_at        timestamptz not null default now()
);
create unique index movements_client_event on movements (team_id, client_event_id) where client_event_id is not null;
create index on movements (item_id, occurred_at desc);
create index on movements (event_id, occurred_at desc);
create index on movements (subject_member_id, occurred_at desc);

-- ---------------------------------------------------------------------------
-- Kiosk devices and notifications
-- ---------------------------------------------------------------------------
create table kiosk_devices (
  id              uuid primary key default gen_random_uuid(),
  team_id         uuid not null references teams(id) on delete cascade,
  member_id       uuid not null references team_members(id) on delete cascade,  -- the kiosk-role member this device signs in as
  name            text not null,
  bound_event_id  uuid references events(id) on delete set null,
  last_sync_at    timestamptz,
  unsynced_count  int not null default 0,
  signed_out_at   timestamptz,
  created_at      timestamptz not null default now()
);

create table notifications (
  id          uuid primary key default gen_random_uuid(),
  team_id     uuid not null references teams(id) on delete cascade,
  member_id   uuid not null references team_members(id) on delete cascade,
  kind        text not null,
  title       text not null,
  body        text,
  link        jsonb not null default '{}',
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);
create index on notifications (member_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Role helpers (security definer to avoid RLS recursion on team_members)
-- ---------------------------------------------------------------------------
create or replace function my_member_id(p_team uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select id from team_members
  where team_id = p_team and profile_id = auth.uid() and active
  limit 1
$$;

create or replace function has_role(p_team uuid, variadic p_roles member_role[]) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from team_members
    where team_id = p_team and profile_id = auth.uid() and active and role = any(p_roles))
$$;

create or replace function is_member(p_team uuid) returns boolean
language sql stable as $$ select has_role(p_team, 'owner','manager','rider','kiosk') $$;

create or replace function is_manager(p_team uuid) returns boolean
language sql stable as $$ select has_role(p_team, 'owner','manager') $$;

create or replace function is_staff(p_team uuid) returns boolean
language sql stable as $$ select has_role(p_team, 'owner','manager','kiosk') $$;

-- ---------------------------------------------------------------------------
-- Battery estimate
-- ---------------------------------------------------------------------------
create or replace function battery_estimate(p_item uuid, p_at timestamptz default now())
returns table (
  pct            numeric,
  is_estimate    boolean,
  charging       boolean,
  ready_at       timestamptz,
  full_at        timestamptz,
  last_reading_at timestamptz
)
language plpgsql stable as $$
declare
  r_pct     int;
  r_at      timestamptz;
  r_src     reading_source;
  s         charging_sessions%rowtype;
  t80       numeric;
  t100      numeric;
  thr       numeric;
  eff_min   numeric;      -- effective charging minutes at factor 1.0
  min_to80  numeric;
  cur       numeric;
  min_to_thr numeric;
  min_to_full numeric;
begin
  select br.pct, br.read_at, br.source into r_pct, r_at, r_src
  from battery_readings br where br.item_id = p_item order by br.read_at desc limit 1;

  select cs.* into s from charging_sessions cs where cs.item_id = p_item and cs.ended_at is null;

  if s.id is null then
    pct := r_pct; is_estimate := (r_src = 'estimate_freeze'); charging := false;
    ready_at := null; full_at := null; last_reading_at := r_at;
    return next; return;
  end if;

  select bt.minutes_to_80, bt.minutes_80_to_100, t.battery_ready_pct
    into t80, t100, thr
  from gear_items gi
  join teams t on t.id = gi.team_id
  left join battery_types bt on bt.id = gi.battery_type_id
  where gi.id = p_item;

  if t80 is null then
    -- no charge model: report the start percentage, estimated, no ready time
    pct := s.start_pct; is_estimate := true; charging := true;
    ready_at := null; full_at := null; last_reading_at := r_at;
    return next; return;
  end if;

  eff_min := greatest(0, extract(epoch from (p_at - s.started_at)) / 60.0) * s.speed_factor;

  -- current estimate, piecewise linear
  if s.start_pct < 80 then
    min_to80 := (80 - s.start_pct) / 80.0 * t80;
    if eff_min <= min_to80 then
      cur := s.start_pct + eff_min / t80 * 80.0;
    else
      cur := 80 + least(20.0, (eff_min - min_to80) / t100 * 20.0);
    end if;
  else
    cur := s.start_pct + least(100 - s.start_pct, eff_min / t100 * 20.0);
  end if;

  -- minutes from session start to threshold and to full
  if s.start_pct >= thr then
    min_to_thr := 0;
  elsif thr <= 80 then
    min_to_thr := (thr - s.start_pct) / 80.0 * t80;
  else
    min_to_thr := greatest(0, (80 - s.start_pct)) / 80.0 * t80 + (thr - greatest(80, s.start_pct)) / 20.0 * t100;
  end if;
  min_to_full := greatest(0, (80 - s.start_pct)) / 80.0 * t80 + (100 - greatest(80, s.start_pct)) / 20.0 * t100;

  pct := round(least(100, cur), 1);
  is_estimate := true;
  charging := true;
  ready_at := s.started_at + make_interval(secs => (min_to_thr / s.speed_factor) * 60);
  full_at  := s.started_at + make_interval(secs => (min_to_full / s.speed_factor) * 60);
  last_reading_at := r_at;
  return next;
end $$;

-- Battery strip for the hub, kiosk and rider app
create or replace view battery_status with (security_invoker = true) as
select
  gi.id as item_id,
  gi.team_id,
  gi.label_code,
  gi.model,
  gi.status,
  gi.holder_member_id,
  hm.display_name as holder_name,
  e.pct,
  e.is_estimate,
  e.charging,
  e.ready_at,
  e.full_at,
  e.last_reading_at,
  case
    when gi.status <> 'ready' then gi.status::text
    when gi.holder_member_id is not null then 'in_use'
    when e.charging and e.pct >= t.battery_ready_pct then 'ready'
    when e.charging then 'charging'
    when e.pct is null then 'unknown'
    when e.pct >= t.battery_ready_pct then 'ready'
    else 'low'
  end as state
from gear_items gi
join teams t on t.id = gi.team_id
left join team_members hm on hm.id = gi.holder_member_id
cross join lateral battery_estimate(gi.id) e
where gi.category = 'battery' and gi.retired_at is null;

-- ---------------------------------------------------------------------------
-- Movement trigger: validates, flags conflicts, applies item state
-- ---------------------------------------------------------------------------
create or replace function apply_movement() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  it        gear_items%rowtype;
  ev        events%rowtype;
  res_member uuid;
  est       record;
  factor    numeric;
begin
  if new.item_id is not null then
    select * into it from gear_items where id = new.item_id for update;
    if it.team_id <> new.team_id then
      raise exception 'item % does not belong to team %', new.item_id, new.team_id;
    end if;
  end if;
  if new.event_id is not null then
    select * into ev from events where id = new.event_id;
    if ev.team_id <> new.team_id then
      raise exception 'event % does not belong to team %', new.event_id, new.team_id;
    end if;
  end if;

  case new.kind
  when 'checkout', 'force_checkout' then
    if it.owner_member_id is not null then
      raise exception 'rider-owned item % cannot be checked out', it.label_code;
    end if;
    if new.subject_member_id is null then
      raise exception 'checkout needs subject_member_id';
    end if;
    if new.kind = 'checkout' then
      if it.status <> 'ready' then
        new.conflict_reason := coalesce(new.conflict_reason, 'item was ' || it.status || ' at checkout');
      end if;
      if it.holder_member_id is not null and it.holder_member_id <> new.subject_member_id then
        new.conflict_reason := coalesce(new.conflict_reason, 'item was already with another rider');
      end if;
      if new.event_id is not null then
        select member_id into res_member from reservations
        where event_id = new.event_id and item_id = new.item_id and released_at is null;
        if res_member is not null and res_member <> new.subject_member_id then
          new.conflict_reason := coalesce(new.conflict_reason, 'item reserved for another rider');
        end if;
      end if;
    end if;
    new.from_location_id := it.location_id;
    -- a battery leaving a charger freezes the estimate
    if it.category = 'battery' then
      update charging_sessions set ended_at = new.occurred_at, ended_by = new.actor_member_id,
        end_pct = coalesce(new.reading_pct, (select round(pct) from battery_estimate(it.id, new.occurred_at)))
        where item_id = it.id and ended_at is null;
      if new.reading_pct is not null then
        insert into battery_readings (item_id, team_id, event_id, pct, source, member_id, read_at)
        values (it.id, it.team_id, new.event_id, new.reading_pct, 'rider_take', new.subject_member_id, new.occurred_at);
      end if;
    end if;
    update gear_items set holder_member_id = new.subject_member_id, location_id = null where id = it.id;

  when 'checkin', 'force_checkin' then
    if it.holder_member_id is null then
      new.conflict_reason := coalesce(new.conflict_reason, 'item was not checked out');
    elsif new.subject_member_id is not null and it.holder_member_id <> new.subject_member_id then
      new.conflict_reason := coalesce(new.conflict_reason, 'item was with a different rider');
    end if;
    new.subject_member_id := coalesce(new.subject_member_id, it.holder_member_id);
    new.to_location_id := coalesce(new.to_location_id, ev.site_location_id, it.home_location_id);
    if new.to_location_id is null then
      raise exception 'checkin needs a destination location';
    end if;
    update gear_items set holder_member_id = null, location_id = new.to_location_id where id = it.id;
    if cardinality(new.condition_flags) > 0 then
      new.from_status := it.status; new.to_status := 'needs_check';
      update gear_items set status = 'needs_check', status_reason = array_to_string(new.condition_flags, ', ') where id = it.id;
    end if;
    if it.category = 'battery' then
      if new.reading_pct is not null then
        insert into battery_readings (item_id, team_id, event_id, pct, source, member_id, read_at)
        values (it.id, it.team_id, new.event_id, new.reading_pct, 'rider_return', new.subject_member_id, new.occurred_at);
        update gear_items set cycle_count = cycle_count + (100 - new.reading_pct) / 100.0 where id = it.id;
      end if;
      if coalesce((new.payload->>'on_charger')::boolean, false) then
        factor := coalesce(ev.charger_speed_factor, 1.0);
        insert into charging_sessions (item_id, team_id, event_id, started_at, start_pct, speed_factor, started_by)
        values (it.id, it.team_id, new.event_id, new.occurred_at, coalesce(new.reading_pct, 0), factor, new.actor_member_id);
      end if;
    end if;

  when 'battery_reading' then
    if new.reading_pct is null then raise exception 'battery_reading needs reading_pct'; end if;
    insert into battery_readings (item_id, team_id, event_id, pct, source, member_id, read_at)
    values (it.id, it.team_id, new.event_id, new.reading_pct,
            coalesce((new.payload->>'source')::reading_source, 'manager'), new.actor_member_id, new.occurred_at);
    -- a manual reading restarts the model from that point
    update charging_sessions set start_pct = new.reading_pct, started_at = new.occurred_at
      where item_id = it.id and ended_at is null;

  when 'charging_started' then
    update charging_sessions set ended_at = new.occurred_at, ended_by = new.actor_member_id,
      end_pct = (select round(pct) from battery_estimate(it.id, new.occurred_at))
      where item_id = it.id and ended_at is null;
    select * into est from battery_estimate(it.id, new.occurred_at);
    factor := coalesce(ev.charger_speed_factor, 1.0);
    insert into charging_sessions (item_id, team_id, event_id, started_at, start_pct, speed_factor, started_by)
    values (it.id, it.team_id, new.event_id, new.occurred_at,
            coalesce(new.reading_pct, round(est.pct)::int, 0), factor, new.actor_member_id);
    if new.reading_pct is not null then
      insert into battery_readings (item_id, team_id, event_id, pct, source, member_id, read_at)
      values (it.id, it.team_id, new.event_id, new.reading_pct, 'manager', new.actor_member_id, new.occurred_at);
    end if;

  when 'charging_ended' then
    select * into est from battery_estimate(it.id, new.occurred_at);
    update charging_sessions set ended_at = new.occurred_at, ended_by = new.actor_member_id,
      end_pct = coalesce(new.reading_pct, round(est.pct)::int)
      where item_id = it.id and ended_at is null;
    insert into battery_readings (item_id, team_id, event_id, pct, source, member_id, read_at)
    values (it.id, it.team_id, new.event_id, coalesce(new.reading_pct, round(est.pct)::int, 0),
            case when new.reading_pct is null then 'estimate_freeze' else 'manager' end,
            new.actor_member_id, new.occurred_at);

  when 'location_change' then
    if new.to_location_id is null then raise exception 'location_change needs to_location_id'; end if;
    new.from_location_id := it.location_id;
    update gear_items set location_id = new.to_location_id, holder_member_id = null where id = it.id;

  when 'status_change' then
    if new.to_status is null then raise exception 'status_change needs to_status'; end if;
    if new.to_status <> 'ready' and coalesce(new.payload->>'reason', '') = '' then
      raise exception 'leaving ready needs a reason';
    end if;
    new.from_status := it.status;
    update gear_items set status = new.to_status,
      status_reason = case when new.to_status = 'ready' then null else new.payload->>'reason' end,
      retired_at = case when new.to_status = 'retired' then new.occurred_at else retired_at end
      where id = it.id;
    if new.to_status = 'retired' then
      update reservations set released_at = new.occurred_at, release_reason = 'item retired'
        where item_id = it.id and released_at is null;
    end if;

  else
    -- informational kinds: no side effects
    null;
  end case;

  return new;
end $$;

create trigger movements_apply before insert on movements
for each row execute function apply_movement();

-- Movements are append-only.
create or replace function reject_change() returns trigger language plpgsql as $$
begin raise exception 'movements are append-only'; end $$;
create trigger movements_no_update before update or delete on movements
for each row execute function reject_change();

-- ---------------------------------------------------------------------------
-- Informational log entries from reservations and manifest changes
-- ---------------------------------------------------------------------------
create or replace function log_reservation() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into movements (team_id, event_id, item_id, kind, actor_member_id, subject_member_id)
    values (new.team_id, new.event_id, new.item_id, 'reservation_set', new.created_by, new.member_id);
  elsif tg_op = 'UPDATE' and old.released_at is null and new.released_at is not null then
    insert into movements (team_id, event_id, item_id, kind, subject_member_id, payload)
    values (new.team_id, new.event_id, new.item_id, 'reservation_released', new.member_id,
            jsonb_build_object('reason', new.release_reason));
  end if;
  return new;
end $$;
create trigger reservations_log after insert or update on reservations
for each row execute function log_reservation();

create or replace function check_manifest_overlap() returns trigger
language plpgsql as $$
declare other text;
begin
  select e2.name into other
  from manifest_items m2
  join events e1 on e1.id = new.event_id
  join events e2 on e2.id = m2.event_id
  where m2.item_id = new.item_id and m2.event_id <> new.event_id
    and e2.phase <> 'closed'
    and daterange(e1.starts_on, e1.ends_on, '[]') && daterange(e2.starts_on, e2.ends_on, '[]')
  limit 1;
  if other is not null then
    raise exception 'item is already on the manifest of overlapping event "%"', other;
  end if;
  return new;
end $$;
create trigger manifest_no_overlap before insert on manifest_items
for each row execute function check_manifest_overlap();

create or replace function log_manifest() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into movements (team_id, event_id, item_id, kind) values (new.team_id, new.event_id, new.item_id, 'manifest_added');
  elsif tg_op = 'DELETE' then
    insert into movements (team_id, event_id, item_id, kind) values (old.team_id, old.event_id, old.item_id, 'manifest_removed');
    return old;
  elsif tg_op = 'UPDATE' and old.state <> new.state then
    new.updated_at := now();
    insert into movements (team_id, event_id, item_id, kind, payload)
    values (new.team_id, new.event_id, new.item_id, 'packing_state', jsonb_build_object('from', old.state, 'to', new.state));
  end if;
  return new;
end $$;
create trigger manifest_log_ins after insert on manifest_items for each row execute function log_manifest();
create trigger manifest_log_del after delete on manifest_items for each row execute function log_manifest();
create trigger manifest_log_upd before update on manifest_items for each row execute function log_manifest();

-- ---------------------------------------------------------------------------
-- Event lifecycle
-- ---------------------------------------------------------------------------
create or replace function on_event_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare loc uuid; t teams%rowtype;
begin
  select * into t from teams where id = new.team_id;
  insert into locations (team_id, kind, name, event_id)
  values (new.team_id, 'event_site', coalesce(new.location_name, new.name), new.id) returning id into loc;
  update events set site_location_id = loc,
    request_deadline_on = coalesce(request_deadline_on, starts_on - t.request_deadline_days),
    chargers_available = coalesce(chargers_available, t.default_chargers)
    where id = new.id;
  insert into event_essentials (event_id, team_id, name, quantity, owner_member_id, lead_time_days, sort_order)
  select new.id, team_id, name, quantity, owner_member_id, lead_time_days, sort_order
  from essentials_template where team_id = new.team_id;
  return new;
end $$;
create trigger events_after_insert after insert on events
for each row execute function on_event_insert();

create or replace function close_event(p_event uuid, p_destination uuid default null) returns void
language plpgsql security definer set search_path = public as $$
declare ev events%rowtype; dest uuid; still int;
begin
  select * into ev from events where id = p_event for update;
  if not is_manager(ev.team_id) then raise exception 'not allowed'; end if;
  select count(*) into still from gear_items gi join manifest_items m on m.item_id = gi.id
    where m.event_id = p_event and gi.holder_member_id is not null;
  if still > 0 then raise exception '% item(s) still checked out', still; end if;

  update reservations set released_at = now(), release_reason = 'event closed'
    where event_id = p_event and released_at is null;

  -- items still at the site go to the chosen destination, or home
  update gear_items gi set location_id = coalesce(p_destination, gi.home_location_id)
  from manifest_items m
  where m.item_id = gi.id and m.event_id = p_event and gi.location_id = ev.site_location_id
    and coalesce(p_destination, gi.home_location_id) is not null;

  update manifest_items set state = 'returned' where event_id = p_event;
  update locations set archived_at = now() where id = ev.site_location_id;
  update events set phase = 'closed', closed_at = now() where id = p_event;
  insert into movements (team_id, event_id, kind, actor_member_id)
  values (ev.team_id, p_event, 'event_closed', my_member_id(ev.team_id));
end $$;

-- ---------------------------------------------------------------------------
-- PINs
-- ---------------------------------------------------------------------------
create or replace function set_member_pin(p_member uuid, p_pin text, p_old_pin text default null) returns void
language plpgsql security definer set search_path = public as $$
declare m team_members%rowtype; salt text; ok boolean;
begin
  select * into m from team_members where id = p_member;
  if m.id is null then raise exception 'no such member'; end if;
  if p_pin !~ '^[0-9]{4}$' then raise exception 'PIN must be 4 digits'; end if;
  if is_manager(m.team_id) then
    ok := true;
  elsif m.profile_id = auth.uid() then
    ok := verify_member_pin(p_member, p_old_pin);
    if not ok then raise exception 'old PIN does not match'; end if;
  else
    raise exception 'not allowed';
  end if;
  if exists (select 1 from member_pins mp join member_pins mine on mine.member_id = p_member
             where mp.team_id = m.team_id and mp.member_id <> p_member
               and mp.pin_hash = encode(digest(mp.pin_salt || p_pin, 'sha256'), 'hex')) then
    raise exception 'PIN already in use in this team';
  end if;
  salt := encode(gen_random_bytes(8), 'hex');
  insert into member_pins (member_id, team_id, pin_salt, pin_hash)
  values (p_member, m.team_id, salt, encode(digest(salt || p_pin, 'sha256'), 'hex'))
  on conflict (member_id) do update
    set pin_salt = excluded.pin_salt, pin_hash = excluded.pin_hash,
        failed_attempts = 0, locked_until = null, set_at = now();
end $$;

create or replace function verify_member_pin(p_member uuid, p_pin text) returns boolean
language plpgsql security definer set search_path = public as $$
declare p member_pins%rowtype;
begin
  select * into p from member_pins where member_id = p_member for update;
  if p.member_id is null then return false; end if;
  if not is_member(p.team_id) then raise exception 'not allowed'; end if;
  if p.locked_until is not null and p.locked_until > now() then return false; end if;
  if p.pin_hash = encode(digest(p.pin_salt || coalesce(p_pin, ''), 'sha256'), 'hex') then
    update member_pins set failed_attempts = 0, locked_until = null where member_id = p_member;
    return true;
  end if;
  update member_pins set failed_attempts = failed_attempts + 1,
    locked_until = case when failed_attempts + 1 >= 3 then now() + interval '60 seconds' else locked_until end
    where member_id = p_member;
  return false;
end $$;

-- Kiosk devices fetch salted hashes so PIN entry works offline.
create or replace function kiosk_pin_hashes(p_team uuid)
returns table (member_id uuid, pin_salt text, pin_hash text)
language sql stable security definer set search_path = public as $$
  select mp.member_id, mp.pin_salt, mp.pin_hash
  from member_pins mp
  where mp.team_id = p_team and is_staff(p_team)
$$;

-- ---------------------------------------------------------------------------
-- Team creation with defaults (the onboarding step 1 and 2)
-- ---------------------------------------------------------------------------
create or replace function create_team(p_name text, p_short text, p_home text default 'HQ') returns uuid
language plpgsql security definer set search_path = public as $$
declare t uuid; hq uuid; me uuid;
begin
  if auth.uid() is null then raise exception 'sign in first'; end if;
  insert into profiles (id) values (auth.uid()) on conflict do nothing;
  insert into teams (name, short_name) values (p_name, p_short) returning id into t;
  insert into team_members (team_id, profile_id, display_name, role, tier)
  values (t, auth.uid(), coalesce((select display_name from profiles where id = auth.uid()), p_name || ' owner'), 'owner', 'core')
  returning id into me;
  insert into locations (team_id, kind, name) values (t, 'hq', p_home) returning id into hq;
  insert into locations (team_id, kind, name, parent_id, sort_order) values
    (t, 'hq_sub', 'Workshop', hq, 1), (t, 'hq_sub', 'Charging bay', hq, 2), (t, 'unknown', 'Unknown', null, 99);
  insert into label_prefixes (team_id, category, prefix, include_size) values
    (t,'board','BRD',false),(t,'mast','MST',false),(t,'front_wing','FW',true),(t,'stabilizer','STB',false),
    (t,'fuselage','FUS',false),(t,'propulsion','PRP',false),(t,'battery','BAT',false),(t,'controller','CTL',false),
    (t,'charger','CHG',false),(t,'spare','SPR',false);
  insert into essentials_template (team_id, name, quantity, lead_time_days, sort_order) values
    (t,'Tents',2,7,1),(t,'Tables',2,7,2),(t,'Chairs',6,7,3),(t,'Water',1,2,4),(t,'Lunch per day',1,2,5),
    (t,'Fuel',1,2,6),(t,'Generator',1,7,7),(t,'Tools',1,3,8),(t,'First aid',1,3,9),(t,'Signage and flags',1,7,10),
    (t,'Buoys for the speed track',3,7,11),(t,'Timing gear',1,7,12),(t,'Chargers',4,3,13),(t,'Extension leads',4,3,14);
  return t;
end $$;

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
alter table profiles            enable row level security;
alter table teams               enable row level security;
alter table team_members        enable row level security;
alter table member_pins         enable row level security;
alter table rider_setups        enable row level security;
alter table invitations         enable row level security;
alter table locations           enable row level security;
alter table battery_types       enable row level security;
alter table label_prefixes      enable row level security;
alter table catalogue_models    enable row level security;
alter table events              enable row level security;
alter table event_roster        enable row level security;
alter table event_essentials    enable row level security;
alter table essentials_template enable row level security;
alter table gear_items          enable row level security;
alter table item_notes          enable row level security;
alter table item_photos         enable row level security;
alter table rider_requests      enable row level security;
alter table request_setup_slots enable row level security;
alter table request_lines       enable row level security;
alter table reservations        enable row level security;
alter table manifest_items      enable row level security;
alter table battery_readings    enable row level security;
alter table charging_sessions   enable row level security;
alter table movements           enable row level security;
alter table kiosk_devices       enable row level security;
alter table notifications       enable row level security;

-- profiles: own row, plus read for people who share a team
create policy profiles_self on profiles for all using (id = auth.uid()) with check (id = auth.uid());
create policy profiles_teammates on profiles for select using (
  exists (select 1 from team_members a join team_members b on a.team_id = b.team_id
          where a.profile_id = auth.uid() and b.profile_id = profiles.id));

-- teams
create policy teams_read on teams for select using (is_member(id));
create policy teams_update on teams for update using (has_role(id, 'owner')) with check (has_role(id, 'owner'));

-- team_members
create policy members_read on team_members for select using (is_member(team_id));
create policy members_manage on team_members for all using (is_manager(team_id)) with check (is_manager(team_id));
create policy members_self_update on team_members for update using (profile_id = auth.uid())
  with check (profile_id = auth.uid() and role = (select role from team_members x where x.id = team_members.id));

-- member_pins: no direct access; functions only
-- rider_setups
create policy setups_read on rider_setups for select using (is_member(team_id));
create policy setups_manage on rider_setups for all using (is_manager(team_id)) with check (is_manager(team_id));
create policy setups_self on rider_setups for all
  using (member_id = my_member_id(team_id)) with check (member_id = my_member_id(team_id));

-- invitations
create policy invitations_manage on invitations for all using (is_manager(team_id)) with check (is_manager(team_id));

-- simple manager-writes, member-reads tables
create policy locations_read on locations for select using (is_member(team_id));
create policy locations_manage on locations for all using (is_manager(team_id)) with check (is_manager(team_id));
create policy battery_types_read on battery_types for select using (is_member(team_id));
create policy battery_types_manage on battery_types for all using (is_manager(team_id)) with check (is_manager(team_id));
create policy label_prefixes_read on label_prefixes for select using (is_member(team_id));
create policy label_prefixes_manage on label_prefixes for all using (is_manager(team_id)) with check (is_manager(team_id));
create policy catalogue_read on catalogue_models for select using (is_member(team_id));
create policy catalogue_manage on catalogue_models for all using (is_manager(team_id)) with check (is_manager(team_id));
create policy events_read on events for select using (is_member(team_id));
create policy events_manage on events for all using (is_manager(team_id)) with check (is_manager(team_id));
create policy essentials_read on event_essentials for select using (is_member(team_id));
create policy essentials_manage on event_essentials for all using (is_manager(team_id)) with check (is_manager(team_id));
create policy essentials_owner_update on event_essentials for update
  using (owner_member_id = my_member_id(team_id)) with check (owner_member_id = my_member_id(team_id));
create policy template_read on essentials_template for select using (is_member(team_id));
create policy template_manage on essentials_template for all using (is_manager(team_id)) with check (is_manager(team_id));
create policy gear_read on gear_items for select using (is_member(team_id));
create policy gear_manage on gear_items for all using (is_manager(team_id)) with check (is_manager(team_id));
create policy notes_read on item_notes for select using (is_member(team_id));
create policy notes_manage on item_notes for all using (is_manager(team_id)) with check (is_manager(team_id));
create policy photos_read on item_photos for select using (is_member(team_id));
create policy photos_manage on item_photos for all using (is_manager(team_id)) with check (is_manager(team_id));
create policy reservations_read on reservations for select using (is_member(team_id));
create policy reservations_manage on reservations for all using (is_manager(team_id)) with check (is_manager(team_id));
create policy manifest_read on manifest_items for select using (is_member(team_id));
create policy manifest_manage on manifest_items for all using (is_manager(team_id)) with check (is_manager(team_id));
create policy readings_read on battery_readings for select using (is_member(team_id));
create policy sessions_read on charging_sessions for select using (is_member(team_id));
create policy devices_read on kiosk_devices for select using (is_staff(team_id));
create policy devices_manage on kiosk_devices for all using (is_manager(team_id)) with check (is_manager(team_id));
create policy devices_self_update on kiosk_devices for update
  using (member_id = my_member_id(team_id)) with check (member_id = my_member_id(team_id));

-- roster: managers manage, riders answer their own invitation
create policy roster_read on event_roster for select using (is_member(team_id));
create policy roster_manage on event_roster for all using (is_manager(team_id)) with check (is_manager(team_id));
create policy roster_self_respond on event_roster for update
  using (member_id = my_member_id(team_id)) with check (member_id = my_member_id(team_id));

-- requests: riders own theirs, managers see and update all
create policy requests_read on rider_requests for select using (is_member(team_id));
create policy requests_manage on rider_requests for update using (is_manager(team_id)) with check (is_manager(team_id));
create policy requests_self on rider_requests for all
  using (member_id = my_member_id(team_id)) with check (member_id = my_member_id(team_id));
create policy req_slots_read on request_setup_slots for select using (is_member(team_id));
create policy req_slots_self on request_setup_slots for all
  using (exists (select 1 from rider_requests r where r.id = request_id and r.member_id = my_member_id(team_id)))
  with check (exists (select 1 from rider_requests r where r.id = request_id and r.member_id = my_member_id(team_id)));
create policy req_slots_manage on request_setup_slots for all using (is_manager(team_id)) with check (is_manager(team_id));
create policy req_lines_read on request_lines for select using (is_member(team_id));
create policy req_lines_self on request_lines for all
  using (exists (select 1 from rider_requests r where r.id = request_id and r.member_id = my_member_id(team_id)))
  with check (exists (select 1 from rider_requests r where r.id = request_id and r.member_id = my_member_id(team_id)));
create policy req_lines_manage on request_lines for update using (is_manager(team_id)) with check (is_manager(team_id));

-- movements: everyone in the team reads; managers write anything; kiosks write kiosk kinds
create policy movements_read on movements for select using (is_member(team_id));
create policy movements_manager_insert on movements for insert with check (is_manager(team_id));
create policy movements_kiosk_insert on movements for insert with check (
  has_role(team_id, 'kiosk')
  and kind in ('checkout','checkin','battery_reading','charging_started','charging_ended','availability_request')
  and actor_member_id = my_member_id(team_id));

-- notifications: own only
create policy notifications_self on notifications for all
  using (member_id = my_member_id(team_id)) with check (member_id = my_member_id(team_id));

-- ---------------------------------------------------------------------------
-- Grants (Supabase applies defaults for authenticated; made explicit here)
-- ---------------------------------------------------------------------------
grant usage on schema public to authenticated, anon;
grant select, insert, update, delete on all tables in schema public to authenticated;
revoke all on member_pins from authenticated, anon;
revoke update, delete on movements from authenticated;
revoke insert, update, delete on battery_readings, charging_sessions from authenticated;
grant execute on all functions in schema public to authenticated;
revoke execute on function kiosk_pin_hashes(uuid) from anon;
