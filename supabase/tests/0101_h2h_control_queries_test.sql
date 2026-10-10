-- End-to-end test of the statements PostgresH2hControlStore and
-- PostgresH2hMonthReportReader run (0100/0101). The PREPARE statements
-- below are generated from the adapters' SQL constants, text for text, with
-- @name::type turned into $n::type. Rolled back at the end.
\set ON_ERROR_STOP on
begin;

create function pg_temp.check(ok boolean, label text) returns void
language plpgsql as $$
begin
  if ok is not true then
    raise exception 'FAILED: %', label;
  end if;
  raise notice 'ok - %', label;
end $$;

-- The constraint name [stmt] raises, or 'none'.
create function pg_temp.refusal(stmt text) returns text
language plpgsql as $$
declare
  v_constraint text;
begin
  execute stmt;
  return 'none';
exception when others then
  get stacked diagnostics v_constraint = constraint_name;
  return coalesce(v_constraint, sqlerrm);
end $$;

-- Rows [stmt] touched (an INSERT/DELETE ... RETURNING cannot fill a table).
create function pg_temp.rows(stmt text) returns integer
language plpgsql as $$
declare
  n integer;
begin
  execute stmt;
  get diagnostics n = row_count;
  return n;
end $$;

-- settingsSql
PREPARE cs_settings AS

SELECT auto_approve            AS auto_approve,
       auto_approve_lead_hours AS lead_hours,
       min_active_days         AS min_active_days,
       updated_by::text        AS updated_by,
       updated_at              AS updated_at
FROM gamification.h2h_settings
WHERE id;

-- saveSettingsSql
PREPARE cs_save_settings(boolean, smallint, smallint, uuid) AS

UPDATE gamification.h2h_settings
SET auto_approve            = $1::boolean,
    auto_approve_lead_hours = $2::smallint,
    min_active_days         = $3::smallint,
    updated_by              = $4::uuid,
    updated_at              = now()
WHERE id;

-- excludedDaysSql
PREPARE cs_excluded_days(date, date) AS

SELECT to_char(day, 'YYYY-MM-DD') AS day
FROM gamification.h2h_day_exclusions
WHERE day BETWEEN $1::date AND $2::date
ORDER BY day;

-- excludeSql
PREPARE cs_exclude(date, uuid) AS

INSERT INTO gamification.h2h_day_exclusions (day, excluded_by)
VALUES ($1::date, $2::uuid)
ON CONFLICT (day) DO NOTHING
RETURNING 1 AS excluded;

-- includeSql
PREPARE cs_include(date) AS

DELETE FROM gamification.h2h_day_exclusions
WHERE day = $1::date
RETURNING 1 AS included;

-- addSeatSql
PREPARE cs_add_seat(uuid, date, uuid, smallint) AS

INSERT INTO gamification.h2h_league_members
  (league_id, month_start, user_id, slot)
VALUES ($1::uuid, $2::date, $3::uuid, $4::smallint);

-- recordSql
PREPARE cs_record(uuid, text, uuid, jsonb) AS

INSERT INTO gamification.h2h_admin_actions (id, action, actor, detail)
VALUES ($1::uuid, $2::text, $3::uuid, $4::jsonb);

-- recentSql
PREPARE cs_recent(integer) AS

SELECT id::text     AS id,
       action       AS action,
       actor::text  AS actor,
       detail::text AS detail,
       acted_at     AS acted_at
FROM gamification.h2h_admin_actions
ORDER BY acted_at DESC, id
LIMIT $1::integer;

-- reportSql
PREPARE mr_report(date) AS

SELECT m.drawn_at                                      AS drawn_at,
       COALESCE(m.is_pilot, false)                     AS is_pilot,
       COALESCE(m.seated_count, 0)                     AS drawn_seats,
       (SELECT count(*)::integer
          FROM gamification.h2h_league_members lm
         WHERE lm.month_start = $1::date)          AS seats,
       (SELECT COALESCE(string_agg(g.division || ':' || g.n, ','
                                   ORDER BY g.division), '')
          FROM (SELECT l.division, count(*)::integer AS n
                  FROM gamification.h2h_leagues l
                 WHERE l.month_start = $1::date
                 GROUP BY l.division) g)               AS groups,
       c.closed_at                                     AS closed_at,
       COALESCE(c.member_count, 0)                     AS closed_members,
       (SELECT COALESCE(string_agg(o.outcome || ':' || o.n, ','
                                   ORDER BY o.outcome), '')
          FROM (SELECT e.payload ->> 'outcome' AS outcome,
                       count(*)::integer       AS n
                  FROM gamification.events e
                 WHERE e.event_type = 'h2h_league_finished'
                   AND e.payload ->> 'month' = to_char($1::date, 'YYYY-MM-DD')
                 GROUP BY 1) o)                        AS outcomes
FROM (SELECT 1) one
LEFT JOIN gamification.h2h_months m ON m.month_start = $1::date
LEFT JOIN gamification.h2h_month_closures c ON c.month_start = $1::date;


insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0103-4000-8103-000000000001', 's1@t.io', now()),
  ('00000000-0103-4000-8103-000000000002', 's2@t.io', now()),
  ('00000000-0103-4000-8103-000000000003', 's3@t.io', now());
insert into identity.users (id, email, display_name) values
  ('00000000-0103-4000-8103-000000000001', 's1@t.io', 'S One'),
  ('00000000-0103-4000-8103-000000000002', 's2@t.io', 'S Two'),
  ('00000000-0103-4000-8103-000000000003', 's3@t.io', 'S Three');

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
create temp table s_before as execute cs_settings;
execute cs_save_settings(false, 12, 4, '00000000-0103-4000-8103-000000000001');
create temp table s_after as execute cs_settings;
do $$
begin
  perform pg_temp.check(
    (select auto_approve and lead_hours = 24 and min_active_days = 5
            and updated_by is null from s_before),
    'the settings start as the rules of 0100');
  perform pg_temp.check(
    (select not auto_approve and lead_hours = 12 and min_active_days = 4
            and updated_by = '00000000-0103-4000-8103-000000000001'
       from s_after),
    'saving replaces them and says who');
  perform pg_temp.check(
    pg_temp.refusal($q$execute cs_save_settings(true, 30, 5, null)$q$)
      = 'h2h_settings_lead_range',
    'a lead past 24 hours is refused by its constraint');
end $$;

-- ---------------------------------------------------------------------------
-- Exclusions
-- ---------------------------------------------------------------------------
create temp table x_counts (step text, n integer);
insert into x_counts values
  ('x1', pg_temp.rows($q$execute cs_exclude('2099-11-05', '00000000-0103-4000-8103-000000000001')$q$));
insert into x_counts values
  ('x2', pg_temp.rows($q$execute cs_exclude('2099-11-05', '00000000-0103-4000-8103-000000000001')$q$));
insert into x_counts values
  ('x3', pg_temp.rows($q$execute cs_exclude('2099-11-09', '00000000-0103-4000-8103-000000000001')$q$));
create temp table x_days as execute cs_excluded_days('2099-11-01', '2099-11-06');
insert into x_counts values ('i1', pg_temp.rows($q$execute cs_include('2099-11-05')$q$));
insert into x_counts values ('i2', pg_temp.rows($q$execute cs_include('2099-11-05')$q$));
create temp table x_left as execute cs_excluded_days('2099-11-01', '2099-11-30');
do $$
begin
  perform pg_temp.check(
    (select n = 1 from x_counts where step = 'x1') and (select n = 0 from x_counts where step = 'x2'),
    'a day is excluded once; the second time says nothing new');
  perform pg_temp.check(
    (select array_agg(day order by ctid) from x_days) = array['2099-11-05'],
    'excluded days within a range, inclusive');
  perform pg_temp.check(
    (select n = 1 from x_counts where step = 'i1') and (select n = 0 from x_counts where step = 'i2'),
    'an exclusion is lifted once');
  perform pg_temp.check(
    (select array_agg(day) from x_left) = array['2099-11-09'],
    'the other exclusion stays');
end $$;

-- ---------------------------------------------------------------------------
-- A late seat
-- ---------------------------------------------------------------------------
insert into gamification.h2h_months (month_start, is_pilot, seated_count) values
  ('2099-11-01', false, 1);
insert into gamification.h2h_leagues (id, month_start, division, group_index, capacity) values
  ('c1030000-0000-4000-8000-0000000000e1', '2099-11-01', 1, 0, 4);
insert into gamification.h2h_league_members (league_id, month_start, user_id, slot) values
  ('c1030000-0000-4000-8000-0000000000e1', '2099-11-01', '00000000-0103-4000-8103-000000000001', 0);
execute cs_add_seat('c1030000-0000-4000-8000-0000000000e1', '2099-11-01', '00000000-0103-4000-8103-000000000002', 1);
do $$
begin
  perform pg_temp.check(
    exists (select 1 from gamification.h2h_league_members
             where user_id = '00000000-0103-4000-8103-000000000002' and slot = 1),
    'a late player takes an empty seat');
  perform pg_temp.check(
    pg_temp.refusal($q$execute cs_add_seat('c1030000-0000-4000-8000-0000000000e1', '2099-11-01', '00000000-0103-4000-8103-000000000003', 1)$q$)
      = 'h2h_league_members_league_slot_uniq',
    'a taken seat is refused');
  perform pg_temp.check(
    pg_temp.refusal($q$execute cs_add_seat('c1030000-0000-4000-8000-0000000000e1', '2099-11-01', '00000000-0103-4000-8103-000000000002', 2)$q$)
      in ('h2h_league_members_month_user_uniq', 'h2h_league_members_pkey'),
    'a player seated already is refused');
  perform pg_temp.check(
    pg_temp.refusal($q$execute cs_add_seat('c1030000-0000-4000-8000-0000000000e1', '2099-11-01', '00000000-0103-4000-8103-000000000003', 7)$q$)
      = 'h2h_league_members_slot_in_capacity',
    'a seat outside the group is refused');
end $$;

-- ---------------------------------------------------------------------------
-- The admin log
-- ---------------------------------------------------------------------------
execute cs_record('c1030000-0000-4000-8000-0000000000a1', 'day_excluded', '00000000-0103-4000-8103-000000000001', '{"day":"2099-11-09"}');
execute cs_record('c1030000-0000-4000-8000-0000000000a2', 'jobs_run', null, '{}');
create temp table log_out as execute cs_recent(1);
create temp table log_all as execute cs_recent(10);
do $$
begin
  perform pg_temp.check((select count(*) = 1 from log_out), 'the log is limited');
  perform pg_temp.check(
    (select count(*) = 2 from log_all)
      and (select (detail::jsonb ->> 'day') = '2099-11-09' from log_all
            where action = 'day_excluded'),
    'the log keeps what was done and to what');
end $$;

-- ---------------------------------------------------------------------------
-- The month report
-- ---------------------------------------------------------------------------
create temp table r_before as execute mr_report('2099-11-01');
insert into gamification.h2h_month_closures (month_start, member_count) values ('2099-11-01', 2);
insert into gamification.events (id, user_id, event_type, dedupe_key, occurred_at, payload, ref_type, ref_id) values
  (gen_random_uuid(), '00000000-0103-4000-8103-000000000001', 'h2h_league_finished',
   'h2h_league_finished:r1', '2099-11-30 21:00Z',
   '{"month":"2099-11-01","division":1,"rank":1,"next_division":1,"outcome":"held"}',
   'h2h_league', 'c1030000-0000-4000-8000-0000000000e1'),
  (gen_random_uuid(), '00000000-0103-4000-8103-000000000002', 'h2h_league_finished',
   'h2h_league_finished:r2', '2099-11-30 21:00Z',
   '{"month":"2099-11-01","division":1,"rank":2,"next_division":2,"outcome":"relegated"}',
   'h2h_league', 'c1030000-0000-4000-8000-0000000000e1');
create temp table r_after as execute mr_report('2099-11-01');
create temp table r_none as execute mr_report('2099-12-01');
do $$
begin
  perform pg_temp.check(
    (select drawn_at is not null and not is_pilot and drawn_seats = 1
            and seats = 2 and groups = '1:1' and closed_at is null
            and closed_members = 0 and outcomes = '' from r_before),
    'a drawn month: the draw, seats now (one added late), groups, not closed');
  perform pg_temp.check(
    (select closed_at is not null and closed_members = 2
            and outcomes = 'held:1,relegated:1' from r_after),
    'a closed month: when, how many, and each outcome');
  perform pg_temp.check(
    (select count(*) = 1 and bool_and(drawn_at is null) and bool_and(seats = 0)
            and bool_and(groups = '') from r_none),
    'a month never drawn reads as one empty row');
end $$;

rollback;
