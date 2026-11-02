-- End-to-end test for migration 0194: a write from any session but the
-- server's moves the cache epoch; the server's own writes do not; the
-- reader's query (PostgresCacheEpochReader) answers it. Rolled back.
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

create temp table seen (epoch bigint);
insert into seen select epoch from ops.cache_epoch where id = 1;

-- The server's session: its own writes leave the epoch alone. Statement
-- triggers fire on a statement touching no row, so no row is needed.
set local application_name = 'nukhbaa-server';
update football_data.leagues set name = name where false;
update competition.fixture_schedules set home_team = home_team where false;
select pg_temp.check(
  (select epoch from ops.cache_epoch) = (select epoch from seen),
  'a write of the server leaves the epoch');

-- The SQL Editor's session (any other name): the epoch moves, once per
-- statement, and says which table and which session.
set local application_name = 'supabase/dashboard';
update competition.fixture_schedules set home_team = home_team where false;
select pg_temp.check(
  (select epoch from ops.cache_epoch) = (select epoch from seen) + 1,
  'a write from the SQL Editor moves the epoch by one');
select pg_temp.check(
  (select source from ops.cache_epoch)
    = 'competition.fixture_schedules by supabase/dashboard',
  'the epoch names the table and the session');

update identity.users set display_name = display_name where false;
select pg_temp.check(
  (select epoch from ops.cache_epoch) = (select epoch from seen) + 2,
  'a statement on identity.users moves it too');

-- No name at all is not the server either.
set local application_name = '';
delete from football_data.leagues where false;
select pg_temp.check(
  (select epoch from ops.cache_epoch) = (select epoch from seen) + 3,
  'a session without a name moves it');

-- PostgresCacheEpochReader's query.
select pg_temp.check(
  (select count(*) = 1 from (
     SELECT epoch, source, changed_at FROM ops.cache_epoch WHERE id = 1) r),
  'the reader finds its one row');

select pg_temp.check(
  exists (select 1 from ops.applied_migrations
           where version = '0194_cache_epoch'),
  '0194 recorded in ops.applied_migrations');

rollback;
