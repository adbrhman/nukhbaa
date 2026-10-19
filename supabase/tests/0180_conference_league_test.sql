-- End-to-end test for migration 0180: the Conference League is one
-- continental competition, listed by the query the admin picker reads
-- (PostgresLeagueRepository.listAll), with no logo_url so the bundled mark
-- shows. Rolled back at the end.
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

do $$
begin
  perform pg_temp.check(
    (select count(*) = 1 and bool_and(is_continental)
       from football_data.leagues
      where btrim(name) = 'دوري المؤتمر الأوروبي'),
    'the Conference League is one continental competition');
  perform pg_temp.check(
    exists (
      select 1
      from (
        select id, name, short_name, logo_url, is_continental
        from football_data.leagues
        order by name asc, id asc
      ) listed
      where listed.name = 'دوري المؤتمر الأوروبي'
        and listed.short_name = 'UECL'
        and listed.logo_url is null
        and listed.is_continental),
    'the admin league list offers it, short UECL, no logo_url');
  perform pg_temp.check(
    exists (select 1 from ops.applied_migrations
             where version = '0180_conference_league'),
    'the migration records itself');
end $$;

rollback;
