-- ============================================================================
-- Migration 0089: error log alerts and the per-build summary (2026-10-03)
--
-- ADDITIVE ONLY. Four columns on ops.error_groups, ops.record_error()
-- redefined with the same signature and result, one new function; no row
-- of any table is removed, and no existing value changes meaning.
--
-- 1. ops.error_groups gains an hour window -- hour_started_at, hour_count:
--    the occurrences since the window opened, reset when an occurrence
--    lands an hour or more after it opened -- and last_alert_at /
--    last_alert_reason: when the admins were last told about this error,
--    and why.
--
-- 2. ops.record_error() keeps the window. Same arguments, same result.
--
-- 3. ops.claim_error_alert(group, is_new, reopened, now) decides whether
--    the admins hear about this occurrence, and claims the alert so two
--    reports at once never both send it. Reasons, first match wins:
--      reopened        a fixed error came back in a build that never had it;
--      new_critical    a new error marked critical;
--      new_in_release  a new error (not low) in a build first seen in the
--                      last 48 hours -- a fresh release;
--      hourly_spike    more than 20 occurrences in the current hour.
--    An ignored error never alerts, and one error alerts at most once an
--    hour: inside the hour the function answers null.
--
-- Safe to re-run.
-- ============================================================================

begin;

alter table ops.error_groups
  add column if not exists hour_started_at   timestamptz,
  add column if not exists hour_count        integer not null default 0,
  add column if not exists last_alert_at     timestamptz,
  add column if not exists last_alert_reason text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'error_groups_alert_reason_check'
  ) then
    alter table ops.error_groups
      add constraint error_groups_alert_reason_check
      check (
        last_alert_reason is null
        or last_alert_reason in
          ('reopened', 'new_critical', 'new_in_release', 'hourly_spike')
      );
  end if;
end $$;

-- The same function as 0087, now also keeping the hour window.
create or replace function ops.record_error(
  p_fingerprint     text,
  p_problem_code    text,
  p_source          text,
  p_error_type      text,
  p_error_code      text,
  p_message         text,
  p_location_file   text,
  p_location_line   integer,
  p_location_symbol text,
  p_severity        text,
  p_build           text,
  p_occurred_at     timestamptz,
  p_user_id         uuid,
  p_request_id      text,
  p_route           text,
  p_device          text,
  p_os              text,
  p_browser         text,
  p_stack           text,
  p_request_input   jsonb
)
returns table (
  group_id       bigint,
  occurrences    bigint,
  status         text,
  severity       text,
  users_affected integer,
  is_new         boolean,
  reopened       boolean
)
language plpgsql
as $$
#variable_conflict use_column
declare
  v_id        bigint;
  v_occ       bigint;
  v_status    text;
  v_inserted  boolean;
  v_new_build boolean;
  v_reopened  boolean := false;
  v_user      uuid;
  v_rows      integer;
begin
  insert into ops.error_groups as g (
    fingerprint, problem_code, source, error_type, error_code, message,
    location_file, location_line, location_symbol, severity,
    first_build, last_build, first_seen_at, last_seen_at, occurrences,
    hour_started_at, hour_count
  )
  values (
    p_fingerprint, p_problem_code, p_source, p_error_type, p_error_code,
    p_message, p_location_file, p_location_line, p_location_symbol,
    p_severity, p_build, p_build, p_occurred_at, p_occurred_at, 1,
    p_occurred_at, 1
  )
  on conflict on constraint error_groups_fingerprint_key do update
    set occurrences   = g.occurrences + 1,
        last_seen_at  = greatest(g.last_seen_at, excluded.last_seen_at),
        last_build    = case
                          when excluded.last_seen_at >= g.last_seen_at
                            then excluded.last_build
                          else g.last_build
                        end,
        location_line = case
                          when excluded.last_seen_at >= g.last_seen_at
                            then excluded.location_line
                          else g.location_line
                        end,
        -- The hour window starts at the first occurrence after the last
        -- window ended; hour_count is what ops.claim_error_alert reads.
        hour_count = case
                       when g.hour_started_at is not null
                        and excluded.last_seen_at
                            < g.hour_started_at + interval '1 hour'
                         then g.hour_count + 1
                       else 1
                     end,
        hour_started_at = case
                            when g.hour_started_at is not null
                             and excluded.last_seen_at
                                 < g.hour_started_at + interval '1 hour'
                              then g.hour_started_at
                            else excluded.last_seen_at
                          end
  returning g.id, g.occurrences, g.status, (g.xmax = 0)
    into v_id, v_occ, v_status, v_inserted;

  insert into ops.error_group_builds as b (
    group_id, build, first_seen_at, last_seen_at, occurrences
  )
  values (v_id, p_build, p_occurred_at, p_occurred_at, 1)
  on conflict on constraint error_group_builds_pkey do update
    set occurrences  = b.occurrences + 1,
        last_seen_at = greatest(b.last_seen_at, excluded.last_seen_at)
  returning (b.xmax = 0) into v_new_build;

  -- A fixed error showing up in a build that never had it is back.
  if not v_inserted and v_new_build and v_status in ('fixed', 'verified') then
    update ops.error_groups g
       set status            = 'new',
           status_changed_at = p_occurred_at,
           reopened_count    = g.reopened_count + 1,
           last_reopened_at  = p_occurred_at
     where g.id = v_id;
    v_reopened := true;
  end if;

  -- Only a player who still exists is linked; an unknown id is dropped
  -- rather than failing the whole report.
  select u.id into v_user from identity.users u where u.id = p_user_id;
  if v_user is not null then
    insert into ops.error_group_users (group_id, user_id)
    values (v_id, v_user)
    on conflict on constraint error_group_users_pkey do nothing;
    get diagnostics v_rows = row_count;
    if v_rows > 0 then
      update ops.error_groups g
         set users_affected = g.users_affected + 1
       where g.id = v_id;
    end if;
  end if;

  insert into ops.error_samples as s (
    group_id, slot, occurred_at, build, message, request_id, user_id, route,
    device, os, browser, stack, request_input
  )
  values (
    v_id, ((v_occ - 1) % 5)::smallint, p_occurred_at, p_build, p_message,
    p_request_id, v_user, p_route, p_device, p_os, p_browser, p_stack,
    p_request_input
  )
  on conflict on constraint error_samples_pkey do update
    set occurred_at   = excluded.occurred_at,
        build         = excluded.build,
        message       = excluded.message,
        request_id    = excluded.request_id,
        user_id       = excluded.user_id,
        route         = excluded.route,
        device        = excluded.device,
        os            = excluded.os,
        browser       = excluded.browser,
        stack         = excluded.stack,
        request_input = excluded.request_input;

  return query
    select g.id, g.occurrences, g.status, g.severity, g.users_affected,
           v_inserted, v_reopened
      from ops.error_groups g
     where g.id = v_id;
end;
$$;

create or replace function ops.claim_error_alert(
  p_group_id bigint,
  p_is_new   boolean,
  p_reopened boolean,
  p_now      timestamptz
)
returns text
language plpgsql
as $$
#variable_conflict use_column
declare
  g        ops.error_groups%rowtype;
  v_fresh  boolean;
  v_reason text;
begin
  select * into g from ops.error_groups e where e.id = p_group_id for update;
  if not found or g.status = 'ignored' then
    return null;
  end if;

  select coalesce(min(b.first_seen_at) > p_now - interval '48 hours', false)
    into v_fresh
    from ops.error_group_builds b
   where b.build = g.last_build;

  v_reason := case
    when p_reopened then 'reopened'
    when p_is_new and g.severity = 'critical' then 'new_critical'
    when p_is_new and g.severity <> 'low' and v_fresh
         and g.last_build not in ('unknown', 'server-dev') then 'new_in_release'
    when g.hour_count > 20 then 'hourly_spike'
    else null
  end;
  if v_reason is null then
    return null;
  end if;
  if g.last_alert_at is not null
     and g.last_alert_at > p_now - interval '1 hour' then
    return null;
  end if;

  update ops.error_groups e
     set last_alert_at = p_now,
         last_alert_reason = v_reason
   where e.id = p_group_id;
  return v_reason;
end;
$$;

comment on function ops.claim_error_alert(bigint, boolean, boolean, timestamptz) is
  'Whether the admins are told about this occurrence of an error, and why '
  '(0089); claims the alert so it is sent at most once an hour.';

revoke all on function ops.claim_error_alert(bigint, boolean, boolean, timestamptz)
  from public, anon, authenticated;
revoke all on function ops.record_error(
  text, text, text, text, text, text, text, integer, text, text, text,
  timestamptz, uuid, text, text, text, text, text, text, jsonb
) from public, anon, authenticated;

insert into ops.applied_migrations (version) values ('0089_error_log_alerts')
on conflict (version) do nothing;

commit;
