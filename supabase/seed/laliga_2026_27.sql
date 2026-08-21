-- ============================================================
-- Nukhba — Seed: La Liga (الدوري الإسباني) — Season 2026/2027
-- Idempotent: safe to re-run. لا يكرّر ولا يكسر بيانات موجودة.
-- ============================================================

begin;

insert into competition.competitions (id, name, format, visibility)
values (
  '11111111-1111-4111-8111-000000000001',
  'الدوري الإسباني',
  'football_scoreline',
  'public'
)
on conflict (id) do update
  set name = excluded.name,
      visibility = excluded.visibility,
      updated_at = now();

insert into competition.seasons (id, competition_id, label)
values (
  '22222222-2222-4222-8222-000000000001',
  '11111111-1111-4111-8111-000000000001',
  '2026/2027'
)
on conflict (id) do update
  set label = excluded.label,
      updated_at = now();

do $$
declare
  r record;
  v_team_id uuid;
  teams jsonb := '[
    {"ext":"laliga:ala","ar":"ديبورتيفو ألافيس","en":"Deportivo Alavés","short":"ALA","crest":"https://upload.wikimedia.org/wikipedia/en/f/f8/Deportivo_Alav%C3%A9s_logo_%282020%29.svg"},
    {"ext":"laliga:ath","ar":"أتلتيك بلباو","en":"Athletic Club","short":"ATH","crest":"https://upload.wikimedia.org/wikipedia/en/9/98/Club_Athletic_Bilbao_logo.svg"},
    {"ext":"laliga:atm","ar":"أتلتيكو مدريد","en":"Atlético de Madrid","short":"ATM","crest":"https://upload.wikimedia.org/wikipedia/en/f/f9/Logo_Atletico_Madrid_2017.svg"},
    {"ext":"laliga:bar","ar":"برشلونة","en":"FC Barcelona","short":"BAR","crest":"https://upload.wikimedia.org/wikipedia/en/4/47/FC_Barcelona_%28crest%29.svg"},
    {"ext":"laliga:cel","ar":"سيلتا فيغو","en":"Celta Vigo","short":"CEL","crest":"https://upload.wikimedia.org/wikipedia/en/1/12/RC_Celta_de_Vigo_logo.svg"},
    {"ext":"laliga:dep","ar":"ديبورتيفو لاكورونيا","en":"Deportivo La Coruña","short":"DEP","crest":"https://upload.wikimedia.org/wikipedia/en/c/c7/RC_Deportivo_La_Coru%C3%B1a_logo.svg"},
    {"ext":"laliga:elc","ar":"إلتشي","en":"Elche CF","short":"ELC","crest":"https://upload.wikimedia.org/wikipedia/en/6/6d/Elche_CF_logo.svg"},
    {"ext":"laliga:esp","ar":"إسبانيول","en":"RCD Espanyol","short":"ESP","crest":"https://upload.wikimedia.org/wikipedia/en/d/d4/RCD_Espanyol_logo.svg"},
    {"ext":"laliga:get","ar":"خيتافي","en":"Getafe CF","short":"GET","crest":"https://upload.wikimedia.org/wikipedia/en/4/46/Getafe_logo.svg"},
    {"ext":"laliga:lev","ar":"ليفانتي","en":"Levante UD","short":"LEV","crest":"https://upload.wikimedia.org/wikipedia/en/b/be/Levante_Uni%C3%B3n_Deportiva%2C_S.A.D._logo.svg"},
    {"ext":"laliga:mal","ar":"ملقا","en":"Málaga CF","short":"MAL","crest":"https://upload.wikimedia.org/wikipedia/en/4/4c/M%C3%A1lagaCF.svg"},
    {"ext":"laliga:osa","ar":"أوساسونا","en":"CA Osasuna","short":"OSA","crest":"https://upload.wikimedia.org/wikipedia/en/1/1a/CA_Osasuna_2024_crest.svg"},
    {"ext":"laliga:rac","ar":"راسينغ سانتاندير","en":"Racing Santander","short":"RAC","crest":"https://upload.wikimedia.org/wikipedia/en/7/7a/Racing_de_Santander_logo.svg"},
    {"ext":"laliga:ray","ar":"رايو فايكانو","en":"Rayo Vallecano","short":"RAY","crest":"https://upload.wikimedia.org/wikipedia/en/d/d0/Rayo_Vallecano_logo.svg"},
    {"ext":"laliga:bet","ar":"ريال بيتيس","en":"Real Betis","short":"BET","crest":"https://upload.wikimedia.org/wikipedia/en/1/13/Real_betis_logo.svg"},
    {"ext":"laliga:rma","ar":"ريال مدريد","en":"Real Madrid","short":"RMA","crest":"https://upload.wikimedia.org/wikipedia/en/5/56/Real_Madrid_CF.svg"},
    {"ext":"laliga:rso","ar":"ريال سوسيداد","en":"Real Sociedad","short":"RSO","crest":"https://upload.wikimedia.org/wikipedia/en/f/f1/Real_Sociedad_logo.svg"},
    {"ext":"laliga:sev","ar":"إشبيلية","en":"Sevilla FC","short":"SEV","crest":"https://upload.wikimedia.org/wikipedia/en/3/3b/Sevilla_FC_logo.svg"},
    {"ext":"laliga:val","ar":"فالنسيا","en":"Valencia CF","short":"VAL","crest":"https://upload.wikimedia.org/wikipedia/en/c/ce/Valenciacf.svg"},
    {"ext":"laliga:vil","ar":"فياريال","en":"Villarreal CF","short":"VIL","crest":"https://upload.wikimedia.org/wikipedia/en/7/70/Villarreal_CF_logo-en.svg"}
  ]'::jsonb;
begin
  for r in select * from jsonb_array_elements(teams) as t(obj)
  loop
    select canonical_id into v_team_id
    from football_data.external_identity_map
    where external_source = 'laliga'
      and external_id = (r.obj->>'ext')
      and canonical_table = 'team';

    if v_team_id is null then
      v_team_id := gen_random_uuid();
      insert into football_data.teams (id, name, short_name, crest_url)
      values (
        v_team_id,
        r.obj->>'ar',
        r.obj->>'short',
        r.obj->>'crest'
      );
      insert into football_data.external_identity_map
        (external_source, external_id, canonical_table, canonical_id)
      values ('laliga', r.obj->>'ext', 'team', v_team_id);
    else
      update football_data.teams
      set name = r.obj->>'ar',
          short_name = r.obj->>'short',
          crest_url = r.obj->>'crest',
          updated_at = now()
      where id = v_team_id;
    end if;
  end loop;
end

$$;

commit;
