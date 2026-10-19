-- ============================================================================
-- Migration 0180: the UEFA Conference League
--
-- ADDITIVE ONLY. One new row in football_data.leagues. No match,
-- prediction, point, ledger, fixture or team row is touched.
--
-- دوري المؤتمر الأوروبي (UEFA Conference League, short UECL) is
-- is_continental = true, as 0038, 0103 and 0105 set for a competition that
-- draws its clubs from other leagues: the admin picker offers the whole
-- catalog, no club is tagged to it, and its fixtures are added by an admin,
-- not by the provider sync (decided with the owner 2026-10-20). A club the
-- catalog lacks is added from the admin panel, as for any competition.
--
-- The league header shows the bundled mark
-- assets/league_logos/conference-league.png by this name
-- (kLeagueLogoAssetsByName), so logo_url stays NULL.
--
-- Forward-only, guarded. Safe to re-run.
-- ============================================================================

begin;

insert into football_data.leagues (name, short_name, is_continental)
select 'دوري المؤتمر الأوروبي', 'UECL', true
where not exists (
  select 1
  from football_data.leagues l
  where btrim(l.name) = 'دوري المؤتمر الأوروبي'
);

insert into ops.applied_migrations (version)
values ('0180_conference_league')
on conflict (version) do nothing;

commit;

-- Verification (expects one continental row):
-- select name, short_name, is_continental from football_data.leagues
--  where btrim(name) = 'دوري المؤتمر الأوروبي';
