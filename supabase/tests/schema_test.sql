-- Schema behaviour tests. Run against a fresh database after the migration:
--   psql -v ON_ERROR_STOP=1 -f supabase/tests/schema_test.sql
-- Requires auth.uid() to read request.jwt.claim.sub (as Supabase does).
begin;

create or replace function pg_temp.assert(cond boolean, msg text) returns void language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'ASSERT FAILED: %', msg; end if; end $$;

create or replace function pg_temp.as_user(u uuid) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', u::text, true); perform set_config('request.jwt.claim.role', 'authenticated', true); end $$;

create or replace function pg_temp.expect_error(sql text, pattern text default null) returns void language plpgsql as $$
begin
  execute sql;
  raise exception 'ASSERT FAILED: expected an error from: %', sql;
exception
  when others then
    if sqlerrm like 'ASSERT FAILED:%' then raise; end if;
    if pattern is not null and sqlerrm not like pattern then
      raise exception 'ASSERT FAILED: wrong error "%" (wanted %)', sqlerrm, pattern;
    end if;
end $$;

-- auth users
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'axel@example.com'),
  ('00000000-0000-0000-0000-00000000000b', 'pete@example.com'),
  ('00000000-0000-0000-0000-00000000000c', 'kiosk-a@example.com'),
  ('00000000-0000-0000-0000-00000000000d', 'other-team@example.com');

-- ---------------------------------------------------------------- team A setup (as Axel)
set local role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select create_team('Lift Foils Racing', 'LIFT', 'Martinchel HQ') as team_a \gset

select pg_temp.assert((select count(*) from label_prefixes where team_id = :'team_a') = 10, 'label prefixes seeded');
select pg_temp.assert((select count(*) from essentials_template where team_id = :'team_a') = 14, 'essentials template seeded');

select id as hq from locations where team_id = :'team_a' and kind = 'hq' \gset
select id as axel from team_members where team_id = :'team_a' and role = 'owner' \gset

insert into team_members (team_id, profile_id, display_name, role, tier) values
  (:'team_a', '00000000-0000-0000-0000-00000000000b', 'Pete', 'rider', 'core') returning id as pete \gset
insert into team_members (team_id, profile_id, display_name, role, tier) values
  (:'team_a', '00000000-0000-0000-0000-00000000000c', 'Tent iPad', 'kiosk', 'guest') returning id as kiosk \gset
insert into team_members (team_id, display_name, role, tier) values
  (:'team_a', 'Guest Gina', 'rider', 'guest') returning id as gina \gset

select set_member_pin(:'pete', '1234');
select set_member_pin(:'gina', '4321');

insert into battery_types (team_id, name, minutes_to_80, minutes_80_to_100) values
  (:'team_a', 'Lift 100 Ah', 80, 40) returning id as bt \gset

insert into gear_items (team_id, category, label_code, model, location_id, home_location_id, battery_type_id) values
  (:'team_a', 'battery', 'BAT-07', 'Lift 100 Ah', :'hq', :'hq', :'bt') returning id as bat7 \gset
insert into gear_items (team_id, category, label_code, model, location_id, home_location_id, battery_type_id) values
  (:'team_a', 'battery', 'BAT-09', 'Lift 100 Ah', :'hq', :'hq', :'bt') returning id as bat9 \gset
insert into gear_items (team_id, category, label_code, model, location_id, home_location_id) values
  (:'team_a', 'board', 'BRD-03', 'Lift 4''4', :'hq', :'hq') returning id as brd3 \gset
insert into gear_items (team_id, category, label_code, model, location_id, home_location_id, owner_member_id) values
  (:'team_a', 'board', 'PK-BRD-01', 'Pete''s own', :'hq', :'hq', :'pete') returning id as petes_board \gset

insert into events (team_id, name, location_name, starts_on, ends_on) values
  (:'team_a', 'Menton Open', 'Menton', current_date + 10, current_date + 12) returning id as ev \gset

select pg_temp.assert((select site_location_id is not null from events where id = :'ev'), 'event site location created');
select pg_temp.assert((select request_deadline_on = starts_on - 5 from events where id = :'ev'), 'request deadline defaulted');
select pg_temp.assert((select count(*) from event_essentials where event_id = :'ev') = 14, 'essentials copied to event');
select site_location_id as site from events where id = :'ev' \gset

insert into event_roster (event_id, member_id, team_id, status) values
  (:'ev', :'pete', :'team_a', 'confirmed'), (:'ev', :'gina', :'team_a', 'confirmed');

insert into manifest_items (event_id, item_id, team_id) values
  (:'ev', :'bat7', :'team_a'), (:'ev', :'bat9', :'team_a'), (:'ev', :'brd3', :'team_a'), (:'ev', :'petes_board', :'team_a');

-- overlapping event may not share an item
insert into events (team_id, name, starts_on, ends_on) values
  (:'team_a', 'Overlap Cup', current_date + 11, current_date + 13) returning id as ev2 \gset
select pg_temp.expect_error(format('insert into manifest_items (event_id, item_id, team_id) values (%L, %L, %L)', :'ev2', :'bat7', :'team_a'), '%overlapping event%');

-- reservation for Pete on BAT-09 (logs a movement)
insert into reservations (event_id, item_id, member_id, team_id, created_by) values (:'ev', :'bat9', :'pete', :'team_a', :'axel');
select pg_temp.assert((select count(*) from movements where item_id = :'bat9' and kind = 'reservation_set') = 1, 'reservation logged');

-- move everything to site
insert into movements (team_id, event_id, item_id, kind, actor_member_id, to_location_id)
select :'team_a', :'ev', item_id, 'location_change', :'axel', :'site' from manifest_items where event_id = :'ev';
select pg_temp.assert((select count(*) from gear_items where location_id = :'site') = 4, 'items relocated to site');

-- ---------------------------------------------------------------- kiosk actions (as the iPad)
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');

select pg_temp.assert((select count(*) from kiosk_pin_hashes(:'team_a')) = 2, 'kiosk can fetch pin hashes');
select pg_temp.assert(verify_member_pin(:'pete', '1234'), 'pete pin ok');
select pg_temp.assert(not verify_member_pin(:'gina', '0000'), 'wrong pin rejected');
select pg_temp.assert(not verify_member_pin(:'gina', '0000'), 'wrong pin 2');
select pg_temp.assert(not verify_member_pin(:'gina', '0000'), 'wrong pin 3');
select pg_temp.assert(not verify_member_pin(:'gina', '4321'), 'locked out after 3 failures even with right pin');

-- Gina tries Pete's reserved battery: allowed but flagged
insert into movements (team_id, event_id, item_id, kind, actor_member_id, subject_member_id, client_event_id)
values (:'team_a', :'ev', :'bat9', 'checkout', :'kiosk', :'gina', '11111111-1111-1111-1111-111111111111') returning conflict_reason as cr \gset
select pg_temp.assert(:'cr' = 'item reserved for another rider', 'conflict flagged for reserved item');

-- offline replay of the same event is ignored by the unique index
select pg_temp.expect_error(format('insert into movements (team_id, event_id, item_id, kind, actor_member_id, subject_member_id, client_event_id) values (%L, %L, %L, ''checkout'', %L, %L, ''11111111-1111-1111-1111-111111111111'')', :'team_a', :'ev', :'bat9', :'kiosk', :'gina'), '%duplicate key%');

-- Gina returns it at 30%, onto the charger, one hour ago
insert into movements (team_id, event_id, item_id, kind, actor_member_id, subject_member_id, reading_pct, payload, occurred_at)
values (:'team_a', :'ev', :'bat9', 'checkin', :'kiosk', :'gina', 30, '{"on_charger": true}', now() - interval '60 minutes');

select pg_temp.assert((select holder_member_id is null and location_id = :'site' from gear_items where id = :'bat9'), 'battery back at site');
select pg_temp.assert((select cycle_count = 0.70 from gear_items where id = :'bat9'), 'cycle count += 0.7');
select pg_temp.assert((select count(*) from charging_sessions where item_id = :'bat9' and ended_at is null) = 1, 'charging session open');

-- estimate: 30% + 50 min to 80, then 10 min of the slow tail = 85%
select pct, charging, ready_at, full_at from battery_estimate(:'bat9') \gset est_
select pg_temp.assert(:est_pct = 85.0, 'estimate is 85% after 60 min, got ' || :est_pct);
select pg_temp.assert(:'est_charging', 'estimate says charging');
select pg_temp.assert(abs(extract(epoch from (:'est_ready_at'::timestamptz - (now() - interval '10 minutes')))) < 2, 'ready 50 min after start');
select pg_temp.assert(abs(extract(epoch from (:'est_full_at'::timestamptz - (now() + interval '30 minutes')))) < 2, 'full 90 min after start');
select pg_temp.assert((select state from battery_status where item_id = :'bat9') = 'ready', 'battery strip shows ready (>= 80 est)');
select pg_temp.assert((select state from battery_status where item_id = :'bat7') = 'unknown', 'battery with no reading is unknown');

-- Pete takes it, reporting 84%: session closes, reading recorded, holder set
insert into movements (team_id, event_id, item_id, kind, actor_member_id, subject_member_id, reading_pct)
values (:'team_a', :'ev', :'bat9', 'checkout', :'kiosk', :'pete', 84) returning coalesce(conflict_reason, '') as cr2 \gset
select pg_temp.assert(:'cr2' = '', 'reserved rider checks out without conflict, got ' || :'cr2');
select pg_temp.assert((select count(*) from charging_sessions where item_id = :'bat9' and ended_at is null) = 0, 'session closed on take');
select pg_temp.assert((select pct from battery_readings where item_id = :'bat9' order by read_at desc limit 1) = 84, 'take reading recorded');
select pg_temp.assert((select state from battery_status where item_id = :'bat9') = 'in_use', 'strip shows in use');

-- damaged return sets needs_check
insert into movements (team_id, event_id, item_id, kind, actor_member_id, subject_member_id, condition_flags)
values (:'team_a', :'ev', :'brd3', 'checkout', :'kiosk', :'pete', '{}');
insert into movements (team_id, event_id, item_id, kind, actor_member_id, subject_member_id, condition_flags)
values (:'team_a', :'ev', :'brd3', 'checkin', :'kiosk', :'pete', '{damaged,loose}');
select pg_temp.assert((select status = 'needs_check' and status_reason = 'damaged, loose' from gear_items where id = :'brd3'), 'damaged return flagged');

-- kiosk may not check out rider-owned gear, nor write manager kinds
select pg_temp.expect_error(format('insert into movements (team_id, event_id, item_id, kind, actor_member_id, subject_member_id) values (%L, %L, %L, ''checkout'', %L, %L)', :'team_a', :'ev', :'petes_board', :'kiosk', :'pete'), '%rider-owned%');
select pg_temp.expect_error(format('insert into movements (team_id, event_id, item_id, kind, actor_member_id, to_status, payload) values (%L, %L, %L, ''status_change'', %L, ''ready'', ''{}'')', :'team_a', :'ev', :'brd3', :'kiosk'), '%row-level security%');

-- kiosk cannot edit inventory
update gear_items set model = 'hacked' where id = :'brd3';
select pg_temp.assert((select model from gear_items where id = :'brd3') <> 'hacked', 'kiosk update silently filtered by RLS');

-- ---------------------------------------------------------------- rider (Pete)
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
select pg_temp.assert((select count(*) from gear_items where team_id = :'team_a') = 4, 'rider reads team inventory');
select pg_temp.assert((select count(*) from gear_items where holder_member_id = :'pete') = 1, 'pete holds bat9');
insert into rider_requests (event_id, member_id, team_id, batteries_per_day, transport_own_gear) values (:'ev', :'pete', :'team_a', 3, true);
insert into rider_setups (member_id, team_id, slot, source, description) values (:'pete', :'team_a', 'board', 'own', 'Lift 4''4 custom');
select pg_temp.expect_error(format('insert into rider_setups (member_id, team_id, slot, source) values (%L, %L, ''board'', ''own'')', :'gina', :'team_a'), '%row-level security%');
select pg_temp.assert((select count(*) from kiosk_pin_hashes(:'team_a')) = 0, 'rider gets no pin hashes');
select set_member_pin(:'pete', '9999', '1234');
select pg_temp.assert(verify_member_pin(:'pete', '9999'), 'rider changed own pin with old pin');

-- ---------------------------------------------------------------- team isolation
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
select create_team('Other Team', 'OTHR') as team_b \gset
select pg_temp.assert((select count(*) from gear_items) = 0, 'other team sees no items');
select pg_temp.assert((select count(*) from events) = 0, 'other team sees no events');
select pg_temp.assert((select count(*) from team_members where team_id = :'team_a') = 0, 'other team sees no members');
select pg_temp.assert((select count(*) from battery_status) = 0, 'other team sees no batteries');
select pg_temp.expect_error(format('insert into movements (team_id, item_id, kind, to_location_id) values (%L, %L, ''location_change'', %L)', :'team_a', :'brd3', :'hq'), '%row-level security%');
select pg_temp.expect_error(format('select set_member_pin(%L, ''0001'')', :'gina'), '%not allowed%');

-- ---------------------------------------------------------------- close event (as Axel)
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select pg_temp.expect_error(format('select close_event(%L)', :'ev'), '%still checked out%');
insert into movements (team_id, event_id, item_id, kind, actor_member_id, reading_pct)
values (:'team_a', :'ev', :'bat9', 'force_checkin', :'axel', 60);
select close_event(:'ev');
select pg_temp.assert((select phase = 'closed' from events where id = :'ev'), 'event closed');
select pg_temp.assert((select count(*) from reservations where event_id = :'ev' and released_at is null) = 0, 'reservations released');
select pg_temp.assert((select count(*) from gear_items where location_id = :'hq') = 4, 'items back home');
select pg_temp.assert((select count(*) from movements where item_id = :'bat9') >= 6, 'bat9 has a history');

-- movements are append-only
select pg_temp.expect_error(format('delete from movements where item_id = %L', :'bat9'), '%denied%');

reset role;
select 'schema tests passed' as result;
rollback;
