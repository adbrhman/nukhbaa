-- ============================================================
-- Nukhba — Seed: English Premier League (الدوري الإنجليزي الممتاز)
-- Season 2026/2027
-- Idempotent: safe to re-run. لا يكرّر ولا يكسر بيانات موجودة.
--
-- Roster verified 2026-09-04 against en.wikipedia.org/wiki/Premier_League
-- (states "Current: 2026–27 Premier League") and
-- en.wikipedia.org/wiki/2026–27_Premier_League (participating-clubs table),
-- cross-checked independently — both agree on the same 20 clubs. Arabic
-- names mirror the already-shipped apps/mobile/.../team_registry.dart
-- kEplTeams table (same 20 clubs, independently corroborating the roster).
--
-- competition/season ids below target the row an admin already created
-- manually for this league (confirmed against the live DB 2026-09-04) —
-- NOT a freshly-invented id, to avoid creating a duplicate competition.
--
-- crest_url intentionally NULL for every team: Wikipedia-hosted club crests
-- are licensed "non-free/fair-use, English Wikipedia articles only" — not
-- cleared for reuse in this app. Left as an explicit open decision (see
-- session record) rather than reused without a clear license, per the
-- "rights stay with their owners" requirement. UI already degrades
-- gracefully to the initials-circle fallback for a null crest.
-- ============================================================

begin;

-- do nothing on conflict: this row was already created manually by an
-- admin (confirmed live 2026-09-04) — this seed only needs the id to
-- exist to attach teams to it, and must not risk overwriting a name it
-- doesn't have byte-for-byte confirmation of.
insert into competition.competitions (id, name, format, visibility)
values (
  '093c7c78-25a9-42b7-85f9-af0727810fe9',
  'الدوري الإنجليزي الممتاز',
  'football_scoreline',
  'public'
)
on conflict (id) do nothing;

insert into competition.seasons (id, competition_id, label)
values (
  '9227e085-c8eb-4bb8-beb0-99b17fa43d51',
  '093c7c78-25a9-42b7-85f9-af0727810fe9',
  '2026/27'
)
on conflict (id) do update
  set label = excluded.label,
      updated_at = now();

do $$
declare
  r record;
  v_team_id uuid;
  teams jsonb := '[
    {"ext":"epl:ars","ar":"أرسنال","en":"Arsenal","short":"ARS","crest":null},
    {"ext":"epl:avl","ar":"أستون فيلا","en":"Aston Villa","short":"AVL","crest":null},
    {"ext":"epl:bou","ar":"بورنموث","en":"AFC Bournemouth","short":"BOU","crest":null},
    {"ext":"epl:bre","ar":"برينتفورد","en":"Brentford","short":"BRE","crest":null},
    {"ext":"epl:bha","ar":"برايتون","en":"Brighton & Hove Albion","short":"BHA","crest":null},
    {"ext":"epl:che","ar":"تشيلسي","en":"Chelsea","short":"CHE","crest":null},
    {"ext":"epl:cov","ar":"كوفنتري سيتي","en":"Coventry City","short":"COV","crest":null},
    {"ext":"epl:cry","ar":"كريستال بالاس","en":"Crystal Palace","short":"CRY","crest":null},
    {"ext":"epl:eve","ar":"إيفرتون","en":"Everton","short":"EVE","crest":null},
    {"ext":"epl:ful","ar":"فولهام","en":"Fulham","short":"FUL","crest":null},
    {"ext":"epl:hul","ar":"هال سيتي","en":"Hull City","short":"HUL","crest":null},
    {"ext":"epl:ips","ar":"إبسويتش تاون","en":"Ipswich Town","short":"IPS","crest":null},
    {"ext":"epl:lee","ar":"ليدز يونايتد","en":"Leeds United","short":"LEE","crest":null},
    {"ext":"epl:liv","ar":"ليفربول","en":"Liverpool","short":"LIV","crest":null},
    {"ext":"epl:mci","ar":"مانشستر سيتي","en":"Manchester City","short":"MCI","crest":null},
    {"ext":"epl:mun","ar":"مانشستر يونايتد","en":"Manchester United","short":"MUN","crest":null},
    {"ext":"epl:new","ar":"نيوكاسل","en":"Newcastle United","short":"NEW","crest":null},
    {"ext":"epl:nfo","ar":"نوتينغهام فورست","en":"Nottingham Forest","short":"NFO","crest":null},
    {"ext":"epl:sun","ar":"سندرلاند","en":"Sunderland","short":"SUN","crest":null},
    {"ext":"epl:tot","ar":"توتنهام","en":"Tottenham Hotspur","short":"TOT","crest":null}
  ]'::jsonb;
begin
  for r in select * from jsonb_array_elements(teams) as t(obj)
  loop
    select canonical_id into v_team_id
    from football_data.external_identity_map
    where external_source = 'epl'
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
      values ('epl', r.obj->>'ext', 'team', v_team_id);
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
