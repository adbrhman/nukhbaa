-- ============================================================================
-- Migration 0110: one match is on the schedule once
--
-- ADDITIVE ONLY. One function for a team name's comparison key, one trigger
-- function and one trigger on competition.fixture_schedules. No row of any
-- table is written, changed or removed; rows already there are not checked.
--
-- The Europa League evening of 2026-10-15 was on the schedule twice: the
-- fixtures sync added its ten matches and an admin added the same ten a few
-- minutes later. The server now refuses that (RegisterFixtureSchedule,
-- batch 138); this trigger is the backstop for every other way a fixture
-- is written -- a second provider id for one match, a correction that moves
-- a fixture onto another, a hidden copy shown again, a hand-run insert --
-- whoever writes it (Axiom 6).
--
-- A visible, non-test fixture may not be written while another visible,
-- non-test fixture of the same two sides -- in either order -- kicks off
-- less than 12 hours from it. Two sides are the same when they name the
-- same catalog team, or when their names have the same key (hamza forms,
-- alif maqsura, taa marbuta, case and spaces folded). A name inside another
-- name is not enough (audit C-04: Al Ahli is not Al Ahly (Egypt)). Hiding a
-- fixture, and any update that changes none of its teams, kickoff or
-- visibility, is never refused. Two writers of one pair are serialised by
-- an advisory lock on the pair, so neither can slip past the other.
--
-- The refusal is unique_violation on the name fixture_schedules_one_match;
-- the schedule adapter turns it into competition.fixture_duplicate.
--
-- Safe to re-run.
-- ============================================================================

begin;

create or replace function competition.team_name_key(p_name text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $f$
  select regexp_replace(
           lower(translate(btrim(p_name), 'أإآٱىة', 'اااايه')),
           '[[:space:]]+', '', 'g');
$f$;

comment on function competition.team_name_key(text) is
  'The key two team names are compared by (0110): hamza forms, alif '
  'maqsura, taa marbuta, case and spaces folded.';

create or replace function competition.reject_second_copy_of_match()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_home  text := competition.team_name_key(new.home_team);
  v_away  text := competition.team_name_key(new.away_team);
  v_other uuid;
begin
  if new.is_test or new.hidden_at is not null then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and not old.is_test
     and old.hidden_at is null
     and new.home_team is not distinct from old.home_team
     and new.away_team is not distinct from old.away_team
     and new.home_team_id is not distinct from old.home_team_id
     and new.away_team_id is not distinct from old.away_team_id
     and new.kickoff_at is not distinct from old.kickoff_at then
    return new;
  end if;

  perform pg_advisory_xact_lock(
    hashtext('competition.one_match:'
             || least(v_home, v_away) || '|' || greatest(v_home, v_away)));

  select s.fixture_id
    into v_other
    from competition.fixture_schedules s
   where s.fixture_id <> new.fixture_id
     and not s.is_test
     and s.hidden_at is null
     and s.kickoff_at > new.kickoff_at - interval '12 hours'
     and s.kickoff_at < new.kickoff_at + interval '12 hours'
     and (
       (    ((s.home_team_id is not null and s.home_team_id = new.home_team_id)
             or competition.team_name_key(s.home_team) = v_home)
        and ((s.away_team_id is not null and s.away_team_id = new.away_team_id)
             or competition.team_name_key(s.away_team) = v_away))
       or
       (    ((s.home_team_id is not null and s.home_team_id = new.away_team_id)
             or competition.team_name_key(s.home_team) = v_away)
        and ((s.away_team_id is not null and s.away_team_id = new.home_team_id)
             or competition.team_name_key(s.away_team) = v_home))
     )
   order by abs(extract(epoch from (s.kickoff_at - new.kickoff_at))),
            s.fixture_id
   limit 1;

  if v_other is not null then
    raise exception 'fixture % (% - %, %) is the same match as fixture %',
      new.fixture_id, new.home_team, new.away_team, new.kickoff_at, v_other
      using errcode = 'unique_violation',
            constraint = 'fixture_schedules_one_match';
  end if;

  return new;
end;
$$;

comment on function competition.reject_second_copy_of_match() is
  'Refuses a second visible, non-test copy of one match within 12 hours '
  '(0110). Backstop for RegisterFixtureSchedule (batch 138).';

drop trigger if exists fixture_schedules_one_match
  on competition.fixture_schedules;
create trigger fixture_schedules_one_match
  before insert or update of home_team, away_team, home_team_id,
    away_team_id, kickoff_at, hidden_at, is_test
  on competition.fixture_schedules
  for each row execute function competition.reject_second_copy_of_match();

insert into ops.applied_migrations (version)
values ('0110_one_match_once')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0110_one_match_once';                          -- 1 row
-- select tgname from pg_trigger
--  where tgname = 'fixture_schedules_one_match';                   -- 1 row
-- select competition.team_name_key(' الأهلى  ');                  -- الاهلي
