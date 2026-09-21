-- ============================================================================
-- Migration 0065: favorite teams (plan P3-1)
--
-- The first of the three notification types in plan P3-4 is "before your
-- team's match". It needs to know which teams a user follows, and nothing in
-- the schema says so today: 0008 rules out a social follow edge, and
-- football_data.teams (0013) is a catalog with no owner. This is that link.
--
-- ## One row per (user, team)
-- A plain link table, not a column on identity.users: a user may follow more
-- than one club (a local side and a European one is the common case). The
-- limit -- at most three -- is a rule in Dart, not a constraint here: the
-- only writer is the server's PUT /me/favorite-teams, which replaces the
-- whole set in one transaction, and a count limit in SQL would need a
-- trigger for a rule nothing else can break.
--
-- ## Matching a fixture
-- competition.fixture_schedules.home_team_id / away_team_id (0024) point at
-- the same catalog, so "whose team plays today" is one join. A fixture whose
-- team ids are still NULL matches nobody, which is the safe side for a push.
--
-- ## Deletion
-- A user who is deleted takes their links along. A team removed from the
-- catalog simply stops being anyone's favorite; fixtures keep their own
-- ON DELETE RESTRICT, so that can only happen to a team no fixture uses.
--
-- Server-only, like notification_preferences (0063): RLS on, no policy and
-- no grant for anon or authenticated.
--
-- ADDITIVE ONLY. One table, one index, no data written. Safe to re-run.
-- ============================================================================

begin;

create table if not exists identity.user_favorite_teams (
  user_id    uuid        not null,
  team_id    uuid        not null,
  created_at timestamptz not null default now(),
  constraint user_favorite_teams_pkey primary key (user_id, team_id),
  constraint user_favorite_teams_user_id_fkey foreign key (user_id)
    references identity.users (id) on delete cascade,
  constraint user_favorite_teams_team_id_fkey foreign key (team_id)
    references football_data.teams (id) on delete cascade
);

comment on table identity.user_favorite_teams is
  'The teams a user follows (plan P3-1): at most three per user, a rule '
  'enforced by the server, the only writer (PUT /me/favorite-teams). Read '
  'by the pre-match push (plan P3-4a).';

-- The pre-match sweep asks "who follows the teams playing today".
create index if not exists user_favorite_teams_team_id_idx
  on identity.user_favorite_teams (team_id);

alter table identity.user_favorite_teams enable row level security;

revoke all on identity.user_favorite_teams from anon, authenticated;

commit;

-- Verification (read-only):
-- select count(*) from identity.user_favorite_teams;                 -- 0
-- select relrowsecurity from pg_class
--  where oid = 'identity.user_favorite_teams'::regclass;             -- t
