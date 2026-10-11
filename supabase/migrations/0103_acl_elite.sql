-- ============================================================================
-- Migration 0103: AFC Champions League Elite (دوري أبطال آسيا للنخبة)
--
-- ADDITIVE ONLY. One new row in football_data.leagues and the clubs of the
-- 2026-27 league stage (checked 2026-10-11 against
-- en.wikipedia.org/wiki/2026–27_AFC_Champions_League_Elite: 16 West, 16
-- East). No match, prediction, point, ledger or fixture row is touched.
--
-- ## The league
-- is_continental = true, as migration 0038 set for every competition that
-- draws its entrants from other leagues: the admin picker offers the whole
-- catalog under it, and no club is tagged to it. Fixtures are added by an
-- admin (decided with the owner 2026-10-11), not by the provider sync.
--
-- ## The clubs
-- The five Saudi clubs and Al Ain are reused (saudi seed, 0050); the other
-- 26 are created with Arabic names, league_id NULL and crest NULL (the app
-- shows initials until a crest is added). East clubs are included so a
-- West-East tie (the final) shows both names from the catalog. Each club is
-- recorded in external_identity_map under the source 'acl_elite', so a
-- re-run creates nothing twice; a club already in the catalog under the
-- same name is reused rather than duplicated.
--
-- Forward-only, guarded. Safe to re-run.
-- ============================================================================

begin;

insert into football_data.leagues (name, short_name, is_continental)
select 'دوري أبطال آسيا للنخبة', 'ACLE', true
where not exists (
  select 1
  from football_data.leagues l
  where btrim(l.name) = 'دوري أبطال آسيا للنخبة'
);

do $$
declare
  r record;
  v_team_id uuid;
  v_existing_name text;
  v_reuse_source text;
  v_reuse_ext text;
  teams jsonb := '[
    {"ext":"acle:hil","ar":"الهلال","short":"HIL","reuse":{"source":"saudi","ext":"saudi:hil"}},
    {"ext":"acle:itt","ar":"الاتحاد","short":"ITT","reuse":{"source":"saudi","ext":"saudi:itt"}},
    {"ext":"acle:nas","ar":"النصر","short":"NAS","reuse":{"source":"saudi","ext":"saudi:nas"}},
    {"ext":"acle:ahl","ar":"الأهلي","short":"AHL","reuse":{"source":"saudi","ext":"saudi:ahl"}},
    {"ext":"acle:qad","ar":"القادسية","short":"QAD","reuse":{"source":"saudi","ext":"saudi:qad"}},
    {"ext":"acle:ain","ar":"العين","short":"AIN","reuse":{"source":"club_world_cup","ext":"cwc:al-ain"}},
    {"ext":"acle:was","ar":"الوصل","short":"WAS","reuse":null},
    {"ext":"acle:sab","ar":"شباب الأهلي","short":"SAB","reuse":null},
    {"ext":"acle:sad","ar":"السد","short":"SAD","reuse":null},
    {"ext":"acle:gha","ar":"الغرافة","short":"GHA","reuse":null},
    {"ext":"acle:sha","ar":"الشمال","short":"SHM","reuse":null},
    {"ext":"acle:est","ar":"استقلال طهران","short":"EST","reuse":null},
    {"ext":"acle:tra","ar":"تراكتور","short":"TRA","reuse":null},
    {"ext":"acle:nef","ar":"نفتشي فرغانة","short":"NEF","reuse":null},
    {"ext":"acle:pak","ar":"باختاكور","short":"PAK","reuse":null},
    {"ext":"acle:qwj","ar":"القوة الجوية","short":"QWJ","reuse":null},
    {"ext":"acle:gam","ar":"غامبا أوساكا","short":"GAM","reuse":null},
    {"ext":"acle:kas","ar":"كاشيما أنتلرز","short":"KAS","reuse":null},
    {"ext":"acle:ksw","ar":"كاشيوا ريسول","short":"KSW","reuse":null},
    {"ext":"acle:kyo","ar":"كيوتو سانغا","short":"KYO","reuse":null},
    {"ext":"acle:vis","ar":"فيسيل كوبي","short":"VIS","reuse":null},
    {"ext":"acle:dae","ar":"دايجون هانا سيتيزن","short":"DAE","reuse":null},
    {"ext":"acle:jeo","ar":"جيونبوك هيونداي موتورز","short":"JEO","reuse":null},
    {"ext":"acle:poh","ar":"بوهانغ ستيلرز","short":"POH","reuse":null},
    {"ext":"acle:bur","ar":"بوريرام يونايتد","short":"BUR","reuse":null},
    {"ext":"acle:prt","ar":"بورت إف سي","short":"PRT","reuse":null},
    {"ext":"acle:rat","ar":"راتشابوري","short":"RAT","reuse":null},
    {"ext":"acle:bei","ar":"بكين غوان","short":"BEI","reuse":null},
    {"ext":"acle:shp","ar":"شنغهاي بورت","short":"SHP","reuse":null},
    {"ext":"acle:new","ar":"نيوكاسل جيتس","short":"NEW","reuse":null},
    {"ext":"acle:jdt","ar":"جوهور دار التعظيم","short":"JDT","reuse":null},
    {"ext":"acle:cah","ar":"كونغ آن هانوي","short":"CAH","reuse":null}
  ]'::jsonb;
begin
  for r in select * from jsonb_array_elements(teams) as t(obj)
  loop
    select canonical_id into v_team_id
    from football_data.external_identity_map
    where external_source = 'acl_elite'
      and external_id = (r.obj->>'ext')
      and canonical_table = 'team';

    if v_team_id is not null then
      select name into v_existing_name
      from football_data.teams
      where id = v_team_id;
      if v_existing_name is distinct from (r.obj->>'ar') then
        raise exception 'ACL Elite identity % already points to team % named %, expected %',
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
    values ('acl_elite', r.obj->>'ext', 'team', v_team_id);
  end loop;
end
$$;

insert into ops.applied_migrations (version)
values ('0103_acl_elite')
on conflict (version) do nothing;

commit;

-- Verification (expects 1 league, continental, and 32 clubs):
-- select name, is_continental from football_data.leagues where name = 'دوري أبطال آسيا للنخبة';
-- select count(*) from football_data.external_identity_map where external_source = 'acl_elite';
