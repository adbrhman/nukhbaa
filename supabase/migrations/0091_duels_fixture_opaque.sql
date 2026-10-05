-- Migration 0091 - duel fixture ids are opaque, like every season fixture.
--
-- ADDITIVE ONLY. No row is touched; two constraints are dropped.
--
-- Why: 0090 made social.duel_challenges.fixture_id and social.duels.fixture_id
-- foreign keys to football_data.fixtures. Nothing writes that table: the
-- fixtures players predict live in competition.season_fixtures and
-- competition.fixture_schedules, whose fixture_id is an opaque reference with
-- no foreign key (0019). So every real challenge failed with
-- duel_challenges_fixture_id_fkey. The 0090 test inserted the fixture into
-- football_data.fixtures by hand, which hid it.
--
-- Integrity is unchanged where it matters: create_duel_challenge still
-- refuses a fixture that is not linked to the season with a kickoff
-- (duel_fixture_not_in_season), and a duel copies its fixture from its
-- challenge.
--
-- Safe to re-run.

begin;

alter table social.duel_challenges
  drop constraint if exists duel_challenges_fixture_id_fkey;

alter table social.duels
  drop constraint if exists duels_fixture_id_fkey;

comment on column social.duel_challenges.fixture_id is
  'Opaque fixture reference, like competition.season_fixtures.fixture_id '
  '(no foreign key, 0091). create_duel_challenge requires the fixture to be '
  'linked to the season and scheduled.';

comment on column social.duels.fixture_id is
  'Copied from the challenge; opaque like the challenge''s fixture_id (0091).';

insert into ops.applied_migrations (version)
values ('0091_duels_fixture_opaque')
on conflict (version) do nothing;

commit;
