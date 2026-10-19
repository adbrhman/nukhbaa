-- ============================================================================
-- Migration 0181: the clubs of the UEFA Conference League
--
-- ADDITIVE ONLY. Teams and identity rows; no match, prediction, point,
-- ledger, fixture or league row is touched, and no team is renamed.
--
-- The 36 clubs of the owner's Conference League crest pack (2026-10-20),
-- for the competition 0180 added. The league is is_continental, so no club
-- is tagged to it: league_id stays as it is for a reused club and NULL for
-- a new one. crest_url stays NULL: the app draws the bundled crest by the
-- club's name (team_logo_assets.dart).
--
-- A club is reused, never duplicated: first by its identity under the
-- source 'uecl' (a re-run), then by competition.team_name_key (0110) of its
-- name or of one of its other spellings, so a club an admin already added
-- as "النجم الأحمر بلغراد" is that club, not a second Red Star. Seven are
-- in the catalog already (Ajax and Panathinaikos from 0104; Brighton,
-- Atalanta, Monaco, Freiburg and Getafe from the 2026-27 seeds); the rest
-- are created. Each is recorded in external_identity_map under 'uecl'.
--
-- Forward-only, guarded. Safe to re-run.
-- ============================================================================

begin;

do $$
declare
  r record;
  v_team_id uuid;
  v_existing_name text;
  v_keys text[];
  teams jsonb := '[
    {"ext":"uecl:agf","ar":"آرهوس","short":"AGF","aka":["أرهوس", "أغف آرهوس"]},
    {"ext":"uecl:ajax","ar":"أياكس","short":"AJA","aka":["أياكس أمستردام"]},
    {"ext":"uecl:monaco","ar":"موناكو","short":"ASM","aka":[]},
    {"ext":"uecl:atalanta","ar":"أتالانتا","short":"ATA","aka":[]},
    {"ext":"uecl:borac","ar":"بوراتس بانيا لوكا","short":"BOR","aka":["بوراتس"]},
    {"ext":"uecl:brann","ar":"بران","short":"BRA","aka":["بران بيرغن"]},
    {"ext":"uecl:brighton","ar":"برايتون","short":"BHA","aka":["برايتون آند هوف ألبيون"]},
    {"ext":"uecl:copenhagen","ar":"كوبنهاغن","short":"FCK","aka":["كوبنهاجن", "إف سي كوبنهاغن"]},
    {"ext":"uecl:crvena-zvezda","ar":"النجم الأحمر","short":"CZV","aka":["النجم الأحمر بلغراد", "ريد ستار", "ريد ستار بلغراد", "تسرفينا زفيزدا"]},
    {"ext":"uecl:cska-sofia","ar":"سسكا صوفيا","short":"CSK","aka":["زسكا صوفيا"]},
    {"ext":"uecl:egnatia","ar":"إغناتيا","short":"EGN","aka":["إيغناتيا"]},
    {"ext":"uecl:freiburg","ar":"فرايبورغ","short":"SCF","aka":[]},
    {"ext":"uecl:gent","ar":"غينت","short":"GNT","aka":["جنت", "خنت"]},
    {"ext":"uecl:getafe","ar":"خيتافي","short":"GET","aka":[]},
    {"ext":"uecl:hajduk-split","ar":"هايدوك سبليت","short":"HAJ","aka":["هايدوك"]},
    {"ext":"uecl:hearts","ar":"هارتس","short":"HEA","aka":["هارتس أوف ميدلوثيان"]},
    {"ext":"uecl:iberia","ar":"إيبيريا تبليسي","short":"IBE","aka":["إيبيريا 1999", "إيبيريا"]},
    {"ext":"uecl:inter-escaldes","ar":"إنتر إسكالديس","short":"IES","aka":["إنتر كلوب إسكالديس"]},
    {"ext":"uecl:jablonec","ar":"يابلونتس","short":"JAB","aka":["يابلونيتس"]},
    {"ext":"uecl:kairat","ar":"كايرات ألماتي","short":"KAI","aka":["كايرات"]},
    {"ext":"uecl:kauno-zalgiris","ar":"كاونو جالغيريس","short":"KAU","aka":["جالغيريس كاوناس"]},
    {"ext":"uecl:kups","ar":"كوبس","short":"KUP","aka":["كوبس كوبيو"]},
    {"ext":"uecl:lincoln-red-imps","ar":"لينكولن ريد إمبس","short":"LRI","aka":["لينكولن"]},
    {"ext":"uecl:lugano","ar":"لوغانو","short":"LUG","aka":[]},
    {"ext":"uecl:midtjylland","ar":"ميتيلاند","short":"FCM","aka":["ميدتيلاند"]},
    {"ext":"uecl:mjallby","ar":"ميالبي","short":"MJA","aka":[]},
    {"ext":"uecl:nordsjaelland","ar":"نوردشيلاند","short":"FCN","aka":["نوردسيلاند"]},
    {"ext":"uecl:pafos","ar":"بافوس","short":"PAF","aka":[]},
    {"ext":"uecl:panathinaikos","ar":"باناثينايكوس","short":"PAO","aka":[]},
    {"ext":"uecl:riga","ar":"ريغا","short":"RIG","aka":["ريغا إف سي"]},
    {"ext":"uecl:sc-braga","ar":"براغا","short":"SCB","aka":["سبورتينغ براغا"]},
    {"ext":"uecl:sint-truidense","ar":"سانت تروند","short":"STV","aka":["سينت ترويدن"]},
    {"ext":"uecl:thun","ar":"تون","short":"THU","aka":["إف سي تون"]},
    {"ext":"uecl:trabzonspor","ar":"طرابزون سبور","short":"TRA","aka":["طرابزونسبور"]},
    {"ext":"uecl:twente","ar":"تفينتي","short":"TWE","aka":["توينتي"]},
    {"ext":"uecl:u-craiova","ar":"أونيفيرسيتاتيا كرايوفا","short":"UCV","aka":["يونيفرسيتاتيا كرايوفا", "كرايوفا"]}
  ]'::jsonb;
begin
  for r in select * from jsonb_array_elements(teams) as t(obj)
  loop
    select canonical_id into v_team_id
    from football_data.external_identity_map
    where external_source = 'uecl'
      and external_id = (r.obj->>'ext')
      and canonical_table = 'team';

    if v_team_id is not null then
      select name into v_existing_name
      from football_data.teams
      where id = v_team_id;
      if v_existing_name is null then
        raise exception 'UECL identity % points to missing team %',
          r.obj->>'ext', v_team_id;
      end if;
      continue;
    end if;

    select array_agg(competition.team_name_key(n))
    into v_keys
    from (
      select r.obj->>'ar' as n
      union all
      select jsonb_array_elements_text(r.obj->'aka')
    ) names;

    select id into v_team_id
    from football_data.teams
    where competition.team_name_key(name) = any (v_keys)
    order by (competition.team_name_key(name) = v_keys[1]) desc, created_at, id
    limit 1;

    if v_team_id is null then
      insert into football_data.teams (name, short_name, crest_url)
      values (r.obj->>'ar', r.obj->>'short', null)
      returning id into v_team_id;
    end if;

    insert into football_data.external_identity_map
      (external_source, external_id, canonical_table, canonical_id)
    values ('uecl', r.obj->>'ext', 'team', v_team_id);
  end loop;
end
$$;

insert into ops.applied_migrations (version)
values ('0181_conference_league_clubs')
on conflict (version) do nothing;

commit;

-- Verification (expects 36 mapped clubs, each its own team):
-- select count(*), count(distinct canonical_id)
--   from football_data.external_identity_map
--  where external_source = 'uecl' and canonical_table = 'team';
