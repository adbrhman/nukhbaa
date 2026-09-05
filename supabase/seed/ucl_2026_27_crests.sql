-- ============================================================
-- Nukhba — Seed: UEFA Champions League 2026/27 — remaining 8 clubs
-- + crest_url for all 36 confirmed league-phase clubs.
-- Idempotent: safe to re-run. لا يكرّر ولا يكسر بيانات موجودة.
--
-- Context: ucl_2026_27.sql seeded 28 of the 36 clubs earlier this
-- season (before every league-phase slot was confirmed). The remaining
-- 8 — AEK Athens, Bodø/Glimt, Fenerbahçe, LASK, LOSC Lille, Slovan
-- Bratislava, Sabah FK, and Viking FK — are identified here from the
-- official 2026/27 UCL crest set (docs/handoff/logos-2026-27/,
-- ucl-2026-27-teams.csv), matched by football knowledge against each
-- source filename, NOT the filename-derived guess in
-- LOGOS_MANIFEST.csv (that guess is explicitly unreliable — see its
-- own header). Cross-checked against every other league seed for
-- overlap — none of these 8 appear anywhere else.
--
-- crest_url is the FINAL public Storage URL for the `team-logos`
-- bucket (migration 0026), computed deterministically from the known
-- project ref, same as europa_2026_27_crests.sql:
--   https://thxzwzscwukifymjthnp.supabase.co/storage/v1/object/public/team-logos/<slug>.png
-- The actual 36 PNG uploads are a separate step — see
-- upload_ucl_2026_27_crests.sh. Running this seed first is safe
-- (a missing Storage object 404s; TeamLogo falls back to initials).
-- ============================================================

begin;

-- ---------------------------------------------------------------------
-- 1) The 8 newly-identified clubs — same create-or-reconcile pattern
--    every other league seed already uses (external_identity_map keyed
--    by 'ucl:<ext>').
-- ---------------------------------------------------------------------
do $$
declare
  r record;
  v_team_id uuid;
  teams jsonb := '[
    {"ext":"ucl:aek","ar":"أيك أثينا","short":"AEK"},
    {"ext":"ucl:bod","ar":"بودو/غليمت","short":"BOD"},
    {"ext":"ucl:fen","ar":"فنربخشة","short":"FEN"},
    {"ext":"ucl:las","ar":"لاسك لينز","short":"LAS"},
    {"ext":"ucl:los","ar":"ليل","short":"LIL"},
    {"ext":"ucl:slb","ar":"سلوفان براتيسلافا","short":"SLB"},
    {"ext":"ucl:sab","ar":"سابا","short":"SAB"},
    {"ext":"ucl:vik","ar":"فايكينغ","short":"VIK"}
  ]'::jsonb;
begin
  for r in select * from jsonb_array_elements(teams) as t(obj)
  loop
    select canonical_id into v_team_id
    from football_data.external_identity_map
    where external_source = 'ucl'
      and external_id = (r.obj->>'ext')
      and canonical_table = 'team';

    if v_team_id is not null then
      update football_data.teams
      set name = r.obj->>'ar',
          short_name = r.obj->>'short',
          updated_at = now()
      where id = v_team_id;
      continue;
    end if;

    v_team_id := gen_random_uuid();
    insert into football_data.teams (id, name, short_name)
    values (v_team_id, r.obj->>'ar', r.obj->>'short');

    insert into football_data.external_identity_map
      (external_source, external_id, canonical_table, canonical_id)
    values ('ucl', r.obj->>'ext', 'team', v_team_id)
    on conflict (external_source, external_id, canonical_table) do nothing;
  end loop;
end
$$;

-- ---------------------------------------------------------------------
-- 2) crest_url for all 36 clubs (the 28 from ucl_2026_27.sql + the 8
--    just above), keyed by the same 'ucl:<ext>' identity.
-- ---------------------------------------------------------------------
do $$
declare
  r record;
  v_base text := 'https://thxzwzscwukifymjthnp.supabase.co/storage/v1/object/public/team-logos/';
  crests jsonb := '[
    {"ext":"ucl:ars","slug":"arsenal"},
    {"ext":"ucl:avl","slug":"aston-villa"},
    {"ext":"ucl:liv","slug":"liverpool"},
    {"ext":"ucl:mci","slug":"manchester-city"},
    {"ext":"ucl:mun","slug":"manchester-united"},
    {"ext":"ucl:atm","slug":"atletico-madrid"},
    {"ext":"ucl:bar","slug":"barcelona"},
    {"ext":"ucl:bet","slug":"real-betis"},
    {"ext":"ucl:rma","slug":"real-madrid"},
    {"ext":"ucl:vil","slug":"villarreal"},
    {"ext":"ucl:com","slug":"como-1907"},
    {"ext":"ucl:int","slug":"inter-milan"},
    {"ext":"ucl:nap","slug":"napoli"},
    {"ext":"ucl:rom","slug":"roma"},
    {"ext":"ucl:bay","slug":"bayern-munchen"},
    {"ext":"ucl:bvb","slug":"borussia-dortmund"},
    {"ext":"ucl:rbl","slug":"rb-leipzig"},
    {"ext":"ucl:vfb","slug":"vfb-stuttgart"},
    {"ext":"ucl:len","slug":"lens"},
    {"ext":"ucl:psg","slug":"psg"},
    {"ext":"ucl:fey","slug":"feyenoord"},
    {"ext":"ucl:psv","slug":"psv-eindhoven"},
    {"ext":"ucl:por","slug":"porto"},
    {"ext":"ucl:scp","slug":"sporting-cp"},
    {"ext":"ucl:clb","slug":"club-brugge"},
    {"ext":"ucl:sla","slug":"slavia-praha"},
    {"ext":"ucl:gal","slug":"galatasaray"},
    {"ext":"ucl:shk","slug":"shakhtar-donetsk"},
    {"ext":"ucl:aek","slug":"aek-athens"},
    {"ext":"ucl:bod","slug":"bodo-glimt"},
    {"ext":"ucl:fen","slug":"fenerbahce"},
    {"ext":"ucl:las","slug":"lask"},
    {"ext":"ucl:los","slug":"lille"},
    {"ext":"ucl:slb","slug":"slovan-bratislava"},
    {"ext":"ucl:sab","slug":"sabah"},
    {"ext":"ucl:vik","slug":"viking-fk"}
  ]'::jsonb;
begin
  for r in select * from jsonb_array_elements(crests) as t(obj)
  loop
    update football_data.teams
    set crest_url = v_base || (r.obj->>'slug') || '.png',
        updated_at = now()
    where id = (
      select canonical_id
      from football_data.external_identity_map
      where external_source = 'ucl'
        and external_id = (r.obj->>'ext')
        and canonical_table = 'team'
    );
  end loop;
end
$$;

commit;
