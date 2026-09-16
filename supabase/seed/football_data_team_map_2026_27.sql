-- ============================================================
-- Nukhba — Seed: football-data.org team identities (season 2026/27)
-- NOT a migration: production data, applied by hand like the other seeds.
--
-- football-data.org (free tier, 10 calls/minute, no daily cap) serves the
-- Premier League, Champions League, Bundesliga, La Liga and Serie A;
-- Highlightly keeps the Roshan League, Europa League and League Cup
-- (decided 2026-09-17). Every club of those five competitions is mapped in
-- football_data.external_identity_map with external_source = 'football-data'
-- to the SAME catalog team its Highlightly id already maps to
-- (supabase/seed/highlightly_team_map_2026_27.sql must be applied first).
-- Team ids come from the provider's /competitions/{code}/teams (2026-09-17).
--
-- Additive and idempotent. Expected result (96):
--   select count(*) from football_data.external_identity_map
--    where external_source = 'football-data' and canonical_table = 'team';
-- ============================================================

insert into football_data.external_identity_map
  (external_source, external_id, canonical_table, canonical_id)
select 'football-data', v.fd, 'team', m.canonical_id
from (values
  ('1044','30569'),
  ('57','36526'),
  ('58','56950'),
  ('402','47589'),
  ('397','44185'),
  ('61','42483'),
  ('1076','1146230'),
  ('354','45036'),
  ('62','39079'),
  ('63','31420'),
  ('322','55248'),
  ('349','49291'),
  ('341','54397'),
  ('64','34824'),
  ('65','43334'),
  ('66','28867'),
  ('67','29718'),
  ('351','56099'),
  ('71','635630'),
  ('73','40781'),
  ('1','164176'),
  ('28','155666'),
  ('15','140348'),
  ('3','143752'),
  ('4','141199'),
  ('18','139497'),
  ('19','144603'),
  ('16','145454'),
  ('5','134391'),
  ('6','148858'),
  ('7','149709'),
  ('721','148007'),
  ('17','136944'),
  ('29','158219'),
  ('719','1413444'),
  ('12','138646'),
  ('2','142901'),
  ('10','147156'),
  ('77','452665'),
  ('79','619461'),
  ('78','451814'),
  ('263','462026'),
  ('285','679031'),
  ('81','450963'),
  ('82','465430'),
  ('88','459473'),
  ('84','456069'),
  ('558','458622'),
  ('560','463728'),
  ('80','460324'),
  ('87','620312'),
  ('90','462877'),
  ('86','461175'),
  ('5335','3970699'),
  ('92','467132'),
  ('559','456920'),
  ('95','453516'),
  ('94','454367'),
  ('98','416923'),
  ('5911','1344513'),
  ('99','427986'),
  ('100','423731'),
  ('102','425433'),
  ('103','426284'),
  ('104','417774'),
  ('7397','762429'),
  ('108','430539'),
  ('470','436496'),
  ('107','422029'),
  ('109','422880'),
  ('112','445857'),
  ('110','415221'),
  ('113','419476'),
  ('586','428837'),
  ('5890','738601'),
  ('471','416072'),
  ('115','421178'),
  ('454','440751'),
  ('851','485003'),
  ('503','181196'),
  ('5721','279061'),
  ('1887','468834'),
  ('613','520745'),
  ('675','178643'),
  ('610','549679'),
  ('2016','873910'),
  ('521','68013'),
  ('1899','490109'),
  ('674','168431'),
  ('524','73119'),
  ('546','99500'),
  ('930','477344'),
  ('10233','11894360'),
  ('498','194812'),
  ('5720','646693'),
  ('7509','559040')
) as v(fd, hl)
join football_data.external_identity_map m
  on m.external_source = 'highlightly'
 and m.canonical_table = 'team'
 and m.external_id = v.hl
on conflict (external_source, external_id, canonical_table) do nothing;
