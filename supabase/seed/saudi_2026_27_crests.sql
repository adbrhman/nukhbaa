-- ============================================================
-- Nukhba — Seed: Saudi Pro League 2026/27 — crest_url for all 18 clubs.
-- Idempotent: safe to re-run. لا يكرّر ولا يكسر بيانات موجودة.
--
-- saudi_2026_27.sql already seeded all 18 clubs (full roster, no
-- pending slots like the European competitions had) — this file only
-- adds crest_url, keyed by the same 'saudi:<ext>' identity, matched
-- against the official 2026/27 SPL crest set
-- (docs/handoff/logos-2026-27/, saudi-2026-27-teams.csv) by football
-- knowledge, not the unreliable filename-derived guess in
-- LOGOS_MANIFEST.csv.
--
-- crest_url is the FINAL public Storage URL for the `team-logos`
-- bucket (migration 0026), computed deterministically, same as the
-- other two crest seeds:
--   https://thxzwzscwukifymjthnp.supabase.co/storage/v1/object/public/team-logos/<slug>.png
-- The actual 18 PNG uploads are a separate step — see
-- upload_saudi_2026_27_crests.sh.
-- ============================================================

begin;

do $$
declare
  r record;
  v_base text := 'https://thxzwzscwukifymjthnp.supabase.co/storage/v1/object/public/team-logos/';
  crests jsonb := '[
    {"ext":"saudi:ahl","slug":"al-ahli"},
    {"ext":"saudi:ett","slug":"al-ettifaq"},
    {"ext":"saudi:fat","slug":"al-fateh"},
    {"ext":"saudi:fay","slug":"al-fayha"},
    {"ext":"saudi:hil","slug":"al-hilal"},
    {"ext":"saudi:itt","slug":"al-ittihad"},
    {"ext":"saudi:kha","slug":"al-khaleej"},
    {"ext":"saudi:kho","slug":"al-kholood"},
    {"ext":"saudi:nas","slug":"al-nassr"},
    {"ext":"saudi:qad","slug":"al-qadsiah"},
    {"ext":"saudi:riy","slug":"al-riyadh"},
    {"ext":"saudi:sha","slug":"al-shabab"},
    {"ext":"saudi:taa","slug":"al-taawoun"},
    {"ext":"saudi:haz","slug":"al-hazem"},
    {"ext":"saudi:neo","slug":"neom"},
    {"ext":"saudi:abh","slug":"abha"},
    {"ext":"saudi:fai","slug":"al-faisaly"},
    {"ext":"saudi:dir","slug":"diriyah"}
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
      where external_source = 'saudi'
        and external_id = (r.obj->>'ext')
        and canonical_table = 'team'
    );
  end loop;
end
$$;

commit;
