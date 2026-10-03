-- ============================================================================
-- Migration 0087: the error log (2026-10-03)
--
-- Every unexpected failure -- on the server, in the Android app, on the
-- web -- lands here, for the admin dashboard's error log. One row per
-- distinct error (ops.error_groups) carries a counter, never one row per
-- occurrence, so the table stays small without deleting anything:
--
--   ops.error_groups       one row per fingerprint: what, where, severity,
--                          status, assignee, notes, first/last build and
--                          time, occurrences, distinct players affected.
--   ops.error_group_builds one row per (error, build): how often each
--                          release hit it. A build first seen AFTER the
--                          error was marked fixed reopens it.
--   ops.error_group_users  one row per (error, player): the distinct count
--                          behind users_affected.
--   ops.error_samples      the last 5 occurrences of each error in full,
--                          a ring of slots 0..4: the newest replaces the
--                          oldest.
--
-- The fingerprint and the 4-character problem code are computed by the
-- server (packages/shared errorFingerprint) from the error's type, code and
-- top stack frames with line numbers and variable ids removed, so a moved
-- line or a different id is the same error, and the app can show the same
-- problem code offline. Everything stored is redacted by the server first
-- (application RecordError); nothing here holds a password, token, key,
-- install id or email.
--
-- ops.record_error() is the ONLY writer of occurrences: one statement that
-- upserts the group, its build, its player and its sample, so concurrent
-- reports of the same error serialise on the group row instead of racing.
--
-- Server-only: RLS on, no policy, nothing granted to anon or authenticated
-- (as 0070 did for ops.frame_reports).
--
-- ADDITIVE ONLY. No existing row is touched. Safe to re-run.
-- ============================================================================

begin;

create schema if not exists ops;

create table if not exists ops.error_groups (
  id                 bigint generated always as identity primary key,
  fingerprint        text        not null,
  problem_code       text        not null,
  source             text        not null,
  error_type         text        not null,
  error_code         text,
  message            text        not null,
  location_file      text,
  location_line      integer,
  location_symbol    text,
  severity           text        not null default 'medium',
  status             text        not null default 'new',
  assignee_id        uuid
    references identity.users (id) on delete set null,
  admin_notes        text,
  first_build        text        not null,
  last_build         text        not null,
  first_seen_at      timestamptz not null,
  last_seen_at       timestamptz not null,
  occurrences        bigint      not null default 1,
  users_affected     integer     not null default 0,
  status_changed_at  timestamptz,
  reopened_count     integer     not null default 0,
  last_reopened_at   timestamptz,
  constraint error_groups_fingerprint_key unique (fingerprint),
  constraint error_groups_fingerprint_check
    check (fingerprint ~ '^[0-9a-f]{16}$'),
  constraint error_groups_problem_code_check
    check (problem_code ~ '^[A-HJ-NP-Z2-9]{4}$'),
  constraint error_groups_source_check
    check (source in ('android', 'ios', 'web', 'server')),
  constraint error_groups_type_check
    check (length(error_type) between 1 and 120),
  constraint error_groups_code_check
    check (error_code is null or length(error_code) between 1 and 120),
  constraint error_groups_message_check
    check (length(message) between 1 and 1000),
  constraint error_groups_location_check
    check (
      (location_file is null or length(location_file) <= 300)
      and (location_symbol is null or length(location_symbol) <= 300)
      and (location_line is null or location_line >= 0)
    ),
  constraint error_groups_severity_check
    check (severity in ('critical', 'high', 'medium', 'low')),
  constraint error_groups_status_check
    check (status in ('new', 'in_progress', 'fixed', 'verified', 'ignored')),
  constraint error_groups_notes_check
    check (admin_notes is null or length(admin_notes) <= 4000),
  constraint error_groups_build_check
    check (
      first_build ~ '^[0-9A-Za-z._-]{1,40}$'
      and last_build ~ '^[0-9A-Za-z._-]{1,40}$'
    ),
  constraint error_groups_counts_check
    check (occurrences >= 1 and users_affected >= 0 and reopened_count >= 0)
);

comment on table ops.error_groups is
  'One row per distinct error (fingerprint) with a counter; written only by '
  'ops.record_error(), status/assignee/notes by the admin routes (0087).';

create index if not exists error_groups_problem_code_idx
  on ops.error_groups (problem_code);
create index if not exists error_groups_last_seen_idx
  on ops.error_groups (last_seen_at desc);
create index if not exists error_groups_status_idx
  on ops.error_groups (status, last_seen_at desc);

create table if not exists ops.error_group_builds (
  group_id      bigint      not null
    references ops.error_groups (id) on delete cascade,
  build         text        not null,
  first_seen_at timestamptz not null,
  last_seen_at  timestamptz not null,
  occurrences   bigint      not null default 1,
  constraint error_group_builds_pkey primary key (group_id, build),
  constraint error_group_builds_build_check
    check (build ~ '^[0-9A-Za-z._-]{1,40}$'),
  constraint error_group_builds_count_check check (occurrences >= 1)
);

comment on table ops.error_group_builds is
  'Occurrences of each error per build (0087). A build first seen after '
  'the error was fixed reopens it.';

create index if not exists error_group_builds_build_idx
  on ops.error_group_builds (build);

create table if not exists ops.error_group_users (
  group_id bigint not null
    references ops.error_groups (id) on delete cascade,
  user_id  uuid   not null
    references identity.users (id) on delete cascade,
  constraint error_group_users_pkey primary key (group_id, user_id)
);

comment on table ops.error_group_users is
  'Distinct signed-in players hit by each error (0087).';

create table if not exists ops.error_samples (
  group_id      bigint      not null
    references ops.error_groups (id) on delete cascade,
  slot          smallint    not null,
  occurred_at   timestamptz not null,
  build         text        not null,
  message       text        not null,
  request_id    text,
  user_id       uuid
    references identity.users (id) on delete set null,
  route         text,
  device        text,
  os            text,
  browser       text,
  stack         text,
  request_input jsonb,
  constraint error_samples_pkey primary key (group_id, slot),
  constraint error_samples_slot_check check (slot between 0 and 4),
  constraint error_samples_build_check
    check (build ~ '^[0-9A-Za-z._-]{1,40}$'),
  constraint error_samples_message_check
    check (length(message) between 1 and 1000),
  constraint error_samples_request_id_check
    check (request_id is null or request_id ~ '^[0-9A-Za-z-]{8,64}$'),
  constraint error_samples_text_check
    check (
      (route is null or length(route) <= 300)
      and (device is null or length(device) <= 120)
      and (os is null or length(os) <= 120)
      and (browser is null or length(browser) <= 200)
      and (stack is null or length(stack) <= 16000)
    ),
  constraint error_samples_input_check
    check (request_input is null or octet_length(request_input::text) <= 8192)
);

comment on table ops.error_samples is
  'The last 5 occurrences of each error in full (slots 0..4, newest '
  'replaces oldest), already redacted (0087).';

-- One occurrence: upserts the group, its build, its player and its sample.
-- Returns the group as it stands after this occurrence, whether this was
-- the first occurrence ever (is_new), and whether a fixed/verified error
-- came back in a build that had never hit it (reopened -> status 'new').
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
    first_build, last_build, first_seen_at, last_seen_at, occurrences
  )
  values (
    p_fingerprint, p_problem_code, p_source, p_error_type, p_error_code,
    p_message, p_location_file, p_location_line, p_location_symbol,
    p_severity, p_build, p_build, p_occurred_at, p_occurred_at, 1
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

comment on function ops.record_error(
  text, text, text, text, text, text, text, integer, text, text, text,
  timestamptz, uuid, text, text, text, text, text, text, jsonb
) is
  'The only writer of error occurrences (0087): one call per occurrence, '
  'already redacted by the server.';

alter table ops.error_groups enable row level security;
alter table ops.error_group_builds enable row level security;
alter table ops.error_group_users enable row level security;
alter table ops.error_samples enable row level security;
revoke all on ops.error_groups from anon, authenticated;
revoke all on ops.error_group_builds from anon, authenticated;
revoke all on ops.error_group_users from anon, authenticated;
revoke all on ops.error_samples from anon, authenticated;
revoke all on function ops.record_error(
  text, text, text, text, text, text, text, integer, text, text, text,
  timestamptz, uuid, text, text, text, text, text, text, jsonb
) from public, anon, authenticated;

insert into ops.applied_migrations (version) values ('0087_error_log')
on conflict (version) do nothing;

commit;
