-- ============================================================
-- Nukhba — Seed: UEFA Champions League (دوري أبطال أوروبا)
-- Season 2026/2027 — league phase, CONFIRMED clubs only
-- Idempotent: safe to re-run. لا يكرّر ولا يكسر بيانات موجودة.
--
-- Verified 2026-09-04 against
-- en.wikipedia.org/wiki/2026–27_UEFA_Champions_League: 28 of the 36
-- league-phase clubs are confirmed as of this date; the remaining 8 slots
-- (5 Champions Path play-off winners, 2 League Path play-off winners, and
-- outstanding coefficient/performance spots) are still undecided pending
-- ongoing qualifying rounds. Only the 28 CONFIRMED clubs are seeded here —
-- the other 8 are deliberately NOT guessed; add them in a follow-up seed
-- once UEFA confirms the play-off results.
--
-- Several clubs already exist as teams from another league's seed (e.g.
-- Real Madrid via laliga_2026_27.sql, Arsenal via epl_2026_27.sql) — this
-- script reuses that SAME canonical team id via its "reuse" field instead
-- of creating a duplicate row, falling back to creating a fresh team only
-- if that other seed hasn't been run yet (order-independent).
--
-- crest_url intentionally NULL for every newly-created team — see
-- epl_2026_27.sql's header for the licensing rationale (Wikipedia club
-- crests are non-free/fair-use, not cleared for reuse here).
--
-- competition/season ids below target the row an admin already created
-- manually for this league (confirmed against the live DB 2026-09-04) —
-- NOT a freshly-invented id, to avoid creating a duplicate competition.
-- ============================================================

begin;

-- do nothing on conflict: this row was already created manually by an
-- admin (confirmed live 2026-09-04) — see epl_2026_27.sql's identical note.
insert into competition.competitions (id, name, format, visibility)
values (
  'b0a0c980-3394-4d47-ad6e-8df325e24e5f',
  'دوري أبطال أوروبا',
  'football_scoreline',
  'public'
)
on conflict (id) do nothing;

insert into competition.seasons (id, competition_id, label)
values (
  'a7c121af-7eb6-4b47-b858-384512273e98',
  'b0a0c980-3394-4d47-ad6e-8df325e24e5f',
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
    {"ext":"ucl:ars","ar":"أرسنال","short":"ARS","crest":null,"reuse":{"source":"epl","ext":"epl:ars"}},
    {"ext":"ucl:avl","ar":"أستون فيلا","short":"AVL","crest":null,"reuse":{"source":"epl","ext":"epl:avl"}},
    {"ext":"ucl:liv","ar":"ليفربول","short":"LIV","crest":null,"reuse":{"source":"epl","ext":"epl:liv"}},
    {"ext":"ucl:mci","ar":"مانشستر سيتي","short":"MCI","crest":null,"reuse":{"source":"epl","ext":"epl:mci"}},
    {"ext":"ucl:mun","ar":"مانشستر يونايتد","short":"MUN","crest":null,"reuse":{"source":"epl","ext":"epl:mun"}},
    {"ext":"ucl:atm","ar":"أتلتيكو مدريد","short":"ATM","crest":null,"reuse":{"source":"laliga","ext":"laliga:atm"}},
    {"ext":"ucl:bar","ar":"برشلونة","short":"BAR","crest":null,"reuse":{"source":"laliga","ext":"laliga:bar"}},
    {"ext":"ucl:bet","ar":"ريال بيتيس","short":"BET","crest":null,"reuse":{"source":"laliga","ext":"laliga:bet"}},
    {"ext":"ucl:rma","ar":"ريال مدريد","short":"RMA","crest":null,"reuse":{"source":"laliga","ext":"laliga:rma"}},
    {"ext":"ucl:vil","ar":"فياريال","short":"VIL","crest":null,"reuse":{"source":"laliga","ext":"laliga:vil"}},
    {"ext":"ucl:com","ar":"كومو","short":"COM","crest":null,"reuse":null},
    {"ext":"ucl:int","ar":"إنتر ميلان","short":"INT","crest":null,"reuse":null},
    {"ext":"ucl:nap","ar":"نابولي","short":"NAP","crest":null,"reuse":null},
    {"ext":"ucl:rom","ar":"روما","short":"ROM","crest":null,"reuse":null},
    {"ext":"ucl:bay","ar":"بايرن ميونخ","short":"BAY","crest":null,"reuse":null},
    {"ext":"ucl:bvb","ar":"بوروسيا دورتموند","short":"BVB","crest":null,"reuse":null},
    {"ext":"ucl:rbl","ar":"لايبزيغ","short":"RBL","crest":null,"reuse":null},
    {"ext":"ucl:vfb","ar":"شتوتغارت","short":"VFB","crest":null,"reuse":null},
    {"ext":"ucl:len","ar":"لانس","short":"LEN","crest":null,"reuse":null},
    {"ext":"ucl:psg","ar":"باريس سان جيرمان","short":"PSG","crest":null,"reuse":null},
    {"ext":"ucl:fey","ar":"فينورد","short":"FEY","crest":null,"reuse":null},
    {"ext":"ucl:psv","ar":"أيندهوفن","short":"PSV","crest":null,"reuse":null},
    {"ext":"ucl:por","ar":"بورتو","short":"POR","crest":null,"reuse":null},
    {"ext":"ucl:scp","ar":"سبورتينغ لشبونة","short":"SCP","crest":null,"reuse":null},
    {"ext":"ucl:clb","ar":"كلوب بروج","short":"CLB","crest":null,"reuse":null},
    {"ext":"ucl:sla","ar":"سلافيا براغ","short":"SLA","crest":null,"reuse":null},
    {"ext":"ucl:gal","ar":"غلطة سراي","short":"GAL","crest":null,"reuse":null},
    {"ext":"ucl:shk","ar":"شاختار دونيتسك","short":"SHK","crest":null,"reuse":null}
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
    values ('ucl', r.obj->>'ext', 'team', v_team_id)
    on conflict (external_source, external_id, canonical_table) do nothing;
  end loop;
end

$$;

commit;
