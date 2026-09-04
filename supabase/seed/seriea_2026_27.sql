-- ============================================================
-- Nukhba — Seed: Serie A (الدوري الإيطالي)
-- Season 2026/2027
-- Idempotent: safe to re-run. لا يكرّر ولا يكسر بيانات موجودة.
--
-- Roster verified 2026-09-04 against
-- en.wikipedia.org/wiki/2026–27_Serie_A (participating-clubs table) and
-- cross-checked against en.wikipedia.org/wiki/Serie_A's 2025-26 table:
-- the 2026-27 list is exactly the 2025-26 list with Cremonese/Hellas
-- Verona/Pisa (relegated) swapped for Frosinone/Monza/Venezia (promoted)
-- — internally consistent across both fetches.
--
-- Four clubs already exist as teams from ucl_2026_27.sql — reused via
-- "reuse", falling back to a fresh team if that seed hasn't run yet
-- (order-independent, same pattern as ucl_2026_27.sql).
--
-- crest_url intentionally NULL — see epl_2026_27.sql's header for the
-- licensing rationale.
-- ============================================================

begin;

insert into competition.competitions (id, name, format, visibility)
values (
  '11111111-1111-4111-8111-000000000006',
  'الدوري الإيطالي',
  'football_scoreline',
  'public'
)
on conflict (id) do update
  set name = excluded.name,
      visibility = excluded.visibility,
      updated_at = now();

insert into competition.seasons (id, competition_id, label)
values (
  '22222222-2222-4222-8222-000000000006',
  '11111111-1111-4111-8111-000000000006',
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
    {"ext":"seriea:ata","ar":"أتالانتا","short":"ATA","crest":null,"reuse":null},
    {"ext":"seriea:bol","ar":"بولونيا","short":"BOL","crest":null,"reuse":null},
    {"ext":"seriea:cag","ar":"كالياري","short":"CAG","crest":null,"reuse":null},
    {"ext":"seriea:com","ar":"كومو","short":"COM","crest":null,"reuse":{"source":"ucl","ext":"ucl:com"}},
    {"ext":"seriea:fio","ar":"فيورنتينا","short":"FIO","crest":null,"reuse":null},
    {"ext":"seriea:fro","ar":"فروزينوني","short":"FRO","crest":null,"reuse":null},
    {"ext":"seriea:gen","ar":"جنوى","short":"GEN","crest":null,"reuse":null},
    {"ext":"seriea:int","ar":"إنتر ميلان","short":"INT","crest":null,"reuse":{"source":"ucl","ext":"ucl:int"}},
    {"ext":"seriea:juv","ar":"يوفنتوس","short":"JUV","crest":null,"reuse":null},
    {"ext":"seriea:laz","ar":"لاتسيو","short":"LAZ","crest":null,"reuse":null},
    {"ext":"seriea:lec","ar":"ليتشي","short":"LEC","crest":null,"reuse":null},
    {"ext":"seriea:mil","ar":"ميلان","short":"MIL","crest":null,"reuse":null},
    {"ext":"seriea:mon","ar":"مونزا","short":"MON","crest":null,"reuse":null},
    {"ext":"seriea:nap","ar":"نابولي","short":"NAP","crest":null,"reuse":{"source":"ucl","ext":"ucl:nap"}},
    {"ext":"seriea:par","ar":"بارما","short":"PAR","crest":null,"reuse":null},
    {"ext":"seriea:rom","ar":"روما","short":"ROM","crest":null,"reuse":{"source":"ucl","ext":"ucl:rom"}},
    {"ext":"seriea:sas","ar":"ساسولو","short":"SAS","crest":null,"reuse":null},
    {"ext":"seriea:tor","ar":"تورينو","short":"TOR","crest":null,"reuse":null},
    {"ext":"seriea:udi","ar":"أودينيزي","short":"UDI","crest":null,"reuse":null},
    {"ext":"seriea:ven","ar":"فينيسيا","short":"VEN","crest":null,"reuse":null}
  ]'::jsonb;
begin
  for r in select * from jsonb_array_elements(teams) as t(obj)
  loop
    select canonical_id into v_team_id
    from football_data.external_identity_map
    where external_source = 'seriea'
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
    values ('seriea', r.obj->>'ext', 'team', v_team_id)
    on conflict (external_source, external_id, canonical_table) do nothing;
  end loop;
end

$$;

commit;
