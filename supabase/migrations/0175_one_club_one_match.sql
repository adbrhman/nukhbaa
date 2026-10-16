-- ============================================================================
-- Migration 0175: one club, one match within 12 hours (script 93)
--
-- ADDITIVE ONLY. One trigger function replaced (same name, same trigger).
-- No row of any table is written, changed or removed; rows already there
-- are not checked.
--
-- 0110 refused a second visible, non-test copy of a match only when both
-- sides agreed -- the same catalog team or the same name key. On 2026-10-15
-- an admin added "هوفنهايم - بيشتكاش" beside the sync's "هوفنهايم - بشكتاش":
-- one side agreed, the other was misspelt, and both copies stood. A club
-- does not play two matches within 12 hours, so one side is enough: a
-- visible, non-test fixture may not be written while another visible,
-- non-test fixture kicks off less than 12 hours from it with one of its
-- clubs -- the same catalog team, or the same name key -- on either side.
--
-- The two refusals keep apart, so the admin is told which it is:
--   * both sides agree: unique_violation on fixture_schedules_one_match,
--     as in 0110 (competition.fixture_duplicate, "already added");
--   * one club is in both: unique_violation on fixture_schedules_one_club
--     (the same code, "that club already has a match then").
-- Hiding a fixture, and any update that changes none of its teams, kickoff
-- or visibility, is never refused. Writers of one pair, and of one club,
-- are serialised by advisory locks, taken in one order.
--
-- Safe to re-run.
-- ============================================================================

begin;

create or replace function competition.reject_second_copy_of_match()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_home  text := competition.team_name_key(new.home_team);
  v_away  text := competition.team_name_key(new.away_team);
  v_other uuid;
  v_both  boolean;
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
  -- One club in two matches (0175): a lock per club, the lesser key first.
  perform pg_advisory_xact_lock(
    hashtext('competition.one_club:' || least(v_home, v_away)));
  perform pg_advisory_xact_lock(
    hashtext('competition.one_club:' || greatest(v_home, v_away)));

  select j.fixture_id, j.both_sides
    into v_other, v_both
    from (
      select s.fixture_id,
             s.kickoff_at,
             coalesce(
               (    ((s.home_team_id is not null and s.home_team_id = new.home_team_id)
                     or competition.team_name_key(s.home_team) = v_home)
                and ((s.away_team_id is not null and s.away_team_id = new.away_team_id)
                     or competition.team_name_key(s.away_team) = v_away))
               or
               (    ((s.home_team_id is not null and s.home_team_id = new.away_team_id)
                     or competition.team_name_key(s.home_team) = v_away)
                and ((s.away_team_id is not null and s.away_team_id = new.home_team_id)
                     or competition.team_name_key(s.away_team) = v_home)),
               false) as both_sides,
             coalesce(
               (s.home_team_id is not null
                  and s.home_team_id in (new.home_team_id, new.away_team_id))
               or (s.away_team_id is not null
                  and s.away_team_id in (new.home_team_id, new.away_team_id))
               or competition.team_name_key(s.home_team) in (v_home, v_away)
               or competition.team_name_key(s.away_team) in (v_home, v_away),
               false) as one_club
        from competition.fixture_schedules s
       where s.fixture_id <> new.fixture_id
         and not s.is_test
         and s.hidden_at is null
         and s.kickoff_at > new.kickoff_at - interval '12 hours'
         and s.kickoff_at < new.kickoff_at + interval '12 hours'
    ) j
   where j.both_sides or j.one_club
   order by j.both_sides desc,
            abs(extract(epoch from (j.kickoff_at - new.kickoff_at))),
            j.fixture_id
   limit 1;

  if v_other is not null and v_both then
    raise exception 'fixture % (% - %, %) is the same match as fixture %',
      new.fixture_id, new.home_team, new.away_team, new.kickoff_at, v_other
      using errcode = 'unique_violation',
            constraint = 'fixture_schedules_one_match';
  end if;

  if v_other is not null then
    raise exception 'fixture % (% - %, %) shares a club with fixture % within 12 hours',
      new.fixture_id, new.home_team, new.away_team, new.kickoff_at, v_other
      using errcode = 'unique_violation',
            constraint = 'fixture_schedules_one_club';
  end if;

  return new;
end;
$$;

comment on function competition.reject_second_copy_of_match() is
  'Refuses a second visible, non-test copy of one match within 12 hours '
  '(0110), and a visible, non-test fixture of a club that already has one '
  'within 12 hours (0175). Backstop for RegisterFixtureSchedule.';

insert into ops.applied_migrations (version)
values ('0175_one_club_one_match')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0175_one_club_one_match';                      -- 1 row
-- select obj_description('competition.reject_second_copy_of_match()'::regprocedure)
--  like '%(0175)%';                                                -- true
