-- ============================================================================
-- Migration 0104: the big derbies (ديربيات كبرى)
--
-- ADDITIVE ONLY. One new row in football_data.leagues and the clubs of the
-- world's best-known derbies whose own league the app does not carry. No
-- match, prediction, point, ledger or fixture row is touched.
--
-- ## The league
-- is_continental = true, as 0038 and 0103 set for a competition that draws
-- its clubs from other leagues: the admin picker offers the whole catalog
-- under it, and no club is tagged to it. Fixtures are added by an admin, one
-- derby at a time (decided with the owner 2026-10-12), not by the provider
-- sync, so the matches tab carries the derby and not the rest of its league.
--
-- ## The clubs (31, in derby pairs)
--   Cairo           الأهلي المصري (0050)        - الزمالك
--   Casablanca      الوداد (0050)               - الرجاء
--   Tunis           الترجي الرياضي التونسي (0050) - النادي الإفريقي
--   Omdurman        الهلال السوداني             - المريخ
--   Algiers         مولودية الجزائر             - اتحاد العاصمة
--   Amman           الفيصلي الأردني             - الوحدات
--   Baghdad         القوة الجوية (0103)         - الزوراء
--   Tehran          استقلال طهران (0103)        - برسبوليس
--   Buenos Aires    بوكا جونيورز (0050)         - ريفر بليت (0050)
--   Rio             فلامنغو (0050)              - فلومينينسي (0050)
--   Glasgow         سلتيك                       - رينجرز
--   Istanbul        غلطة سراي - فنربخشة - بشكتاش
--   Athens          أولمبياكوس                  - باناثينايكوس
--   Netherlands     أياكس                       - فينورد
--   Lisbon          بنفيكا (0050)               - سبورتينغ لشبونة
-- A club created by 0050 or 0103 is reused through that migration's
-- identity; a club already in the catalog under the same Arabic name (the
-- 2026-27 seeds: سلتيك، غلطة سراي، فنربخشة، بشكتاش، أولمبياكوس، فينورد،
-- سبورتينغ لشبونة) is reused by name; the rest are created with
-- league_id NULL and crest NULL (initials until a crest is added). Each club
-- is recorded in external_identity_map under the source 'big_derbies', so a
-- re-run creates nothing twice.
--
-- Forward-only, guarded. Safe to re-run.
-- ============================================================================

begin;

insert into football_data.leagues (name, short_name, is_continental)
select 'ديربيات كبرى', 'DRB', true
where not exists (
  select 1
  from football_data.leagues l
  where btrim(l.name) = 'ديربيات كبرى'
);

do $$
declare
  r record;
  v_team_id uuid;
  v_existing_name text;
  v_reuse_source text;
  v_reuse_ext text;
  teams jsonb := '[
    {"ext":"drb:ahly","ar":"الأهلي المصري","short":"AHL","reuse":{"source":"club_world_cup","ext":"cwc:al-ahly"}},
    {"ext":"drb:zamalek","ar":"الزمالك","short":"ZAM","reuse":null},
    {"ext":"drb:wydad","ar":"الوداد","short":"WAC","reuse":{"source":"club_world_cup","ext":"cwc:wydad"}},
    {"ext":"drb:raja","ar":"الرجاء","short":"RCA","reuse":null},
    {"ext":"drb:esperance","ar":"الترجي الرياضي التونسي","short":"EST","reuse":{"source":"club_world_cup","ext":"cwc:esperance"}},
    {"ext":"drb:club-africain","ar":"النادي الإفريقي","short":"CA","reuse":null},
    {"ext":"drb:al-hilal-sd","ar":"الهلال السوداني","short":"HSD","reuse":null},
    {"ext":"drb:al-merrikh","ar":"المريخ","short":"MER","reuse":null},
    {"ext":"drb:mc-alger","ar":"مولودية الجزائر","short":"MCA","reuse":null},
    {"ext":"drb:usm-alger","ar":"اتحاد العاصمة","short":"USMA","reuse":null},
    {"ext":"drb:al-faisaly-jo","ar":"الفيصلي الأردني","short":"FAI","reuse":null},
    {"ext":"drb:al-wehdat","ar":"الوحدات","short":"WEH","reuse":null},
    {"ext":"drb:al-quwa","ar":"القوة الجوية","short":"QWJ","reuse":{"source":"acl_elite","ext":"acle:qwj"}},
    {"ext":"drb:al-zawraa","ar":"الزوراء","short":"ZAW","reuse":null},
    {"ext":"drb:esteghlal","ar":"استقلال طهران","short":"EST","reuse":{"source":"acl_elite","ext":"acle:est"}},
    {"ext":"drb:persepolis","ar":"برسبوليس","short":"PER","reuse":null},
    {"ext":"drb:boca","ar":"بوكا جونيورز","short":"BOC","reuse":{"source":"club_world_cup","ext":"cwc:boca-juniors"}},
    {"ext":"drb:river","ar":"ريفر بليت","short":"RIV","reuse":{"source":"club_world_cup","ext":"cwc:river-plate"}},
    {"ext":"drb:flamengo","ar":"فلامنغو","short":"FLA","reuse":{"source":"club_world_cup","ext":"cwc:flamengo"}},
    {"ext":"drb:fluminense","ar":"فلومينينسي","short":"FLU","reuse":{"source":"club_world_cup","ext":"cwc:fluminense"}},
    {"ext":"drb:celtic","ar":"سلتيك","short":"CEL","reuse":null},
    {"ext":"drb:rangers","ar":"رينجرز","short":"RAN","reuse":null},
    {"ext":"drb:galatasaray","ar":"غلطة سراي","short":"GAL","reuse":null},
    {"ext":"drb:fenerbahce","ar":"فنربخشة","short":"FEN","reuse":null},
    {"ext":"drb:besiktas","ar":"بشكتاش","short":"BES","reuse":null},
    {"ext":"drb:olympiacos","ar":"أولمبياكوس","short":"OLY","reuse":null},
    {"ext":"drb:panathinaikos","ar":"باناثينايكوس","short":"PAO","reuse":null},
    {"ext":"drb:ajax","ar":"أياكس","short":"AJA","reuse":null},
    {"ext":"drb:feyenoord","ar":"فينورد","short":"FEY","reuse":null},
    {"ext":"drb:benfica","ar":"بنفيكا","short":"BEN","reuse":{"source":"club_world_cup","ext":"cwc:benfica"}},
    {"ext":"drb:sporting","ar":"سبورتينغ لشبونة","short":"SCP","reuse":null}
  ]'::jsonb;
begin
  for r in select * from jsonb_array_elements(teams) as t(obj)
  loop
    select canonical_id into v_team_id
    from football_data.external_identity_map
    where external_source = 'big_derbies'
      and external_id = (r.obj->>'ext')
      and canonical_table = 'team';

    if v_team_id is not null then
      -- Already recorded by an earlier run. A reused club keeps the name its
      -- own source gave it, so only a club this migration created is held to
      -- the name above.
      if r.obj->'reuse' = 'null'::jsonb then
        select name into v_existing_name
        from football_data.teams
        where id = v_team_id;
        if lower(btrim(v_existing_name)) is distinct from lower(btrim(r.obj->>'ar')) then
          raise exception 'Big derbies identity % already points to team % named %, expected %',
            r.obj->>'ext', v_team_id, v_existing_name, r.obj->>'ar';
        end if;
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
      order by created_at, id
      limit 1;
    end if;

    if v_team_id is null then
      insert into football_data.teams (name, short_name, crest_url)
      values (r.obj->>'ar', r.obj->>'short', null)
      returning id into v_team_id;
    end if;

    insert into football_data.external_identity_map
      (external_source, external_id, canonical_table, canonical_id)
    values ('big_derbies', r.obj->>'ext', 'team', v_team_id);
  end loop;
end
$$;

insert into ops.applied_migrations (version)
values ('0104_big_derbies')
on conflict (version) do nothing;

commit;

-- Verification (expects 1 league, continental, and 31 clubs):
-- select name, is_continental from football_data.leagues where name = 'ديربيات كبرى';
-- select count(*) from football_data.external_identity_map where external_source = 'big_derbies';
