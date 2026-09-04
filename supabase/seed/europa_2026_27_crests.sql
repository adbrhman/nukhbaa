-- ============================================================
-- Nukhba — Seed: UEFA Europa League 2026/27 — remaining 12 clubs
-- + crest_url for all 36 confirmed league-phase clubs.
-- Idempotent: safe to re-run. لا يكرّر ولا يكسر بيانات موجودة.
--
-- Context: europa_2026_27.sql seeded the 24 clubs confirmed as of
-- 2026-09-04 (see its own header — the play-off/qualifying slots were
-- still pending, and Torreense was already one of those 24). The
-- remaining 12, now confirmed and verified against the official UEFA
-- list (europa-league-2026-27-teams.csv), are Anderlecht, Benfica,
-- Beşiktaş, Ferencváros, Lech Poznań, Lillestrøm, OFI Crete, Viktoria
-- Plzeň, Ararat-Armenia, Jagiellonia Białystok, Omonia Nicosia, and FC
-- Red Bull Salzburg. Cross-checked against ucl_2026_27.sql and the other
-- five league seeds for overlap — none of these 12 appear anywhere
-- else, so none reuse an existing row.
--
-- crest_url below is the FINAL public Storage URL for the `team-logos`
-- bucket (migration 0026) — computed deterministically from the known
-- project ref, not looked up after the fact:
--   https://thxzwzscwukifymjthnp.supabase.co/storage/v1/object/public/team-logos/<slug>.png
-- The actual 36 PNG uploads (800x800, transparent background, named
-- <slug>.png to match) are a separate step outside SQL's reach — see the
-- upload script this seed ships alongside. Running THIS seed before the
-- uploads happen is safe (Storage 404s on a missing object; the app
-- already falls back to initials via TeamLogo when a crest fails to
-- load) but the crests obviously won't render until the upload runs.
-- ============================================================

begin;

-- ---------------------------------------------------------------------
-- 1) The 12 newly-confirmed clubs — same create-or-reconcile pattern as
--    europa_2026_27.sql (external_identity_map keyed by 'europa:<ext>'),
--    no "reuse" needed since none of them already exist under another
--    league's seed.
-- ---------------------------------------------------------------------
do $$
declare
  r record;
  v_team_id uuid;
  teams jsonb := '[
    {"ext":"europa:and","ar":"أندرلخت","short":"AND"},
    {"ext":"europa:ben","ar":"بنفيكا","short":"BEN"},
    {"ext":"europa:bjk","ar":"بشيكتاش","short":"BJK"},
    {"ext":"europa:ftc","ar":"فرنكفاروش","short":"FTC"},
    {"ext":"europa:lec","ar":"ليخ بوزنان","short":"LEC"},
    {"ext":"europa:lsk","ar":"ليليستروم","short":"LSK"},
    {"ext":"europa:ofi","ar":"أوفي كريت","short":"OFI"},
    {"ext":"europa:vpl","ar":"فيكتوريا بلزن","short":"VPL"},
    {"ext":"europa:ara","ar":"أرارات أرمينيا","short":"ARA"},
    {"ext":"europa:jag","ar":"ياجيلونيا بياليستوك","short":"JAG"},
    {"ext":"europa:omo","ar":"أومونيا نيقوسيا","short":"OMO"},
    {"ext":"europa:rbs","ar":"سالزبورغ","short":"RBS"}
  ]'::jsonb;
begin
  for r in select * from jsonb_array_elements(teams) as t(obj)
  loop
    select canonical_id into v_team_id
    from football_data.external_identity_map
    where external_source = 'europa'
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
    values ('europa', r.obj->>'ext', 'team', v_team_id)
    on conflict (external_source, external_id, canonical_table) do nothing;
  end loop;
end
$$;

-- ---------------------------------------------------------------------
-- 2) crest_url for all 36 clubs (the 24 from europa_2026_27.sql +
--    the 12 just above), keyed by the same 'europa:<ext>' identity —
--    exact deterministic match, not a fuzzy name/slug lookup, since
--    every one of these teams already has a precise ext key.
-- ---------------------------------------------------------------------
do $$
declare
  r record;
  v_base text := 'https://thxzwzscwukifymjthnp.supabase.co/storage/v1/object/public/team-logos/';
  crests jsonb := '[
    {"ext":"europa:cry","slug":"crystal-palace"},
    {"ext":"europa:bou","slug":"bournemouth"},
    {"ext":"europa:sun","slug":"sunderland"},
    {"ext":"europa:mil","slug":"milan"},
    {"ext":"europa:juv","slug":"juventus"},
    {"ext":"europa:rso","slug":"real-sociedad"},
    {"ext":"europa:cel","slug":"celta-vigo"},
    {"ext":"europa:tsg","slug":"hoffenheim"},
    {"ext":"europa:b04","slug":"leverkusen"},
    {"ext":"europa:mar","slug":"marseille"},
    {"ext":"europa:ren","slug":"rennes"},
    {"ext":"europa:aza","slug":"az-alkmaar"},
    {"ext":"europa:tor","slug":"torreense"},
    {"ext":"europa:cel2","slug":"celtic"},
    {"ext":"europa:hap","slug":"hapoel-beer-sheva"},
    {"ext":"europa:dzg","slug":"dinamo-zagreb"},
    {"ext":"europa:cje","slug":"celje"},
    {"ext":"europa:lev","slug":"levski-sofia"},
    {"ext":"europa:lyo","slug":"lyon"},
    {"ext":"europa:nec","slug":"nec-nijmegen"},
    {"ext":"europa:usg","slug":"union-saint-gilloise"},
    {"ext":"europa:spr","slug":"sparta-praha"},
    {"ext":"europa:oly","slug":"olympiacos"},
    {"ext":"europa:stg","slug":"sturm-graz"},
    {"ext":"europa:and","slug":"anderlecht"},
    {"ext":"europa:ben","slug":"benfica"},
    {"ext":"europa:bjk","slug":"besiktas"},
    {"ext":"europa:ftc","slug":"ferencvaros"},
    {"ext":"europa:lec","slug":"lech-poznan"},
    {"ext":"europa:lsk","slug":"lillestrom"},
    {"ext":"europa:ofi","slug":"ofi-crete"},
    {"ext":"europa:vpl","slug":"viktoria-plzen"},
    {"ext":"europa:ara","slug":"ararat-armenia"},
    {"ext":"europa:jag","slug":"jagiellonia-bialystok"},
    {"ext":"europa:omo","slug":"omonia"},
    {"ext":"europa:rbs","slug":"salzburg"}
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
      where external_source = 'europa'
        and external_id = (r.obj->>'ext')
        and canonical_table = 'team'
    );
  end loop;
end
$$;

commit;
