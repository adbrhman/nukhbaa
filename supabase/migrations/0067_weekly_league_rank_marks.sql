-- ============================================================================
-- Migration 0067: the last rank seen per weekly-league member (plan P3-4c)
--
-- "Someone overtook you" needs two looks at a group: the rank a member had
-- and the rank they have now. Standings are derived, never stored (0061),
-- so this table keeps only the previous look, one row per member of a
-- group, overwritten every sweep. It holds no points and decides nothing:
-- who ranks where is still WeeklyLeaguePolicy.order, in Dart.
--
-- Server-only: RLS on, no policy and no grant for anon or authenticated.
--
-- ADDITIVE ONLY. One table, no data written. Safe to re-run.
-- ============================================================================

begin;

create table if not exists gamification.weekly_league_rank_marks (
  league_id uuid        not null,
  user_id   uuid        not null,
  rank      smallint    not null,
  marked_at timestamptz not null default now(),
  constraint weekly_league_rank_marks_pkey primary key (league_id, user_id),
  constraint weekly_league_rank_marks_rank_positive check (rank > 0),
  constraint weekly_league_rank_marks_league_id_fkey foreign key (league_id)
    references gamification.weekly_leagues (id) on delete cascade,
  constraint weekly_league_rank_marks_user_id_fkey foreign key (user_id)
    references identity.users (id) on delete cascade
);

comment on table gamification.weekly_league_rank_marks is
  'The rank each member had at the previous overtaken sweep (plan P3-4c), '
  'overwritten every sweep. Not a standing: standings are derived.';

alter table gamification.weekly_league_rank_marks enable row level security;

revoke all on gamification.weekly_league_rank_marks from anon, authenticated;

commit;

-- Verification (read-only):
-- select count(*) from gamification.weekly_league_rank_marks;          -- 0
