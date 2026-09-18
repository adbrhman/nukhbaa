-- 0050: FIFA Club World Cup 2025 team catalog.
-- Additive only. Reuses existing canonical club rows where the project
-- already has them, and creates missing CWC clubs with league_id = NULL.
-- No match, prediction, point, ledger, or fixture rows are modified.

begin;

do $$
declare
  r record;
  v_team_id uuid;
  v_existing_name text;
  v_reuse_source text;
  v_reuse_ext text;
  teams jsonb := '[
    {"ext":"cwc:al-ahly","ar":"الأهلي المصري","short":"AHL","reuse":null},
    {"ext":"cwc:al-hilal","ar":"الهلال","short":"HIL","reuse":{"source":"saudi","ext":"saudi:hil"}},
    {"ext":"cwc:al-ain","ar":"العين","short":"AIN","reuse":null},
    {"ext":"cwc:atletico-madrid","ar":"أتلتيكو مدريد","short":"ATM","reuse":{"source":"laliga","ext":"laliga:atm"}},
    {"ext":"cwc:auckland-city","ar":"أوكلاند سيتي","short":"AKL","reuse":null},
    {"ext":"cwc:bayern-munich","ar":"بايرن ميونخ","short":"BAY","reuse":{"source":"ucl","ext":"ucl:bay"}},
    {"ext":"cwc:benfica","ar":"بنفيكا","short":"BEN","reuse":{"source":"europa","ext":"europa:ben"}},
    {"ext":"cwc:boca-juniors","ar":"بوكا جونيورز","short":"BOC","reuse":null},
    {"ext":"cwc:borussia-dortmund","ar":"بوروسيا دورتموند","short":"BVB","reuse":{"source":"ucl","ext":"ucl:bvb"}},
    {"ext":"cwc:botafogo","ar":"بوتافوغو","short":"BOT","reuse":null},
    {"ext":"cwc:chelsea","ar":"تشيلسي","short":"CHE","reuse":{"source":"epl","ext":"epl:che"}},
    {"ext":"cwc:esperance","ar":"الترجي الرياضي التونسي","short":"EST","reuse":null},
    {"ext":"cwc:flamengo","ar":"فلامنغو","short":"FLA","reuse":null},
    {"ext":"cwc:fluminense","ar":"فلومينينسي","short":"FLU","reuse":null},
    {"ext":"cwc:inter-miami","ar":"إنتر ميامي","short":"MIA","reuse":null},
    {"ext":"cwc:inter-milan","ar":"إنتر ميلان","short":"INT","reuse":{"source":"ucl","ext":"ucl:int"}},
    {"ext":"cwc:juventus","ar":"يوفنتوس","short":"JUV","reuse":{"source":"seriea","ext":"seriea:juv"}},
    {"ext":"cwc:lafc","ar":"لوس أنجلوس إف سي","short":"LAFC","reuse":null},
    {"ext":"cwc:mamelodi-sundowns","ar":"ماميلودي صن داونز","short":"MSD","reuse":null},
    {"ext":"cwc:manchester-city","ar":"مانشستر سيتي","short":"MCI","reuse":{"source":"epl","ext":"epl:mci"}},
    {"ext":"cwc:monterrey","ar":"مونتيري","short":"MTY","reuse":null},
    {"ext":"cwc:pachuca","ar":"باتشوكا","short":"PAC","reuse":null},
    {"ext":"cwc:palmeiras","ar":"بالميراس","short":"PAL","reuse":null},
    {"ext":"cwc:paris-saint-germain","ar":"باريس سان جيرمان","short":"PSG","reuse":{"source":"ucl","ext":"ucl:psg"}},
    {"ext":"cwc:porto","ar":"بورتو","short":"POR","reuse":{"source":"ucl","ext":"ucl:por"}},
    {"ext":"cwc:real-madrid","ar":"ريال مدريد","short":"RMA","reuse":{"source":"laliga","ext":"laliga:rma"}},
    {"ext":"cwc:rb-salzburg","ar":"سالزبورغ","short":"RBS","reuse":{"source":"europa","ext":"europa:rbs"}},
    {"ext":"cwc:river-plate","ar":"ريفر بليت","short":"RIV","reuse":null},
    {"ext":"cwc:seattle-sounders","ar":"سياتل ساوندرز","short":"SEA","reuse":null},
    {"ext":"cwc:ulsan-hd","ar":"أولسان HD","short":"ULS","reuse":null},
    {"ext":"cwc:urawa-red-diamonds","ar":"أوراوا ريد دايموندز","short":"URA","reuse":null},
    {"ext":"cwc:wydad","ar":"الوداد","short":"WAC","reuse":null}
  ]'::jsonb;
begin
  for r in select * from jsonb_array_elements(teams) as t(obj)
  loop
    select canonical_id into v_team_id
    from football_data.external_identity_map
    where external_source = 'club_world_cup'
      and external_id = (r.obj->>'ext')
      and canonical_table = 'team';

    if v_team_id is not null then
      select name into v_existing_name
      from football_data.teams
      where id = v_team_id;
      if v_existing_name is distinct from (r.obj->>'ar') then
        raise exception 'CWC identity % already points to team % with name %, expected %',
          r.obj->>'ext', v_team_id, v_existing_name, r.obj->>'ar';
      end if;
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
      if v_team_id is null
         and exists (
           select 1
           from football_data.external_identity_map
           where external_source = v_reuse_source
         ) then
        raise exception 'Required reuse mapping %:% is missing for %',
          v_reuse_source, v_reuse_ext, r.obj->>'ar';
      end if;
    end if;

    if v_team_id is null then
      select id into v_team_id
      from football_data.teams
      where lower(btrim(name)) = lower(btrim(r.obj->>'ar'))
      limit 1;
    end if;

    if v_team_id is null then
      insert into football_data.teams (name, short_name, crest_url)
      values (r.obj->>'ar', r.obj->>'short', null)
      returning id into v_team_id;
    end if;

    insert into football_data.external_identity_map
      (external_source, external_id, canonical_table, canonical_id)
    values ('club_world_cup', r.obj->>'ext', 'team', v_team_id);
  end loop;
end
$$;

commit;
