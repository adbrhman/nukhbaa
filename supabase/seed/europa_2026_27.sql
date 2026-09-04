-- ============================================================
-- Nukhba — Seed: UEFA Europa League (الدوري الأوروبي)
-- Season 2026/2027 — league phase, CONFIRMED clubs only
-- Idempotent: safe to re-run. لا يكرّر ولا يكسر بيانات موجودة.
--
-- Verified 2026-09-04 against
-- en.wikipedia.org/wiki/2026–27_UEFA_Europa_League: 24 of the 36
-- league-phase clubs are confirmed as of this date; the remaining slots
-- (winners of the play-off round and other pending qualifying rounds) are
-- still undecided. Only the 24 CONFIRMED clubs are seeded here — the rest
-- are deliberately NOT guessed; add them in a follow-up seed once UEFA
-- confirms the play-off results. Cross-checked against the already-shipped
-- apps/mobile/.../team_logo_assets.dart "الدوري الأوروبي" slug list (same
-- 24 clubs, prior season — same underlying pot of domestic finishers).
--
-- Nine clubs already exist as teams from epl_2026_27.sql,
-- seriea_2026_27.sql, laliga_2026_27.sql, or bundesliga_2026_27.sql —
-- reused via "reuse", falling back to a fresh team if that seed hasn't
-- run yet (order-independent, same pattern as ucl_2026_27.sql).
--
-- crest_url intentionally NULL — see epl_2026_27.sql's header for the
-- licensing rationale.
--
-- competition/season ids below target the row an admin already created
-- manually for this league (confirmed against the live DB 2026-09-04) —
-- NOT a freshly-invented id, and the competition insert is "do nothing"
-- on conflict, same pattern as epl_2026_27.sql.
-- ============================================================

begin;

insert into competition.competitions (id, name, format, visibility)
values (
  '2a08e85b-60f4-4705-94c1-87d37ade016a',
  'الدوري الأوروبي',
  'football_scoreline',
  'public'
)
on conflict (id) do nothing;

insert into competition.seasons (id, competition_id, label)
values (
  'cb42ee45-5abe-4f52-8551-be5a403b79a8',
  '2a08e85b-60f4-4705-94c1-87d37ade016a',
  '2026/27'
)
on conflict (id) do update
  set label = excluded.label,
      updated_at = now();

do $$
declare
  r record;
  v_team_id uuid;
  v_reuse_source text;
  v_reuse_ext text;
  teams jsonb := '[
    {"ext":"europa:cry","ar":"كريستال بالاس","short":"CRY","crest":null,"reuse":{"source":"epl","ext":"epl:cry"}},
    {"ext":"europa:bou","ar":"بورنموث","short":"BOU","crest":null,"reuse":{"source":"epl","ext":"epl:bou"}},
    {"ext":"europa:sun","ar":"سندرلاند","short":"SUN","crest":null,"reuse":{"source":"epl","ext":"epl:sun"}},
    {"ext":"europa:mil","ar":"ميلان","short":"MIL","crest":null,"reuse":{"source":"seriea","ext":"seriea:mil"}},
    {"ext":"europa:juv","ar":"يوفنتوس","short":"JUV","crest":null,"reuse":{"source":"seriea","ext":"seriea:juv"}},
    {"ext":"europa:rso","ar":"ريال سوسيداد","short":"RSO","crest":null,"reuse":{"source":"laliga","ext":"laliga:rso"}},
    {"ext":"europa:cel","ar":"سيلتا فيغو","short":"CEL","crest":null,"reuse":{"source":"laliga","ext":"laliga:cel"}},
    {"ext":"europa:tsg","ar":"هوفنهايم","short":"TSG","crest":null,"reuse":{"source":"bundesliga","ext":"bundesliga:tsg"}},
    {"ext":"europa:b04","ar":"باير ليفركوزن","short":"B04","crest":null,"reuse":{"source":"bundesliga","ext":"bundesliga:b04"}},
    {"ext":"europa:mar","ar":"مارسيليا","short":"MAR","crest":null,"reuse":null},
    {"ext":"europa:ren","ar":"رين","short":"REN","crest":null,"reuse":null},
    {"ext":"europa:aza","ar":"ألكمار","short":"AZA","crest":null,"reuse":null},
    {"ext":"europa:tor","ar":"توريينسي","short":"TOR","crest":null,"reuse":null},
    {"ext":"europa:cel2","ar":"سلتيك","short":"CEL2","crest":null,"reuse":null},
    {"ext":"europa:hap","ar":"هابوعيل بئر السبع","short":"HAP","crest":null,"reuse":null},
    {"ext":"europa:dzg","ar":"دينامو زغرب","short":"DZG","crest":null,"reuse":null},
    {"ext":"europa:cje","ar":"تسيليه","short":"CJE","crest":null,"reuse":null},
    {"ext":"europa:lev","ar":"ليفسكي صوفيا","short":"LEV","crest":null,"reuse":null},
    {"ext":"europa:lyo","ar":"ليون","short":"LYO","crest":null,"reuse":null},
    {"ext":"europa:nec","ar":"نايميخن","short":"NEC","crest":null,"reuse":null},
    {"ext":"europa:usg","ar":"يونيون سان جيلواز","short":"USG","crest":null,"reuse":null},
    {"ext":"europa:spr","ar":"سبارتا براغ","short":"SPR","crest":null,"reuse":null},
    {"ext":"europa:oly","ar":"أولمبياكوس","short":"OLY","crest":null,"reuse":null},
    {"ext":"europa:stg","ar":"شتورم غراتس","short":"STG","crest":null,"reuse":null}
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

    v_reuse_source := r.obj#>>'{reuse,source}';
    v_reuse_ext := r.obj#>>'{reuse,ext}';
    v_team_id := null;
    if v_reuse_source is not null then
      select canonical_id into v_team_id
      from football_data.external_identity_map
      where external_source = v_reuse_source
        and external_id = v_reuse_ext
        and canonical_table = 'team';
    end if;

    if v_team_id is null then
      v_team_id := gen_random_uuid();
      insert into football_data.teams (id, name, short_name, crest_url)
      values (
        v_team_id,
        r.obj->>'ar',
        r.obj->>'short',
        r.obj->>'crest'
      );
    end if;

    insert into football_data.external_identity_map
      (external_source, external_id, canonical_table, canonical_id)
    values ('europa', r.obj->>'ext', 'team', v_team_id)
    on conflict (external_source, external_id, canonical_table) do nothing;
  end loop;
end

$$;

commit;
