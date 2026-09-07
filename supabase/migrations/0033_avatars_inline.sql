-- ============================================================================
-- Migration 0033: avatars move from the storage bucket into the row
--
-- Supersedes the storage half of migration 0032, which is reversed here. That
-- design had the server upload to a public Supabase Storage bucket with the
-- service-role key. It works, but it costs a new production secret on
-- Northflank, a storage adapter, and an outbound upload call -- three moving
-- parts to keep alive so that images can be served by a CDN instead of by the
-- server.
--
-- At this size that trade is backwards. With a 512 KB cap and a user base in
-- the dozens, the entire corpus is a few megabytes; serving it from the
-- server with cache headers costs one request per device per change. So the
-- bytes live in the row, and the whole storage path disappears:
--
--   avatar_bytes       the image itself, capped in the server (never trusted
--                      from the client) and again by the CHECK below
--   avatar_mime        the content type, restricted to the three formats the
--                      client can produce
--   avatar_updated_at  the cache-busting token: the read URL carries it, so a
--                      replaced picture is a different URL and no stale image
--                      survives on a device
--
-- The three columns are set and cleared together -- a row with bytes and no
-- mime would be unservable -- so a CHECK ties them, making the impossible
-- state unrepresentable rather than merely unlikely.
--
-- identity.avatar_reports from 0032 is unaffected: moderation is about what
-- was published, not where the bytes sat.
--
-- Forward-only. Safe to re-run.
-- ============================================================================

alter table identity.users
  add column if not exists avatar_bytes      bytea,
  add column if not exists avatar_mime       text,
  add column if not exists avatar_updated_at timestamptz;

-- 512 KB. The server rejects an oversized upload long before this, with a
-- message the user can act on; this is the backstop that keeps a bug or a
-- direct write from parking an unbounded blob in a hot table.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'users_avatar_consistent'
      and conrelid = 'identity.users'::regclass
  ) then
    alter table identity.users
      add constraint users_avatar_consistent check (
        (avatar_bytes is null
          and avatar_mime is null
          and avatar_updated_at is null)
        or (avatar_bytes is not null
          and avatar_mime in ('image/jpeg', 'image/png', 'image/webp')
          and avatar_updated_at is not null
          and octet_length(avatar_bytes) <= 524288)
      );
  end if;
end
$$;

comment on column identity.users.avatar_bytes is
  'The user''s profile picture, stored inline. NULL means no picture: the '
  'client draws the display-name initial instead.';
comment on column identity.users.avatar_updated_at is
  'When the current picture was set. Travels in the read URL as a cache-'
  'busting token, so replacing a picture invalidates every cached copy.';

-- ---------------------------------------------------------------------------
-- Reverse the 0032 storage half.
-- ---------------------------------------------------------------------------
-- The bucket itself is left in place: Supabase forbids deleting from
-- storage.buckets over SQL (storage.protect_delete raises 42501), and an
-- empty, unreferenced bucket costs nothing. Its policies do come off.
do $$
begin
  execute 'drop policy if exists avatars_select_all on storage.objects';
  execute 'drop policy if exists avatars_no_client_writes on storage.objects';
exception
  when insufficient_privilege then
    raise notice 'avatars storage policies skipped: current role is not owner';
end;
$$;

-- ---------------------------------------------------------------------------
-- Reproject the standings VIEWs: avatar_updated_at replaces avatar_path.
--
-- The views carry only the token, never the bytes: a leaderboard read must
-- not drag image data through a join it does not display. NULL means the
-- participant has no picture, so the client knows to draw the initial without
-- a second request.
-- ---------------------------------------------------------------------------
drop view if exists leaderboard.season_standings_with_movement;
drop view if exists leaderboard.season_standings;

alter table identity.users drop column if exists avatar_path;

create view leaderboard.season_standings as
  select
    p.season_id                        as season_id,
    p.id                               as participant_id,
    max(u.display_name)                as display_name,
    max(u.avatar_updated_at)           as avatar_updated_at,
    coalesce(sum(e.amount), 0)::bigint as total_points,
    count(e.id)::bigint                as entry_count,
    p.joined_at                        as joined_at
  from competition.participants p
  join identity.users u on u.id = p.user_id
  left join ledger.point_entries e
    on e.participant_id = p.id
   and e.round_id in (
         select r.id from competition.rounds r
         where r.season_id = p.season_id
       )
  group by p.season_id, p.id, p.joined_at;

comment on view leaderboard.season_standings is
  'Season-scoped standings projection (Axiom 5). One row per season '
  'participant; display_name and avatar_updated_at are the platform-owned '
  'identity columns (the token only -- never the image bytes). Ranks are '
  'assigned by the pure domain SeasonLeaderboard.rank, not stored here.';

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
      s.season_id, s.participant_id, s.display_name, s.avatar_updated_at,
      s.total_points, s.entry_count, s.joined_at,
      rank() over (partition by s.season_id order by s.total_points desc)
        as current_rank
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
      count(*) filter (where fs.grade = 'exact_scoreline')::bigint
        as exact_count,
      count(*) filter (where fs.grade <> 'pending')::bigint
        as settled_count
    from scoring.fixture_scores fs
    group by fs.participant_id
  )
  select
    live.season_id,
    live.participant_id,
    live.display_name,
    live.avatar_updated_at,
    live.total_points,
    live.entry_count,
    live.joined_at,
    live.current_rank,
    snap.rank                       as previous_rank,
    (snap.rank - live.current_rank) as movement,
    latest.captured_on              as compared_to,
    coalesce(acc.exact_count, 0)    as exact_count,
    coalesce(acc.settled_count, 0)  as settled_count
  from live
  left join latest on latest.season_id = live.season_id
  left join leaderboard.season_rank_snapshots snap
    on snap.season_id = live.season_id
   and snap.participant_id = live.participant_id
   and snap.captured_on = latest.captured_on
  left join accuracy acc on acc.participant_id = live.participant_id;

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
