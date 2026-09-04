-- ============================================================
-- Nukhba — Seed: Saudi Pro League (الدوري السعودي)
-- Season 2026/2027
-- Idempotent: safe to re-run. لا يكرّر ولا يكسر بيانات موجودة.
--
-- Roster verified 2026-09-04 against
-- en.wikipedia.org/wiki/2026–27_Saudi_Pro_League (participating-clubs
-- table), independently cross-checked against the already-shipped
-- apps/mobile/.../team_registry.dart kSaudiTeams table (same 18 clubs).
--
-- crest_url intentionally NULL — see epl_2026_27.sql's header for the
-- licensing rationale.
--
-- competition/season ids below target the row an admin already created
-- manually for this league (confirmed against the live DB 2026-09-04,
-- named "روشن السعودي" there) — NOT a freshly-invented id, and the
-- competition insert is "do nothing" on conflict so this seed never
-- overwrites that existing name.
-- ============================================================

begin;

insert into competition.competitions (id, name, format, visibility)
values (
  '496e8eae-0be2-4065-b15a-dd53b577c323',
  'روشن السعودي',
  'football_scoreline',
  'public'
)
on conflict (id) do nothing;

insert into competition.seasons (id, competition_id, label, start_at, end_at)
values (
  '252dbdbf-fa77-4a46-a60e-bb2565fdd888',
  '496e8eae-0be2-4065-b15a-dd53b577c323',
  '2026/27',
  (date_trunc('month', now() at time zone 'utc') at time zone 'utc'),
  (date_trunc('month', now() at time zone 'utc') at time zone 'utc') + interval '1 month'
)
on conflict (id) do update
  set label = excluded.label,
      start_at = excluded.start_at,
      end_at = excluded.end_at,
      updated_at = now();

do $$
declare
  r record;
  v_team_id uuid;
  teams jsonb := '[
    {"ext":"saudi:abh","ar":"أبها","short":"ABH","crest":null},
    {"ext":"saudi:ahl","ar":"الأهلي","short":"AHL","crest":null},
    {"ext":"saudi:dir","ar":"الدرعية","short":"DIR","crest":null},
    {"ext":"saudi:ett","ar":"الاتفاق","short":"ETT","crest":null},
    {"ext":"saudi:fai","ar":"الفيصلي","short":"FAI","crest":null},
    {"ext":"saudi:fat","ar":"الفتح","short":"FAT","crest":null},
    {"ext":"saudi:fay","ar":"الفيحاء","short":"FAY","crest":null},
    {"ext":"saudi:haz","ar":"الحزم","short":"HAZ","crest":null},
    {"ext":"saudi:hil","ar":"الهلال","short":"HIL","crest":null},
    {"ext":"saudi:itt","ar":"الاتحاد","short":"ITT","crest":null},
    {"ext":"saudi:kha","ar":"الخليج","short":"KHA","crest":null},
    {"ext":"saudi:kho","ar":"الخلود","short":"KHO","crest":null},
    {"ext":"saudi:nas","ar":"النصر","short":"NAS","crest":null},
    {"ext":"saudi:qad","ar":"القادسية","short":"QAD","crest":null},
    {"ext":"saudi:riy","ar":"الرياض","short":"RIY","crest":null},
    {"ext":"saudi:sha","ar":"الشباب","short":"SHA","crest":null},
    {"ext":"saudi:taa","ar":"التعاون","short":"TAA","crest":null},
    {"ext":"saudi:neo","ar":"نيوم","short":"NEO","crest":null}
  ]'::jsonb;
begin
  for r in select * from jsonb_array_elements(teams) as t(obj)
  loop
    select canonical_id into v_team_id
    from football_data.external_identity_map
    where external_source = 'saudi'
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
      values ('saudi', r.obj->>'ext', 'team', v_team_id);
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
