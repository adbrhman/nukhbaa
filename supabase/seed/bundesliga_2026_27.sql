-- ============================================================
-- Nukhba — Seed: Bundesliga (الدوري الألماني)
-- Season 2026/2027
-- Idempotent: safe to re-run. لا يكرّر ولا يكسر بيانات موجودة.
--
-- Roster verified 2026-09-04 against
-- en.wikipedia.org/wiki/2026–27_Bundesliga (participating-clubs table),
-- independently cross-checked against the already-shipped
-- apps/mobile/.../team_logo_assets.dart kMonthlyCompetitionLogoGroups
-- Bundesliga slug list (same 18 clubs).
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
  '11111111-1111-4111-8111-000000000005',
  'الدوري الألماني',
  'football_scoreline',
  'public'
)
on conflict (id) do update
  set name = excluded.name,
      visibility = excluded.visibility,
      updated_at = now();

insert into competition.seasons (id, competition_id, label, start_at, end_at)
values (
  '22222222-2222-4222-8222-000000000005',
  '11111111-1111-4111-8111-000000000005',
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
  v_reuse_source text;
  v_reuse_ext text;
  teams jsonb := '[
    {"ext":"bundesliga:fca","ar":"أوغسبورغ","short":"FCA","crest":null,"reuse":null},
    {"ext":"bundesliga:fcu","ar":"يونيون برلين","short":"FCU","crest":null,"reuse":null},
    {"ext":"bundesliga:svw","ar":"فيردر بريمن","short":"SVW","crest":null,"reuse":null},
    {"ext":"bundesliga:bvb","ar":"بوروسيا دورتموند","short":"BVB","crest":null,"reuse":{"source":"ucl","ext":"ucl:bvb"}},
    {"ext":"bundesliga:sve","ar":"إلفرسبيرغ","short":"SVE","crest":null,"reuse":null},
    {"ext":"bundesliga:sge","ar":"آينتراخت فرانكفورت","short":"SGE","crest":null,"reuse":null},
    {"ext":"bundesliga:scf","ar":"فرايبورغ","short":"SCF","crest":null,"reuse":null},
    {"ext":"bundesliga:hsv","ar":"هامبورغ","short":"HSV","crest":null,"reuse":null},
    {"ext":"bundesliga:tsg","ar":"هوفنهايم","short":"TSG","crest":null,"reuse":null},
    {"ext":"bundesliga:koe","ar":"كولن","short":"KOE","crest":null,"reuse":null},
    {"ext":"bundesliga:rbl","ar":"لايبزيغ","short":"RBL","crest":null,"reuse":{"source":"ucl","ext":"ucl:rbl"}},
    {"ext":"bundesliga:b04","ar":"باير ليفركوزن","short":"B04","crest":null,"reuse":null},
    {"ext":"bundesliga:m05","ar":"ماينز","short":"M05","crest":null,"reuse":null},
    {"ext":"bundesliga:bmg","ar":"بوروسيا مونشنغلادباخ","short":"BMG","crest":null,"reuse":null},
    {"ext":"bundesliga:fcb","ar":"بايرن ميونخ","short":"FCB","crest":null,"reuse":{"source":"ucl","ext":"ucl:bay"}},
    {"ext":"bundesliga:scp","ar":"بادربورن","short":"SCP","crest":null,"reuse":null},
    {"ext":"bundesliga:s04","ar":"شالكه","short":"S04","crest":null,"reuse":null},
    {"ext":"bundesliga:vfb","ar":"شتوتغارت","short":"VFB","crest":null,"reuse":{"source":"ucl","ext":"ucl:vfb"}}
  ]'::jsonb;
begin
  for r in select * from jsonb_array_elements(teams) as t(obj)
  loop
    select canonical_id into v_team_id
    from football_data.external_identity_map
    where external_source = 'bundesliga'
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
    values ('bundesliga', r.obj->>'ext', 'team', v_team_id)
    on conflict (external_source, external_id, canonical_table) do nothing;
  end loop;
end

$$;

commit;
