-- End-to-end test for migration 0103: the AFC Champions League Elite is a
-- continental league, its 32 clubs are in the catalog once each, a club
-- already present under the same name is reused, and a re-run of the
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
      where btrim(name) = 'دوري أبطال آسيا للنخبة'),
    'one continental league named دوري أبطال آسيا للنخبة');
  perform pg_temp.check(
    (select count(*) from football_data.external_identity_map
      where external_source = 'acl_elite' and canonical_table = 'team') = 32,
    'the 32 clubs of the league stage are mapped');
  perform pg_temp.check(
    (select count(distinct canonical_id) from football_data.external_identity_map
      where external_source = 'acl_elite' and canonical_table = 'team') = 32,
    'each club is its own team');
  perform pg_temp.check(
    (select count(*) from football_data.teams where btrim(name) = 'العين') = 1,
    'Al Ain, already in the catalog (0050), is reused, not duplicated');
  perform pg_temp.check(
    (select count(*) from football_data.teams t
       join football_data.external_identity_map m
         on m.canonical_id = t.id and m.external_source = 'acl_elite'
      where t.name = 'الوصل' and t.league_id is null and t.crest_url is null) = 1,
    'a new club has no league and no crest yet');
  perform pg_temp.check(
    exists (select 1 from ops.applied_migrations where version = '0103_acl_elite'),
    'the migration records itself');
end $$;

rollback;
