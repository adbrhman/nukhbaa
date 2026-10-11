-- End-to-end test for migration 0105: three super cups and the CAF
-- Champions League are continental leagues, once each, beside the Spanish
-- super cup of 0045; the five CAF clubs are in the catalog once each with
-- no crest yet. Rolled back at the end.
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
    (select count(*) = 4 and bool_and(is_continental)
       from football_data.leagues
      where btrim(name) in ('كأس السوبر الإيطالي', 'كأس السوبر الفرنسي',
                           'كأس السوبر الألماني', 'دوري أبطال إفريقيا')),
    'four continental competitions, once each');
  perform pg_temp.check(
    (select count(*) from football_data.leagues
      where btrim(name) = 'كأس السوبر الإسباني') = 1,
    'the Spanish super cup of 0045 stays one competition');
  perform pg_temp.check(
    (select count(*) from football_data.external_identity_map
      where external_source = 'caf_cl' and canonical_table = 'team') = 5,
    'the five CAF contenders are mapped');
  perform pg_temp.check(
    (select count(distinct canonical_id) from football_data.external_identity_map
      where external_source = 'caf_cl' and canonical_table = 'team') = 5,
    'each club is its own team');
  perform pg_temp.check(
    (select count(*) from football_data.teams t
       join football_data.external_identity_map m
         on m.canonical_id = t.id and m.external_source = 'caf_cl'
      where t.name = 'بيراميدز' and t.league_id is null and t.crest_url is null) = 1,
    'a new club has no league and no crest yet');
  perform pg_temp.check(
    exists (select 1 from ops.applied_migrations where version = '0105_super_cups_caf'),
    'the migration records itself');
end $$;

rollback;
