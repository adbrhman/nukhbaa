-- ============================================================
-- Nukhba — Seed: Ligue 1 (الدوري الفرنسي) — season 2026/27
-- NOT a migration: production data, applied by hand like the other seeds.
--
-- Adds the league row, the eighteen clubs, and their football-data.org
-- identities, so `FL1` in apps/server/lib/provider_sync/phase_one_rules.dart
-- stops reporting `league not in catalog` / `unmapped team`.
--
-- Team ids are the provider's own /v4/competitions/FL1/teams list, read
-- 2026-09-18. Six of the eighteen already exist in the catalog from
-- ucl_2026_27.sql / europa_2026_27.sql (باريس سان جيرمان، مارسيليا، ليون،
-- ليل، رين، لانس) and are reused by exact name — never duplicated.
--
-- crest_url stays NULL, as for every other seeded league: the card falls
-- back to the name (migration 0027's contract). Client logos already ship
-- for those same six.
--
-- Additive and idempotent. Expected result:
--   select count(*) from football_data.external_identity_map
--    where external_source = 'football-data'
--      and canonical_table = 'team';   -- 96 -> 114
-- ============================================================

begin;

insert into football_data.leagues (name, short_name, is_continental)
select 'الدوري الفرنسي', 'FL1', false
where not exists (
  select 1
  from football_data.leagues l
  where btrim(l.name) = 'الدوري الفرنسي'
);

do $$
declare
  r record;
  v_league_id uuid;
  v_team_id uuid;
  teams jsonb := '[
    {"fd":"524","ar":"باريس سان جيرمان","tla":"PSG"},
    {"fd":"516","ar":"مارسيليا","tla":"MAR"},
    {"fd":"523","ar":"ليون","tla":"LYO"},
    {"fd":"521","ar":"ليل","tla":"LIL"},
    {"fd":"529","ar":"رين","tla":"REN"},
    {"fd":"546","ar":"لانس","tla":"RCL"},
    {"fd":"548","ar":"موناكو","tla":"ASM"},
    {"fd":"522","ar":"نيس","tla":"NIC"},
    {"fd":"576","ar":"ستراسبورغ","tla":"RCS"},
    {"fd":"512","ar":"بريست","tla":"BRE"},
    {"fd":"511","ar":"تولوز","tla":"TOU"},
    {"fd":"519","ar":"أوكسير","tla":"AJA"},
    {"fd":"525","ar":"لوريان","tla":"FCL"},
    {"fd":"532","ar":"أنجيه","tla":"ANG"},
    {"fd":"533","ar":"لوهافر","tla":"HAC"},
    {"fd":"531","ar":"تروا","tla":"ETR"},
    {"fd":"535","ar":"لومان","tla":"LMF"},
    {"fd":"1045","ar":"باريس إف سي","tla":"PFC"}
  ]'::jsonb;
begin
  select id into v_league_id
  from football_data.leagues
  where btrim(name) = 'الدوري الفرنسي';

  if v_league_id is null then
    raise exception 'league row missing after insert';
  end if;

  for r in select value as obj from jsonb_array_elements(teams) loop
    v_team_id := null;

    -- Already mapped from a previous run of this seed.
    select canonical_id into v_team_id
    from football_data.external_identity_map
    where external_source = 'football-data'
      and external_id = r.obj->>'fd'
      and canonical_table = 'team';

    -- Otherwise reuse the catalog team of the same Arabic name, so a club
    -- seeded for a continental competition is not duplicated.
    if v_team_id is null then
      select id into v_team_id
      from football_data.teams
      where btrim(name) = r.obj->>'ar'
      order by created_at
      limit 1;
    end if;

    if v_team_id is null then
      v_team_id := gen_random_uuid();
      insert into football_data.teams (id, name, short_name, crest_url, league_id)
      values (v_team_id, r.obj->>'ar', r.obj->>'tla', null, v_league_id);
    else
      -- A club belongs to its domestic league; a continental tag is not a
      -- club list (migration 0038). Never overwrite another domestic league.
      update football_data.teams t
      set league_id = v_league_id
      where t.id = v_team_id
        and (
          t.league_id is null
          or exists (
            select 1
            from football_data.leagues l
            where l.id = t.league_id
              and l.is_continental
          )
        );
    end if;

    insert into football_data.external_identity_map
      (external_source, external_id, canonical_table, canonical_id)
    values ('football-data', r.obj->>'fd', 'team', v_team_id)
    on conflict (external_source, external_id, canonical_table) do nothing;
  end loop;
end
$$;

commit;

-- Verification:
-- select t.name, t.short_name, m.external_id
--   from football_data.teams t
--   join football_data.leagues l on l.id = t.league_id
--   join football_data.external_identity_map m
--     on m.canonical_id = t.id
--    and m.external_source = 'football-data'
--    and m.canonical_table = 'team'
--  where btrim(l.name) = 'الدوري الفرنسي'
--  order by t.name;
