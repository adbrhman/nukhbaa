-- ============================================================================
-- Migration 0032: user avatars (storage, column, reports) -- step 1 of the
-- profile-picture feature. Database only: no endpoint, no client code.
--
-- Three pieces:
--
--   1. identity.users.avatar_path -- the object key inside the bucket, NOT a
--      URL. Storing a key means the public base URL can change (project
--      migration, custom domain, CDN) without a data rewrite, and it keeps
--      the column meaningless to anyone who cannot resolve it.
--
--   2. an `avatars` storage bucket, public-read like `team-logos` (0026).
--      Public because every signed-in viewer of a leaderboard sees every
--      participant's picture anyway, and serving those over signed URLs
--      would mean minting one per row per request for no privacy gain. Keys
--      are random UUIDs, so a URL is unguessable without the row. Writes are
--      denied to every client: uploads go through the server with the
--      service-role key (ADR-002 -- the app performs no direct storage call).
--
--   3. identity.avatar_reports -- the moderation record. Owner decision for
--      launch: pictures publish immediately, any signed-in user may report
--      one, and an admin deletes it. No automated screening and no
--      pre-approval queue; the user base is a known WhatsApp group, not an
--      open sign-up. Moving to pre-approval later is one boolean column on
--      identity.users, not a redesign -- which is why nothing here assumes
--      "visible" and "uploaded" are the same thing beyond the absent column.
--
-- Axioms 2/5 untouched: an avatar is identity decoration. No points, no
-- ranking input, nothing on the ledger path reads this table.
--
-- Forward-only, expand-only. Safe to re-run.
-- ============================================================================

alter table identity.users
  add column if not exists avatar_path text;

comment on column identity.users.avatar_path is
  'Object key of the user''s profile picture inside the `avatars` storage '
  'bucket (never a URL -- the base is resolved at read time). NULL means no '
  'picture: the client renders the display-name initial instead.';

-- ---------------------------------------------------------------------------
-- 2. Storage bucket
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update
  set public = excluded.public;

-- Ownership of storage.objects belongs to supabase_storage_admin. The hosted
-- project's `postgres` reaches it; a local stack's does not, and the CI
-- migration gate died here with 42501 for migration 0026. Skipping is safe
-- for the same reason it was there: Supabase enables RLS on storage.objects
-- itself in both environments, the bucket is public-read with no auth check,
-- and uploads use the service-role key, which bypasses RLS entirely.
do $$
begin
  execute 'alter table storage.objects enable row level security';

  execute 'drop policy if exists avatars_select_all on storage.objects';
  execute $p$
    create policy avatars_select_all
      on storage.objects
      for select
      to anon, authenticated
      using (bucket_id = 'avatars')
  $p$;

  execute 'drop policy if exists avatars_no_client_writes on storage.objects';
  execute $p$
    create policy avatars_no_client_writes
      on storage.objects
      for insert
      to anon, authenticated
      with check (bucket_id = 'avatars' and false)
  $p$;
exception
  when insufficient_privilege then
    raise notice
      'storage.objects RLS/policies skipped: current role does not own the table';
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Reports
-- ---------------------------------------------------------------------------
create table if not exists identity.avatar_reports (
  id            uuid primary key,
  subject_id    uuid not null
                references identity.users (id) on delete cascade,
  reporter_id   uuid not null
                references identity.users (id) on delete cascade,
  -- The key that was live when the report was filed. Kept even after the
  -- picture is replaced or removed, so a report stays readable evidence of
  -- what was actually seen rather than a pointer to whatever is there now.
  reported_path text not null,
  reason        text,
  created_at    timestamptz not null default now(),
  resolved_at   timestamptz,
  -- One open report per (reporter, subject): a second press of the button is
  -- not a second complaint. A new one may be filed once the first is
  -- resolved, since the picture may have changed since.
  constraint avatar_reports_reason_len
    check (reason is null or char_length(btrim(reason)) between 1 and 500)
);

create unique index if not exists avatar_reports_one_open_per_pair
  on identity.avatar_reports (reporter_id, subject_id)
  where resolved_at is null;

create index if not exists avatar_reports_open_idx
  on identity.avatar_reports (created_at desc)
  where resolved_at is null;

comment on table identity.avatar_reports is
  'A user''s report of another user''s profile picture. Launch moderation is '
  'report-then-remove: pictures publish immediately and an admin clears them '
  'on report. resolved_at null = still in the admin queue.';

alter table identity.avatar_reports enable row level security;

revoke all on identity.avatar_reports from anon, authenticated;

-- No client policy at all: reports are filed and resolved through the server,
-- which connects as the table owner. A SELECT policy would let a reporter
-- enumerate who else reported whom, and there is no screen that needs it.

-- ---------------------------------------------------------------------------
-- 4. Project avatar_path through the standings VIEWs
--
-- season_standings must be dropped and recreated to gain a column, and
-- season_standings_with_movement depends on it -- so the dependent view is
-- dropped first and rebuilt after, unchanged except for the new column.
-- ---------------------------------------------------------------------------
drop view if exists leaderboard.season_standings_with_movement;
drop view if exists leaderboard.season_standings;

create view leaderboard.season_standings as
  select
    p.season_id                          as season_id,
    p.id                                  as participant_id,
    max(u.display_name)                  as display_name,
    max(u.avatar_path)                   as avatar_path,
    coalesce(sum(e.amount), 0)::bigint   as total_points,
    count(e.id)::bigint                  as entry_count,
    p.joined_at                          as joined_at
  from competition.participants p
  join identity.users u
    on u.id = p.user_id
  left join ledger.point_entries e
    on e.participant_id = p.id
   and e.round_id in (
         select r.id
         from competition.rounds r
         where r.season_id = p.season_id
       )
  group by p.season_id, p.id, p.joined_at;

comment on view leaderboard.season_standings is
  'Season-scoped standings projection (Axiom 5). One row per season '
  'participant (ACTIVE or WITHDRAWN); display_name and avatar_path are the '
  'platform-owned identity columns; total_points/entry_count/joined_at as '
  'before. Ranks are assigned by the pure domain SeasonLeaderboard.rank, not '
  'stored here.';

do $$
begin
  begin
    execute
      'alter view leaderboard.season_standings set (security_invoker = on)';
  exception when others then
    null;
  end;
end;
$$;

revoke all on leaderboard.season_standings from anon;
grant select on leaderboard.season_standings to authenticated;

create view leaderboard.season_standings_with_movement as
  with live as (
    select
      s.season_id,
      s.participant_id,
      s.display_name,
      s.avatar_path,
      s.total_points,
      s.entry_count,
      s.joined_at,
      rank() over (
        partition by s.season_id
        order by s.total_points desc
      ) as current_rank
    from leaderboard.season_standings s
  ),
  latest as (
    select season_id, max(captured_on) as captured_on
    from leaderboard.season_rank_snapshots
    group by season_id
  ),
  accuracy as (
    select
      fs.participant_id,
      count(*) filter (
        where fs.grade = 'exact_scoreline'
      )::bigint as exact_count,
      count(*) filter (
        where fs.grade <> 'pending'
      )::bigint as settled_count
    from scoring.fixture_scores fs
    group by fs.participant_id
  )
  select
    live.season_id,
    live.participant_id,
    live.display_name,
    live.avatar_path,
    live.total_points,
    live.entry_count,
    live.joined_at,
    live.current_rank,
    snap.rank                            as previous_rank,
    (snap.rank - live.current_rank)      as movement,
    latest.captured_on                   as compared_to,
    coalesce(acc.exact_count, 0)         as exact_count,
    coalesce(acc.settled_count, 0)       as settled_count
  from live
  left join latest
    on latest.season_id = live.season_id
  left join leaderboard.season_rank_snapshots snap
    on snap.season_id      = live.season_id
   and snap.participant_id = live.participant_id
   and snap.captured_on    = latest.captured_on
  left join accuracy acc
    on acc.participant_id = live.participant_id;

comment on view leaderboard.season_standings_with_movement is
  'season_standings plus the live 1224 rank, its delta against the most '
  'recent daily snapshot, and the exact/settled fixture counts behind the '
  'accuracy figure. movement > 0 means climbed; NULL means no comparable '
  'snapshot. settled_count = 0 means no accuracy exists yet.';

do $$
begin
  begin
    execute
      'alter view leaderboard.season_standings_with_movement '
      'set (security_invoker = on)';
  exception when others then
    null;
  end;
end;
$$;

revoke all on leaderboard.season_standings_with_movement from anon;
grant select on leaderboard.season_standings_with_movement to authenticated;
