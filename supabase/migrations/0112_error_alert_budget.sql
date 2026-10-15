-- ============================================================================
-- Migration 0112: at most six error alerts an hour (audit M-19, batch 142)
--
-- ops.claim_error_alert (0089) decides whether the admins' phones ring for
-- one occurrence of an error, and claims the alert so the same error rings
-- at most once an hour. Nothing bounded the alerts across errors: every new
-- error in a fresh build rang every admin, and `POST /errors/report` takes
-- reports before sign-in, so a script could invent a new error -- or a new
-- build -- for every request and ring the admins all night.
--
-- The server now lets only its own errors and reports from signed-in
-- players alert (RecordError). This migration adds the second bound: once
-- six errors have alerted within the last hour, the next one is kept in the
-- log, counted on the admin home and claimed by nobody, until the hour has
-- room again. A new critical error is the exception: only the server
-- records the critical severity, never an app report, so it always alerts.
--
-- The function keeps its signature, its grants and every other rule of
-- 0089; only the budget is new. The partial index serves the hourly count.
--
-- ADDITIVE ONLY: one function replaced, one index. No data written.
-- Safe to re-run.
-- ============================================================================

begin;

create index if not exists error_groups_last_alert_idx
  on ops.error_groups (last_alert_at)
  where last_alert_at is not null;

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

  -- Six alerts an hour across every error (0112); a new critical error,
  -- which only the server records, is never held back.
  if v_reason <> 'new_critical'
     and (select count(*)
            from ops.error_groups e
           where e.last_alert_at > p_now - interval '1 hour'
             and e.last_alert_at <= p_now) >= 6 then
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
  '(0089); claims the alert so it is sent at most once an hour, and at most '
  'six errors alert in any hour except a new critical one (0112).';

revoke all on function ops.claim_error_alert(bigint, boolean, boolean, timestamptz)
  from public, anon, authenticated;

insert into ops.applied_migrations (version) values ('0112_error_alert_budget')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0112_error_alert_budget';                 -- one row
-- select indexname from pg_indexes
--  where indexname = 'error_groups_last_alert_idx';           -- one row
