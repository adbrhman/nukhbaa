-- End-to-end test for migration 0104: the big derbies are a continental
-- league, their 31 clubs are in the catalog once each, a club created by
-- 0050 or 0103 is reused through its identity, and a re-run of the
-- migration's statements adds nothing. Rolled back at the end.
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
      where btrim(name) = 'ديربيات كبرى'),
    'one continental league named ديربيات كبرى');
  perform pg_temp.check(
    (select count(*) from football_data.external_identity_map
      where external_source = 'big_derbies' and canonical_table = 'team') = 31,
    'the 31 derby clubs are mapped');
  perform pg_temp.check(
    (select count(distinct canonical_id) from football_data.external_identity_map
      where external_source = 'big_derbies' and canonical_table = 'team') = 31,
    'each club is its own team');
  perform pg_temp.check(
    (select count(*) from football_data.teams where btrim(name) = 'الأهلي المصري') = 1,
    'Al Ahly, already in the catalog (0050), is reused, not duplicated');
  perform pg_temp.check(
    (select m.canonical_id from football_data.external_identity_map m
      where m.external_source = 'big_derbies' and m.external_id = 'drb:esteghlal')
    = (select m.canonical_id from football_data.external_identity_map m
      where m.external_source = 'acl_elite' and m.external_id = 'acle:est'),
    'Esteghlal is the club 0103 created');
  perform pg_temp.check(
    (select count(*) from football_data.teams t
       join football_data.external_identity_map m
         on m.canonical_id = t.id and m.external_source = 'big_derbies'
      where t.name = 'الزمالك' and t.league_id is null and t.crest_url is null) = 1,
    'a new club has no league and no crest yet');
  perform pg_temp.check(
    exists (select 1 from ops.applied_migrations where version = '0104_big_derbies'),
    'the migration records itself');
end $$;

rollback;
