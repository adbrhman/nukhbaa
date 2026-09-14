-- ============================================================================
-- Migration 0046: national teams (CAF + AFC)
--
-- ADDITIVE ONLY. Gives migration 0045's four national-team competitions
-- (كأس الخليج، كأس آسيا، كأس أمم إفريقيا، تصفيات كأس أمم إفريقيا 2027) sides
-- to pick. No club row is touched, no column is added, nothing is deleted.
-- Safe to re-run: reconciliation goes through football_data.external_identity_map
-- exactly as the club seeds do (external_source 'caf' / 'afc'), so a second
-- run refreshes names instead of creating a second Egypt.
--
-- ## Membership, not one edition's entrants
-- The rows are the full CAF (54) and AFC (47) membership -- football reality,
-- stable between editions -- not the 24 who qualified for a given finals. A
-- catalog row is an identity, and an identity does not expire when a side
-- fails to qualify; seeding only the qualified would leave the AFCON
-- qualifiers unfillable and would need re-seeding every cycle.
--
-- ## league_id stays NULL
-- A national side belongs to no league, and all four competitions are
-- is_continental (0045), which by 0038's rule offers the whole catalog
-- regardless of league_id -- so a league_id here would be a value the picker
-- never reads. The cost is stated rather than hidden: national sides now also
-- appear in the other continental pickers (دوري أبطال أوروبا، الدوري
-- الأوروبي، كؤوس الأندية), because "the whole catalog" is exactly what
-- is_continental means today. Narrowing that needs a client change, not a
-- data one.
--
-- crest_url stays NULL, as in every club seed -- the card falls back to the
-- name alone.
-- ============================================================================

begin;

do $$
declare
  r record;
  v_team_id uuid;
  nations jsonb := '[
    {"src":"caf","ext":"caf:alg","ar":"الجزائر","short":"ALG"},
    {"src":"caf","ext":"caf:ang","ar":"أنغولا","short":"ANG"},
    {"src":"caf","ext":"caf:ben","ar":"بنين","short":"BEN"},
    {"src":"caf","ext":"caf:bot","ar":"بوتسوانا","short":"BOT"},
    {"src":"caf","ext":"caf:bfa","ar":"بوركينا فاسو","short":"BFA"},
    {"src":"caf","ext":"caf:bdi","ar":"بوروندي","short":"BDI"},
    {"src":"caf","ext":"caf:cmr","ar":"الكاميرون","short":"CMR"},
    {"src":"caf","ext":"caf:cpv","ar":"الرأس الأخضر","short":"CPV"},
    {"src":"caf","ext":"caf:cta","ar":"أفريقيا الوسطى","short":"CTA"},
    {"src":"caf","ext":"caf:cha","ar":"تشاد","short":"CHA"},
    {"src":"caf","ext":"caf:com","ar":"جزر القمر","short":"COM"},
    {"src":"caf","ext":"caf:cgo","ar":"الكونغو","short":"CGO"},
    {"src":"caf","ext":"caf:cod","ar":"الكونغو الديمقراطية","short":"COD"},
    {"src":"caf","ext":"caf:dji","ar":"جيبوتي","short":"DJI"},
    {"src":"caf","ext":"caf:egy","ar":"مصر","short":"EGY"},
    {"src":"caf","ext":"caf:eqg","ar":"غينيا الاستوائية","short":"EQG"},
    {"src":"caf","ext":"caf:eri","ar":"إريتريا","short":"ERI"},
    {"src":"caf","ext":"caf:swz","ar":"إسواتيني","short":"SWZ"},
    {"src":"caf","ext":"caf:eth","ar":"إثيوبيا","short":"ETH"},
    {"src":"caf","ext":"caf:gab","ar":"الغابون","short":"GAB"},
    {"src":"caf","ext":"caf:gam","ar":"غامبيا","short":"GAM"},
    {"src":"caf","ext":"caf:gha","ar":"غانا","short":"GHA"},
    {"src":"caf","ext":"caf:gui","ar":"غينيا","short":"GUI"},
    {"src":"caf","ext":"caf:gnb","ar":"غينيا بيساو","short":"GNB"},
    {"src":"caf","ext":"caf:civ","ar":"ساحل العاج","short":"CIV"},
    {"src":"caf","ext":"caf:ken","ar":"كينيا","short":"KEN"},
    {"src":"caf","ext":"caf:les","ar":"ليسوتو","short":"LES"},
    {"src":"caf","ext":"caf:lbr","ar":"ليبيريا","short":"LBR"},
    {"src":"caf","ext":"caf:lby","ar":"ليبيا","short":"LBY"},
    {"src":"caf","ext":"caf:mad","ar":"مدغشقر","short":"MAD"},
    {"src":"caf","ext":"caf:mwi","ar":"مالاوي","short":"MWI"},
    {"src":"caf","ext":"caf:mli","ar":"مالي","short":"MLI"},
    {"src":"caf","ext":"caf:mtn","ar":"موريتانيا","short":"MTN"},
    {"src":"caf","ext":"caf:mri","ar":"موريشيوس","short":"MRI"},
    {"src":"caf","ext":"caf:mar","ar":"المغرب","short":"MAR"},
    {"src":"caf","ext":"caf:moz","ar":"موزمبيق","short":"MOZ"},
    {"src":"caf","ext":"caf:nam","ar":"ناميبيا","short":"NAM"},
    {"src":"caf","ext":"caf:nig","ar":"النيجر","short":"NIG"},
    {"src":"caf","ext":"caf:nga","ar":"نيجيريا","short":"NGA"},
    {"src":"caf","ext":"caf:rwa","ar":"رواندا","short":"RWA"},
    {"src":"caf","ext":"caf:stp","ar":"ساو تومي وبرينسيبي","short":"STP"},
    {"src":"caf","ext":"caf:sen","ar":"السنغال","short":"SEN"},
    {"src":"caf","ext":"caf:sey","ar":"سيشل","short":"SEY"},
    {"src":"caf","ext":"caf:sle","ar":"سيراليون","short":"SLE"},
    {"src":"caf","ext":"caf:som","ar":"الصومال","short":"SOM"},
    {"src":"caf","ext":"caf:rsa","ar":"جنوب أفريقيا","short":"RSA"},
    {"src":"caf","ext":"caf:ssd","ar":"جنوب السودان","short":"SSD"},
    {"src":"caf","ext":"caf:sdn","ar":"السودان","short":"SDN"},
    {"src":"caf","ext":"caf:tan","ar":"تنزانيا","short":"TAN"},
    {"src":"caf","ext":"caf:tog","ar":"توغو","short":"TOG"},
    {"src":"caf","ext":"caf:tun","ar":"تونس","short":"TUN"},
    {"src":"caf","ext":"caf:uga","ar":"أوغندا","short":"UGA"},
    {"src":"caf","ext":"caf:zam","ar":"زامبيا","short":"ZAM"},
    {"src":"caf","ext":"caf:zim","ar":"زيمبابوي","short":"ZIM"},
    {"src":"afc","ext":"afc:afg","ar":"أفغانستان","short":"AFG"},
    {"src":"afc","ext":"afc:aus","ar":"أستراليا","short":"AUS"},
    {"src":"afc","ext":"afc:bhr","ar":"البحرين","short":"BHR"},
    {"src":"afc","ext":"afc:ban","ar":"بنغلاديش","short":"BAN"},
    {"src":"afc","ext":"afc:bhu","ar":"بوتان","short":"BHU"},
    {"src":"afc","ext":"afc:bru","ar":"بروناي","short":"BRU"},
    {"src":"afc","ext":"afc:cam","ar":"كمبوديا","short":"CAM"},
    {"src":"afc","ext":"afc:chn","ar":"الصين","short":"CHN"},
    {"src":"afc","ext":"afc:tpe","ar":"تايبيه الصينية","short":"TPE"},
    {"src":"afc","ext":"afc:gum","ar":"غوام","short":"GUM"},
    {"src":"afc","ext":"afc:hkg","ar":"هونغ كونغ","short":"HKG"},
    {"src":"afc","ext":"afc:ind","ar":"الهند","short":"IND"},
    {"src":"afc","ext":"afc:idn","ar":"إندونيسيا","short":"IDN"},
    {"src":"afc","ext":"afc:irn","ar":"إيران","short":"IRN"},
    {"src":"afc","ext":"afc:irq","ar":"العراق","short":"IRQ"},
    {"src":"afc","ext":"afc:jpn","ar":"اليابان","short":"JPN"},
    {"src":"afc","ext":"afc:jor","ar":"الأردن","short":"JOR"},
    {"src":"afc","ext":"afc:prk","ar":"كوريا الشمالية","short":"PRK"},
    {"src":"afc","ext":"afc:kor","ar":"كوريا الجنوبية","short":"KOR"},
    {"src":"afc","ext":"afc:kuw","ar":"الكويت","short":"KUW"},
    {"src":"afc","ext":"afc:kgz","ar":"قيرغيزستان","short":"KGZ"},
    {"src":"afc","ext":"afc:lao","ar":"لاوس","short":"LAO"},
    {"src":"afc","ext":"afc:lbn","ar":"لبنان","short":"LBN"},
    {"src":"afc","ext":"afc:mac","ar":"ماكاو","short":"MAC"},
    {"src":"afc","ext":"afc:mas","ar":"ماليزيا","short":"MAS"},
    {"src":"afc","ext":"afc:mdv","ar":"جزر المالديف","short":"MDV"},
    {"src":"afc","ext":"afc:mng","ar":"منغوليا","short":"MNG"},
    {"src":"afc","ext":"afc:mya","ar":"ميانمار","short":"MYA"},
    {"src":"afc","ext":"afc:nep","ar":"نيبال","short":"NEP"},
    {"src":"afc","ext":"afc:nmi","ar":"جزر ماريانا الشمالية","short":"NMI"},
    {"src":"afc","ext":"afc:oma","ar":"سلطنة عمان","short":"OMA"},
    {"src":"afc","ext":"afc:pak","ar":"باكستان","short":"PAK"},
    {"src":"afc","ext":"afc:ple","ar":"فلسطين","short":"PLE"},
    {"src":"afc","ext":"afc:phi","ar":"الفلبين","short":"PHI"},
    {"src":"afc","ext":"afc:qat","ar":"قطر","short":"QAT"},
    {"src":"afc","ext":"afc:ksa","ar":"السعودية","short":"KSA"},
    {"src":"afc","ext":"afc:sgp","ar":"سنغافورة","short":"SGP"},
    {"src":"afc","ext":"afc:sri","ar":"سريلانكا","short":"SRI"},
    {"src":"afc","ext":"afc:syr","ar":"سوريا","short":"SYR"},
    {"src":"afc","ext":"afc:tjk","ar":"طاجيكستان","short":"TJK"},
    {"src":"afc","ext":"afc:tha","ar":"تايلاند","short":"THA"},
    {"src":"afc","ext":"afc:tls","ar":"تيمور الشرقية","short":"TLS"},
    {"src":"afc","ext":"afc:tkm","ar":"تركمانستان","short":"TKM"},
    {"src":"afc","ext":"afc:uae","ar":"الإمارات","short":"UAE"},
    {"src":"afc","ext":"afc:uzb","ar":"أوزبكستان","short":"UZB"},
    {"src":"afc","ext":"afc:vie","ar":"فيتنام","short":"VIE"},
    {"src":"afc","ext":"afc:yem","ar":"اليمن","short":"YEM"}
  ]'::jsonb;
begin
  for r in select * from jsonb_array_elements(nations) as t(obj)
  loop
    select canonical_id into v_team_id
    from football_data.external_identity_map
    where external_source = (r.obj->>'src')
      and external_id = (r.obj->>'ext')
      and canonical_table = 'team';

    if v_team_id is null then
      v_team_id := gen_random_uuid();
      insert into football_data.teams (id, name, short_name, crest_url)
      values (v_team_id, r.obj->>'ar', r.obj->>'short', null);
      insert into football_data.external_identity_map
        (external_source, external_id, canonical_table, canonical_id)
      values (r.obj->>'src', r.obj->>'ext', 'team', v_team_id);
    else
      update football_data.teams
      set name = r.obj->>'ar',
          short_name = r.obj->>'short',
          updated_at = now()
      where id = v_team_id;
    end if;
  end loop;
end
$$;

commit;

-- Verification (expects 101):
-- select count(*) from football_data.external_identity_map
--  where external_source in ('caf','afc') and canonical_table = 'team';
