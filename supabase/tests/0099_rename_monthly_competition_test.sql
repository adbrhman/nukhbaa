-- End-to-end test for migration 0099: the monthly competition's name, and
-- nothing else about it, changes. Rolled back at the end.
\set ON_ERROR_STOP on
begin;

create function pg_temp.check(ok boolean, label text) returns void
language plpgsql as $$
begin
  if ok is not true then
    raise exception 'FAILED: %', label;
  end if;
  raise notice 'ok - %', label;
end $$;

insert into competition.competitions (id, name, format, visibility) values
  ('c9900000-0000-4000-8000-000000000001', 'شهر 9', 'football_scoreline', 'public'),
  ('c9900000-0000-4000-8000-000000000002', 'Premier League', 'football_scoreline', 'public');
insert into competition.seasons (id, competition_id, label, start_at, end_at) values
  ('c9900000-0000-4000-8000-000000000010', 'c9900000-0000-4000-8000-000000000001',
   '09/2099', '2099-08-31 21:00Z', '2099-09-30 21:00Z'),
  ('c9900000-0000-4000-8000-000000000011', 'c9900000-0000-4000-8000-000000000001',
   '10/2099', '2099-09-30 21:00Z', '2099-10-31 21:00Z');

do $$
begin
  perform pg_temp.check(
    competition.rename_competition('شهر 9', 'المسابقة الشهرية') = 1,
    'the one competition so named is renamed');
  perform pg_temp.check(
    (select name from competition.competitions
      where id = 'c9900000-0000-4000-8000-000000000001') = 'المسابقة الشهرية',
    'it carries the new name');
  perform pg_temp.check(
    (select name from competition.competitions
      where id = 'c9900000-0000-4000-8000-000000000002') = 'Premier League',
    'another competition keeps its name');
  perform pg_temp.check(
    (select count(*) from competition.seasons
      where competition_id = 'c9900000-0000-4000-8000-000000000001') = 2,
    'its months stay under it, untouched');
  perform pg_temp.check(
    competition.rename_competition('شهر 9', 'المسابقة الشهرية') = 0,
    'a second run finds nothing and changes nothing');
end $$;

insert into competition.competitions (id, name, format, visibility) values
  ('c9900000-0000-4000-8000-000000000003', 'Twin', 'football_scoreline', 'public'),
  ('c9900000-0000-4000-8000-000000000004', 'Twin', 'football_scoreline', 'public');

do $$
declare
  v_refused boolean := false;
begin
  begin
    perform competition.rename_competition('Twin', 'X');
  exception when others then
    v_refused := true;
  end;
  perform pg_temp.check(v_refused, 'two competitions with one name stop the rename');
  perform pg_temp.check(
    (select count(*) from competition.competitions where name = 'Twin') = 2,
    'and neither is renamed');
end $$;

do $$
begin
  perform pg_temp.check(
    not has_function_privilege('anon',
      'competition.rename_competition(text, text)', 'execute')
    and not has_function_privilege('authenticated',
      'competition.rename_competition(text, text)', 'execute'),
    'no client may call it');
end $$;

rollback;
