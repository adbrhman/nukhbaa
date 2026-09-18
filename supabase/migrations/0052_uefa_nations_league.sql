-- ============================================================================
-- Migration 0052: UEFA Nations League + European national teams
--
-- ADDITIVE ONLY. One new row in `football_data.leagues` (migration 0027) and
-- the 54 UEFA sides, so «دوري الأمم الأوروبية» can be picked the same way
-- «كأس أمم إفريقيا» already is (migrations 0045 + 0046). No club row is
-- touched, no column is added, nothing is deleted.
--
-- Safe to re-run: reconciliation goes through football_data.external_identity_map
-- with external_source 'uefa', so a second run refreshes names instead of
-- creating a second Spain.
--
-- ## Membership, not one edition's entrants
-- The rows are UEFA's membership, not the sides drawn into a given League A/B
-- group -- the same reasoning 0046 states for CAF and AFC. Russia is absent:
-- it is suspended from UEFA competition and has no fixture to predict.
--
-- ## league_id stays NULL, is_continental is true
-- A national side belongs to no league, and the competition draws its
-- entrants from other leagues, so by 0038's rule the picker offers the whole
-- catalog regardless. Stated rather than hidden: these 54 now also appear in
-- the other continental pickers, exactly as 0046's 101 sides already do.
--
-- crest_url stays NULL, as in every seed: the client resolves the badge from
-- the Arabic name (apps/mobile/.../team_logo_assets.dart).
-- ============================================================================

begin;

insert into football_data.leagues (name, is_continental)
select 'دوري الأمم الأوروبية', true
where not exists (
  select 1
  from football_data.leagues l
  where btrim(l.name) = 'دوري الأمم الأوروبية'
);

do $$
declare
  r record;
  v_team_id uuid;
  nations jsonb := '[
    {"ext":"uefa:alb","ar":"ألبانيا","short":"ALB"},
    {"ext":"uefa:and","ar":"أندورا","short":"AND"},
    {"ext":"uefa:arm","ar":"أرمينيا","short":"ARM"},
    {"ext":"uefa:aut","ar":"النمسا","short":"AUT"},
    {"ext":"uefa:aze","ar":"أذربيجان","short":"AZE"},
    {"ext":"uefa:blr","ar":"بيلاروسيا","short":"BLR"},
    {"ext":"uefa:bel","ar":"بلجيكا","short":"BEL"},
    {"ext":"uefa:bih","ar":"البوسنة والهرسك","short":"BIH"},
    {"ext":"uefa:bul","ar":"بلغاريا","short":"BUL"},
    {"ext":"uefa:cro","ar":"كرواتيا","short":"CRO"},
    {"ext":"uefa:cyp","ar":"قبرص","short":"CYP"},
    {"ext":"uefa:cze","ar":"التشيك","short":"CZE"},
    {"ext":"uefa:den","ar":"الدنمارك","short":"DEN"},
    {"ext":"uefa:ned","ar":"هولندا","short":"NED"},
    {"ext":"uefa:eng","ar":"إنجلترا","short":"ENG"},
    {"ext":"uefa:est","ar":"إستونيا","short":"EST"},
    {"ext":"uefa:fro","ar":"جزر فارو","short":"FRO"},
    {"ext":"uefa:fin","ar":"فنلندا","short":"FIN"},
    {"ext":"uefa:fra","ar":"فرنسا","short":"FRA"},
    {"ext":"uefa:geo","ar":"جورجيا","short":"GEO"},
    {"ext":"uefa:ger","ar":"ألمانيا","short":"GER"},
    {"ext":"uefa:gib","ar":"جبل طارق","short":"GIB"},
    {"ext":"uefa:gre","ar":"اليونان","short":"GRE"},
    {"ext":"uefa:hun","ar":"المجر","short":"HUN"},
    {"ext":"uefa:isl","ar":"آيسلندا","short":"ISL"},
    {"ext":"uefa:isr","ar":"إسرائيل","short":"ISR"},
    {"ext":"uefa:ita","ar":"إيطاليا","short":"ITA"},
    {"ext":"uefa:kaz","ar":"كازاخستان","short":"KAZ"},
    {"ext":"uefa:kvx","ar":"كوسوفو","short":"KVX"},
    {"ext":"uefa:lva","ar":"لاتفيا","short":"LVA"},
    {"ext":"uefa:lie","ar":"ليختنشتاين","short":"LIE"},
    {"ext":"uefa:ltu","ar":"ليتوانيا","short":"LTU"},
    {"ext":"uefa:lux","ar":"لوكسمبورغ","short":"LUX"},
    {"ext":"uefa:mlt","ar":"مالطا","short":"MLT"},
    {"ext":"uefa:mda","ar":"مولدوفا","short":"MDA"},
    {"ext":"uefa:mne","ar":"الجبل الأسود","short":"MNE"},
    {"ext":"uefa:mkd","ar":"مقدونيا الشمالية","short":"MKD"},
    {"ext":"uefa:nir","ar":"أيرلندا الشمالية","short":"NIR"},
    {"ext":"uefa:nor","ar":"النرويج","short":"NOR"},
    {"ext":"uefa:pol","ar":"بولندا","short":"POL"},
    {"ext":"uefa:por","ar":"البرتغال","short":"POR"},
    {"ext":"uefa:irl","ar":"جمهورية أيرلندا","short":"IRL"},
    {"ext":"uefa:rou","ar":"رومانيا","short":"ROU"},
    {"ext":"uefa:smr","ar":"سان مارينو","short":"SMR"},
    {"ext":"uefa:sco","ar":"إسكتلندا","short":"SCO"},
    {"ext":"uefa:srb","ar":"صربيا","short":"SRB"},
    {"ext":"uefa:svk","ar":"سلوفاكيا","short":"SVK"},
    {"ext":"uefa:svn","ar":"سلوفينيا","short":"SVN"},
    {"ext":"uefa:esp","ar":"إسبانيا","short":"ESP"},
    {"ext":"uefa:swe","ar":"السويد","short":"SWE"},
    {"ext":"uefa:sui","ar":"سويسرا","short":"SUI"},
    {"ext":"uefa:tur","ar":"تركيا","short":"TUR"},
    {"ext":"uefa:ukr","ar":"أوكرانيا","short":"UKR"},
    {"ext":"uefa:wal","ar":"ويلز","short":"WAL"}
  ]';
begin
  for r in select * from jsonb_array_elements(nations) as t(obj)
  loop
    select canonical_id into v_team_id
    from football_data.external_identity_map
    where external_source = 'uefa'
      and external_id = (r.obj->>'ext')
      and canonical_table = 'team';

    if v_team_id is null then
      v_team_id := gen_random_uuid();
      insert into football_data.teams (id, name, short_name, crest_url)
      values (v_team_id, r.obj->>'ar', r.obj->>'short', null);
      insert into football_data.external_identity_map
        (external_source, external_id, canonical_table, canonical_id)
      values ('uefa', r.obj->>'ext', 'team', v_team_id);
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

-- Verification (expects 54):
-- select count(*) from football_data.external_identity_map
--  where external_source = 'uefa' and canonical_table = 'team';
--
-- select name, is_continental from football_data.leagues
--  where btrim(name) = 'دوري الأمم الأوروبية';
