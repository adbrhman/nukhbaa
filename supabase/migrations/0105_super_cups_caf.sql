-- ============================================================================
-- Migration 0105: the Italian, French and German super cups and the CAF
-- Champions League
--
-- ADDITIVE ONLY. Four new rows in football_data.leagues and five clubs. No
-- match, prediction, point, ledger or fixture row is touched.
--
-- ## The competitions
--   كأس السوبر الإيطالي   (Supercoppa Italiana)
--   كأس السوبر الفرنسي    (Trophée des Champions)
--   كأس السوبر الألماني   (DFL-Supercup)
--   دوري أبطال إفريقيا    (CAF Champions League)
-- كأس السوبر الإسباني is already in the catalog (0045); each super cup
-- stays its own competition, as that one is (decided with the owner
-- 2026-10-12). All four are is_continental = true, as 0038 and 0045 set for
-- a competition that draws its clubs from other leagues: the admin picker
-- offers the whole catalog, no club is tagged to them, and fixtures are
-- added by an admin, not by the provider sync.
--
-- ## The clubs
-- The super cups need none: their clubs are in the catalog already. For the
-- CAF Champions League, whose group stage is not drawn yet (second round
-- 13-25 October 2026), the big contenders the catalog lacks are created:
-- بيراميدز، نهضة بركان، أورلاندو بايرتس، يانغ أفريكانز، سيمبا. Al Ahly,
-- Zamalek, Esperance, Wydad, Raja, Mamelodi Sundowns, Al-Hilal Omdurman
-- and MC Alger are there already (0050, 0104). A club already in the
-- catalog under the same Arabic name is reused; the others get league_id
-- NULL and crest NULL. Each is recorded in external_identity_map under the
-- source 'caf_cl', so a re-run creates nothing twice.
--
-- Forward-only, guarded. Safe to re-run.
-- ============================================================================

begin;

insert into football_data.leagues (name, is_continental)
select v.name, true
from (values
  ('كأس السوبر الإيطالي'),
  ('كأس السوبر الفرنسي'),
  ('كأس السوبر الألماني'),
  ('دوري أبطال إفريقيا')
) as v (name)
where not exists (
  select 1
  from football_data.leagues l
  where btrim(l.name) = v.name
);

do $$
declare
  r record;
  v_team_id uuid;
  v_existing_name text;
  teams jsonb := '[
    {"ext":"caf:pyramids","ar":"بيراميدز","short":"PYR"},
    {"ext":"caf:rs-berkane","ar":"نهضة بركان","short":"RSB"},
    {"ext":"caf:orlando-pirates","ar":"أورلاندو بايرتس","short":"ORL"},
    {"ext":"caf:young-africans","ar":"يانغ أفريكانز","short":"YAN"},
    {"ext":"caf:simba","ar":"سيمبا","short":"SIM"}
  ]'::jsonb;
begin
  for r in select * from jsonb_array_elements(teams) as t(obj)
  loop
    select canonical_id into v_team_id
    from football_data.external_identity_map
    where external_source = 'caf_cl'
      and external_id = (r.obj->>'ext')
      and canonical_table = 'team';

    if v_team_id is not null then
      select name into v_existing_name
      from football_data.teams
      where id = v_team_id;
      if lower(btrim(v_existing_name)) is distinct from lower(btrim(r.obj->>'ar')) then
        raise exception 'CAF identity % already points to team % named %, expected %',
          r.obj->>'ext', v_team_id, v_existing_name, r.obj->>'ar';
      end if;
      continue;
    end if;

    select id into v_team_id
    from football_data.teams
    where lower(btrim(name)) = lower(btrim(r.obj->>'ar'))
    order by created_at, id
    limit 1;

    if v_team_id is null then
      insert into football_data.teams (name, short_name, crest_url)
      values (r.obj->>'ar', r.obj->>'short', null)
      returning id into v_team_id;
    end if;

    insert into football_data.external_identity_map
      (external_source, external_id, canonical_table, canonical_id)
    values ('caf_cl', r.obj->>'ext', 'team', v_team_id);
  end loop;
end
$$;

insert into ops.applied_migrations (version)
values ('0105_super_cups_caf')
on conflict (version) do nothing;

commit;

-- Verification (expects 4 continental leagues and 5 clubs):
-- select name, is_continental from football_data.leagues
--  where name in ('كأس السوبر الإيطالي','كأس السوبر الفرنسي','كأس السوبر الألماني','دوري أبطال إفريقيا');
-- select count(*) from football_data.external_identity_map where external_source = 'caf_cl';
