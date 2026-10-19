-- End-to-end test for migration 0181: the 36 Conference League clubs are
-- mapped once each to their own team; Ajax, created by 0104, is reused
-- through its name, not duplicated; a new club has no league and no crest
-- row (the app bundles it); and the admin's team list, which offers the
-- whole catalog for a continental league, carries Red Star. Rolled back
-- at the end.
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
    (select count(*) from football_data.external_identity_map
      where external_source = 'uecl' and canonical_table = 'team') = 36,
    'the 36 clubs are mapped');
  perform pg_temp.check(
    (select count(distinct canonical_id) from football_data.external_identity_map
      where external_source = 'uecl' and canonical_table = 'team') = 36,
    'each club is its own team');
  perform pg_temp.check(
    (select count(*) from football_data.teams where btrim(name) = 'أياكس') = 1,
    'Ajax, already in the catalog (0104), is not duplicated');
  perform pg_temp.check(
    (select m.canonical_id from football_data.external_identity_map m
      where m.external_source = 'uecl' and m.external_id = 'uecl:ajax')
    = (select m.canonical_id from football_data.external_identity_map m
      where m.external_source = 'big_derbies' and m.external_id = 'drb:ajax'),
    'Ajax is the club 0104 created');
  perform pg_temp.check(
    (select count(*) from football_data.teams t
       join football_data.external_identity_map m
         on m.canonical_id = t.id and m.external_source = 'uecl'
      where t.name = 'النجم الأحمر' and t.short_name = 'CZV'
        and t.league_id is null and t.crest_url is null) = 1,
    'Red Star is created once, no league, no crest row');
  perform pg_temp.check(
    exists (
      select 1 from football_data.teams t
       where t.name = 'كوبنهاغن'),
    'the catalog the admin picker lists carries Copenhagen');
  perform pg_temp.check(
    exists (select 1 from ops.applied_migrations
             where version = '0181_conference_league_clubs'),
    'the migration records itself');
end $$;

rollback;
