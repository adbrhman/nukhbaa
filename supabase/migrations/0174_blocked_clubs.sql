-- ============================================================================
-- Migration 0174: four clubs never on the schedule (script 92)
--
-- ADDITIVE ONLY. One table with its rows, two functions, two trigger
-- functions and two triggers. No match, prediction, point, ledger, team or
-- fixture row is written, changed or removed.
--
-- Decided by the owner on 2026-10-16: no match of these clubs appears in
-- Nukhbaa, in any league, cup, qualifier or friendly, in any season:
--   1. Hapoel Beer Sheva   (هبوعيل بئر السبع)
--   2. Maccabi Tel Aviv    (مكابي تل أبيب)
--   3. Beitar Jerusalem    (بيتار القدس)
--   4. Hapoel Tel Aviv     (هبوعيل تل أبيب)
-- On that day the schedule held one such match, "ألكمار - هابوعيل بئر
-- السبع" of 2026-10-15, already hidden; it stays hidden for good.
--
-- * football_data.club_block_key(name): a name folded the way the list is
--   written -- case, spaces, dashes, dots, brackets and apostrophes
--   dropped, hamza forms, alif maqsura, taa marbuta and tatweel folded.
-- * football_data.blocked_clubs: the fragments of those keys that name one
--   of the four clubs, Arabic and English spellings, so "Hapoel Be'er-Sheva
--   FC" and "هابوعيل بئر السبع" are both caught.
-- * football_data.is_blocked_club(name): whether a name holds one.
-- * competition.fixture_schedules refuses a new fixture with such a side,
--   by its name or by its catalog team, and refuses to show one again; a
--   hidden one may still be corrected while it stays hidden. The refusal is
--   check_violation on the name fixture_schedules_blocked_club.
-- * football_data.teams refuses a new club, or a rename, with such a name
--   (teams_blocked_club). The catalog row the Europa League seed added
--   ("هابوعيل بئر السبع") stays, unused: GET /teams leaves blocked clubs
--   out, and the fixtures sync skips their matches before writing.
--
-- Safe to re-run.
-- ============================================================================

begin;

create or replace function football_data.club_block_key(p_name text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $f$
  select regexp_replace(
           lower(translate(coalesce(p_name, ''), 'أإآٱىةـ', 'اااايه')),
           '[[:space:]''’`ʼ._()-]+', '', 'g');
$f$;

comment on function football_data.club_block_key(text) is
  'A club name folded for the blocked list (0174): case, spaces, dashes, '
  'dots, brackets and apostrophes dropped; hamza forms, alif maqsura, taa '
  'marbuta and tatweel folded.';

create table if not exists football_data.blocked_clubs (
  pattern    text primary key,
  club       text not null,
  created_at timestamptz not null default now(),
  constraint blocked_clubs_pattern_folded
    check (pattern = football_data.club_block_key(pattern)
           and length(pattern) >= 6),
  constraint blocked_clubs_club_not_blank check (btrim(club) <> '')
);

comment on table football_data.blocked_clubs is
  'Fragments of club_block_key that name a club whose matches never appear '
  'in Nukhbaa (0174, decided by the owner 2026-10-16). A name holding one is '
  'refused on the schedule and in the catalog.';

alter table football_data.blocked_clubs enable row level security;
revoke all on football_data.blocked_clubs from anon, authenticated;

insert into football_data.blocked_clubs (pattern, club) values
  -- Hapoel Beer Sheva
  ('بئرالسبع',          'Hapoel Beer Sheva'),
  ('بيرالسبع',          'Hapoel Beer Sheva'),
  ('beersheva',         'Hapoel Beer Sheva'),
  ('beersheba',         'Hapoel Beer Sheva'),
  -- Maccabi Tel Aviv
  ('مكابيتلابيب',       'Maccabi Tel Aviv'),
  ('مكابيتلافيف',       'Maccabi Tel Aviv'),
  ('ماكابيتلابيب',      'Maccabi Tel Aviv'),
  ('ماكابيتلافيف',      'Maccabi Tel Aviv'),
  ('maccabitelaviv',    'Maccabi Tel Aviv'),
  ('makabitelaviv',     'Maccabi Tel Aviv'),
  ('mtelaviv',          'Maccabi Tel Aviv'),
  -- Beitar Jerusalem
  ('بيتارالقدس',        'Beitar Jerusalem'),
  ('بيتاراورشليم',      'Beitar Jerusalem'),
  ('بيتاريروشلايم',     'Beitar Jerusalem'),
  ('beitarjerusalem',   'Beitar Jerusalem'),
  ('betarjerusalem',    'Beitar Jerusalem'),
  ('beitaryerushalayim','Beitar Jerusalem'),
  -- Hapoel Tel Aviv
  ('هبوعيلتلابيب',      'Hapoel Tel Aviv'),
  ('هابوعيلتلابيب',     'Hapoel Tel Aviv'),
  ('هبوعيلتلافيف',      'Hapoel Tel Aviv'),
  ('هابوعيلتلافيف',     'Hapoel Tel Aviv'),
  ('hapoeltelaviv',     'Hapoel Tel Aviv'),
  ('htelaviv',          'Hapoel Tel Aviv')
on conflict (pattern) do nothing;

create or replace function football_data.is_blocked_club(p_name text)
returns boolean
language sql
stable
set search_path = ''
as $f$
  select p_name is not null and exists (
    select 1
      from football_data.blocked_clubs b
     where strpos(football_data.club_block_key(p_name), b.pattern) > 0
  );
$f$;

comment on function football_data.is_blocked_club(text) is
  'Whether [p_name] names a club of football_data.blocked_clubs (0174).';

-- ---------------------------------------------------------------------------
-- 1. the schedule: no fixture with a blocked club, and none shown again
-- ---------------------------------------------------------------------------
create or replace function competition.reject_blocked_club_fixture()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_home text;
  v_away text;
begin
  -- A hidden fixture already there may be corrected while it stays hidden.
  if tg_op = 'UPDATE' and new.hidden_at is not null then
    return new;
  end if;

  select t.name into v_home
    from football_data.teams t where t.id = new.home_team_id;
  select t.name into v_away
    from football_data.teams t where t.id = new.away_team_id;

  if football_data.is_blocked_club(new.home_team)
     or football_data.is_blocked_club(new.away_team)
     or football_data.is_blocked_club(v_home)
     or football_data.is_blocked_club(v_away) then
    raise exception 'fixture % (% - %) names a club that never appears',
      new.fixture_id, new.home_team, new.away_team
      using errcode = 'check_violation',
            constraint = 'fixture_schedules_blocked_club';
  end if;

  return new;
end;
$$;

comment on function competition.reject_blocked_club_fixture() is
  'Refuses a fixture with a club of football_data.blocked_clubs, and showing '
  'one again (0174).';

drop trigger if exists fixture_schedules_blocked_club
  on competition.fixture_schedules;
create trigger fixture_schedules_blocked_club
  before insert or update of home_team, away_team, home_team_id,
    away_team_id, hidden_at
  on competition.fixture_schedules
  for each row execute function competition.reject_blocked_club_fixture();

-- ---------------------------------------------------------------------------
-- 2. the catalog: no new club, and no rename, with a blocked name
-- ---------------------------------------------------------------------------
create or replace function football_data.reject_blocked_club_team()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if football_data.is_blocked_club(new.name) then
    raise exception 'team "%" is a club that never appears', new.name
      using errcode = 'check_violation',
            constraint = 'teams_blocked_club';
  end if;
  return new;
end;
$$;

comment on function football_data.reject_blocked_club_team() is
  'Refuses a catalog club, or a rename, with a blocked name (0174).';

drop trigger if exists teams_blocked_club on football_data.teams;
create trigger teams_blocked_club
  before insert or update of name on football_data.teams
  for each row execute function football_data.reject_blocked_club_team();

insert into ops.applied_migrations (version)
values ('0174_blocked_clubs')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0174_blocked_clubs';                           -- 1 row
-- select count(*) from football_data.blocked_clubs;                 -- 23
-- select football_data.is_blocked_club('هابوعيل بئر السبع');        -- true
-- select football_data.is_blocked_club('Maccabi Tel-Aviv FC');       -- true
-- select football_data.is_blocked_club('هوفنهايم');                  -- false
-- select count(*) from competition.fixture_schedules s
--  where s.hidden_at is null and (football_data.is_blocked_club(s.home_team)
--     or football_data.is_blocked_club(s.away_team));               -- 0
