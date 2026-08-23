-- Migration 0015 — display_name on identity.users, projected through the
-- Hall of Fame VIEW so the board can show a real name instead of the raw
-- user_id UUID (Axiom 5: still no new points source; this only adds an
-- identity-display column and threads it through the existing read-side
-- projection).
--
-- display_name defaults from the local part of email on insert/update via
-- trigger (never null/empty once a row exists), backfilled for existing
-- rows. A user may later rename via the application layer (not covered by
-- this migration); the column stays platform-editable, never derived from
-- auth token claims (Identity ADR: platform-owned once the row exists).
--
-- Forward-only, expand-only. Every statement is guarded — safe to re-run.
-- NOTE: the VIEW is dropped + recreated (not CREATE OR REPLACE) because
-- Postgres forbids renaming/reordering columns of an existing view via
-- REPLACE — this adds a new display_name column ahead of total_points.

alter table identity.users
  add column if not exists display_name text;

comment on column identity.users.display_name is
  'Platform-owned display name shown on leaderboards. Defaults from the '
  'email local-part on insert if not supplied; never null once a row '
  'exists.';

-- ---------------------------------------------------------------------------
-- Default-from-email trigger (insert + update-of-email), so display_name is
-- never left null for a row that has an email.
-- ---------------------------------------------------------------------------
create or replace function identity.default_display_name()
returns trigger
language plpgsql
as $$
begin
  if new.display_name is null or btrim(new.display_name) = '' then
    new.display_name := coalesce(
      nullif(split_part(new.email, '@', 1), ''),
      'Player'
    );
  end if;
  return new;
end;
$$;

drop trigger if exists users_default_display_name on identity.users;
create trigger users_default_display_name
  before insert or update on identity.users
  for each row
  execute function identity.default_display_name();

-- Backfill existing rows.
update identity.users
set display_name = coalesce(nullif(split_part(email, '@', 1), ''), 'Player')
where display_name is null or btrim(display_name) = '';

-- ---------------------------------------------------------------------------
-- Project display_name through the Hall of Fame VIEW. Dropped + recreated
-- (see note above) rather than CREATE OR REPLACE.
-- ---------------------------------------------------------------------------
drop view if exists leaderboard.hall_of_fame_standings;

create view leaderboard.hall_of_fame_standings as
  select
    p.user_id                            as user_id,
    max(u.display_name)                  as display_name,
    coalesce(sum(e.amount), 0)::bigint   as total_points,
    count(distinct p.season_id)::bigint  as seasons_played
  from competition.participants p
  join identity.users u
    on u.id = p.user_id
  left join ledger.point_entries e
    on e.participant_id = p.id
  group by p.user_id;

comment on view leaderboard.hall_of_fame_standings is
  'All-time, cross-season standings projection (Axiom 5). One row per user '
  'with at least one participant row; display_name is the platform-owned '
  'name from identity.users; total_points/seasons_played as before. Ranks '
  'assigned by the pure domain HallOfFame.rank, not stored here.';

do $$
begin
  begin
    execute
      'alter view leaderboard.hall_of_fame_standings set (security_invoker = on)';
  exception when others then
    null;
  end;
end;
$$;

revoke all on leaderboard.hall_of_fame_standings from anon;
grant select on leaderboard.hall_of_fame_standings to authenticated;
