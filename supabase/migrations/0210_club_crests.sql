-- ============================================================================
-- Migration 0210: the clubs' crests leave the app for a list the owner
-- controls (script 265)
--
-- ADDITIVE ONLY. A new schema with three tables, one Storage bucket and the
-- crests' rows; no existing row is changed or removed.
--
-- Decided by the owner on 2026-11-11, before the Google Play release: the
-- clubs' crests are their owners' marks. They no longer ship inside the
-- app (script 266) and no longer leave it (the publisher is gone, 260): the
-- app reads, on every start, a list of the crests it may show (`GET
-- /crests`) and downloads them from the public bucket `crests`. The owner
-- admin alone hides one at once (a complaint), shows it again, deletes it
-- for good (the file is erased), or turns every club crest off. The
-- countries' flags stay inside the app: they are not marks.
--
-- 1. media.club_crests: one row per club crest -- its slug (the app's file
--    name), its Storage path (`clubs/<slug>.<first 8 hex of its sha256>.png`,
--    so a new file is a new URL and no cache keeps an old one), its status
--    (`active`, `hidden`, `deleted`) and why.
-- 2. media.crest_settings: one row, whether club crests show at all.
-- 3. media.crest_events: every change, with its reason and complainant.
-- 4. storage.buckets `crests`: public files (read by URL), PNG, 256 KB at
--    most. Listing them needs a policy on storage.objects, which no one has.
-- 5. The 235 club crests of the app, active.
--
-- Server only (no grant to anon or authenticated). Safe to re-run.
-- ============================================================================

begin;

create schema if not exists media;
revoke all on schema media from anon, authenticated;

create table if not exists media.club_crests (
  slug text primary key check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  object_path text not null unique,
  status text not null default 'active'
    check (status in ('active', 'hidden', 'deleted')),
  reason text,
  complainant text,
  changed_at timestamptz,
  changed_by uuid references identity.users (id) on delete set null
);

create table if not exists media.crest_settings (
  id boolean primary key default true check (id),
  clubs_enabled boolean not null default true,
  changed_at timestamptz,
  changed_by uuid references identity.users (id) on delete set null
);

insert into media.crest_settings (id) values (true)
on conflict (id) do nothing;

create table if not exists media.crest_events (
  id bigserial primary key,
  slug text,
  action text not null
    check (action in ('hidden', 'shown', 'deleted', 'clubs_on', 'clubs_off')),
  reason text not null check (btrim(reason) <> ''),
  complainant text,
  actor_id uuid references identity.users (id) on delete set null,
  at timestamptz not null default now()
);

create index if not exists crest_events_at_idx
  on media.crest_events (at desc);

alter table media.club_crests enable row level security;
alter table media.crest_settings enable row level security;
alter table media.crest_events enable row level security;
revoke all on media.club_crests from anon, authenticated;
revoke all on media.crest_settings from anon, authenticated;
revoke all on media.crest_events from anon, authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('crests', 'crests', true, 262144, array['image/png'])
on conflict (id) do nothing;

insert into media.club_crests (slug, object_path) values
  ('abha', 'clubs/abha.324837b0.png'),
  ('aek-athens', 'clubs/aek-athens.f77af118.png'),
  ('agf', 'clubs/agf.78aed776.png'),
  ('ajax', 'clubs/ajax.18df1a97.png'),
  ('al-ahli', 'clubs/al-ahli.27155ba4.png'),
  ('al-ahly', 'clubs/al-ahly.c93bb565.png'),
  ('al-ain', 'clubs/al-ain.1fa15832.png'),
  ('al-ettifaq', 'clubs/al-ettifaq.ec7c5da2.png'),
  ('al-faisaly-amman', 'clubs/al-faisaly-amman.71583322.png'),
  ('al-faisaly', 'clubs/al-faisaly.52a0dc5c.png'),
  ('al-fateh', 'clubs/al-fateh.9053ce9e.png'),
  ('al-fayha', 'clubs/al-fayha.cc376317.png'),
  ('al-gharafa', 'clubs/al-gharafa.0f4a9898.png'),
  ('al-hazem', 'clubs/al-hazem.8b66c8a5.png'),
  ('al-hilal-omdurman', 'clubs/al-hilal-omdurman.49e360b2.png'),
  ('al-hilal', 'clubs/al-hilal.a0f4cec7.png'),
  ('al-ittihad', 'clubs/al-ittihad.402ee176.png'),
  ('al-khaleej', 'clubs/al-khaleej.ffe3ead0.png'),
  ('al-kholood', 'clubs/al-kholood.da151eb8.png'),
  ('al-merrikh', 'clubs/al-merrikh.3457f9d6.png'),
  ('al-nassr', 'clubs/al-nassr.93ffe484.png'),
  ('al-qadsiah', 'clubs/al-qadsiah.d4b86c20.png'),
  ('al-quwa-al-jawiya', 'clubs/al-quwa-al-jawiya.175a2545.png'),
  ('al-riyadh', 'clubs/al-riyadh.77e95d32.png'),
  ('al-sadd', 'clubs/al-sadd.380ea4db.png'),
  ('al-shabab', 'clubs/al-shabab.01f0a660.png'),
  ('al-shamal', 'clubs/al-shamal.228580d5.png'),
  ('al-taawoun', 'clubs/al-taawoun.c742abd9.png'),
  ('al-wasl', 'clubs/al-wasl.5dd512e6.png'),
  ('al-wehdat', 'clubs/al-wehdat.fc2691b1.png'),
  ('al-zawraa', 'clubs/al-zawraa.1ef8de95.png'),
  ('alaves', 'clubs/alaves.29f35ebc.png'),
  ('anderlecht', 'clubs/anderlecht.b332cc00.png'),
  ('angers', 'clubs/angers.76f6680c.png'),
  ('ararat-armenia', 'clubs/ararat-armenia.1d382598.png'),
  ('arsenal', 'clubs/arsenal.c031bbff.png'),
  ('aston-villa', 'clubs/aston-villa.c7191168.png'),
  ('atalanta', 'clubs/atalanta.b89cf893.png'),
  ('athletic-club', 'clubs/athletic-club.9f5e3caf.png'),
  ('atletico-atlanta', 'clubs/atletico-atlanta.df5c12f9.png'),
  ('atletico-madrid', 'clubs/atletico-madrid.b5e99105.png'),
  ('auckland-city-fc', 'clubs/auckland-city-fc.81ebf528.png'),
  ('auckland-fc', 'clubs/auckland-fc.aa95c265.png'),
  ('augsburg', 'clubs/augsburg.839fbfd4.png'),
  ('auxerre', 'clubs/auxerre.383c8521.png'),
  ('az-alkmaar', 'clubs/az-alkmaar.157a57a0.png'),
  ('barcelona', 'clubs/barcelona.c7aafddc.png'),
  ('bayer-leverkusen', 'clubs/bayer-leverkusen.34c40cb5.png'),
  ('bayern-munchen', 'clubs/bayern-munchen.354df64b.png'),
  ('benfica', 'clubs/benfica.fbb6bdfc.png'),
  ('besiktas', 'clubs/besiktas.6b7fb081.png'),
  ('boca-juniors', 'clubs/boca-juniors.e911d89f.png'),
  ('bodo-glimt', 'clubs/bodo-glimt.888cf572.png'),
  ('bologna', 'clubs/bologna.3894dac5.png'),
  ('borac', 'clubs/borac.43362044.png'),
  ('borussia-dortmund', 'clubs/borussia-dortmund.c405ad83.png'),
  ('borussia-monchengladbach', 'clubs/borussia-monchengladbach.a7ea7cb8.png'),
  ('botafogo', 'clubs/botafogo.650f4025.png'),
  ('bournemouth', 'clubs/bournemouth.ca27724a.png'),
  ('brann', 'clubs/brann.fd2400ea.png'),
  ('brentford', 'clubs/brentford.eb82e250.png'),
  ('brest', 'clubs/brest.7df809c5.png'),
  ('brighton', 'clubs/brighton.cbd6c353.png'),
  ('cagliari', 'clubs/cagliari.d26f893d.png'),
  ('celje', 'clubs/celje.4fed0908.png'),
  ('celta', 'clubs/celta.25edda54.png'),
  ('celtic', 'clubs/celtic.8556d025.png'),
  ('chelsea', 'clubs/chelsea.f417fb45.png'),
  ('club-africain', 'clubs/club-africain.0a74b9f5.png'),
  ('club-brugge', 'clubs/club-brugge.fa81c334.png'),
  ('como-1907', 'clubs/como-1907.fcc09de1.png'),
  ('copenhagen', 'clubs/copenhagen.a924c943.png'),
  ('coventry-city', 'clubs/coventry-city.745aed60.png'),
  ('crvena-zvezda', 'clubs/crvena-zvezda.ea67d895.png'),
  ('crystal-palace', 'clubs/crystal-palace.2a0e6f31.png'),
  ('cska-sofia', 'clubs/cska-sofia.96fa8f47.png'),
  ('deportivo-la-coruna', 'clubs/deportivo-la-coruna.ab352a20.png'),
  ('deportivo', 'clubs/deportivo.b6557f63.png'),
  ('dinamo-zagreb', 'clubs/dinamo-zagreb.d3bc8c6d.png'),
  ('diriyah', 'clubs/diriyah.bade3ef1.png'),
  ('egnatia', 'clubs/egnatia.f0094786.png'),
  ('eintracht-frankfurt', 'clubs/eintracht-frankfurt.6db571d7.png'),
  ('elche', 'clubs/elche.0b633832.png'),
  ('espanyol', 'clubs/espanyol.88eb4d4f.png'),
  ('esperance', 'clubs/esperance.6b53182e.png'),
  ('esteghlal', 'clubs/esteghlal.f16e0ecd.png'),
  ('everton', 'clubs/everton.9749c766.png'),
  ('fc-porto', 'clubs/fc-porto.7f4b2c9e.png'),
  ('fenerbahce', 'clubs/fenerbahce.17e27439.png'),
  ('ferencvaros', 'clubs/ferencvaros.47674632.png'),
  ('feyenoord', 'clubs/feyenoord.59362b18.png'),
  ('fiorentina', 'clubs/fiorentina.d0a5175f.png'),
  ('flamengo', 'clubs/flamengo.77242cbe.png'),
  ('fluminense', 'clubs/fluminense.41c1fb33.png'),
  ('freiburg', 'clubs/freiburg.8433cde0.png'),
  ('frosinone', 'clubs/frosinone.50daf9fa.png'),
  ('fulham', 'clubs/fulham.39f7427d.png'),
  ('galatasaray', 'clubs/galatasaray.20e48d3c.png'),
  ('genoa', 'clubs/genoa.db5bbcdb.png'),
  ('gent', 'clubs/gent.9d9c98ed.png'),
  ('getafe', 'clubs/getafe.988b8801.png'),
  ('hajduk-split', 'clubs/hajduk-split.1c08f544.png'),
  ('hamburger-sv', 'clubs/hamburger-sv.cd5aafa7.png'),
  ('hearts', 'clubs/hearts.8ea89856.png'),
  ('hoffenheim', 'clubs/hoffenheim.1ef75fae.png'),
  ('hull-city', 'clubs/hull-city.df693552.png'),
  ('iberia', 'clubs/iberia.d10347bd.png'),
  ('inter-escaldes', 'clubs/inter-escaldes.5cdf3711.png'),
  ('inter-miami-cf', 'clubs/inter-miami-cf.34d49e2f.png'),
  ('inter', 'clubs/inter.f4f806ce.png'),
  ('ipswich', 'clubs/ipswich.a99337f2.png'),
  ('jablonec', 'clubs/jablonec.3f4788f2.png'),
  ('jagiellonia', 'clubs/jagiellonia.d875dd3d.png'),
  ('johor-darul-tazim', 'clubs/johor-darul-tazim.592d6a6b.png'),
  ('juventus', 'clubs/juventus.60a27e16.png'),
  ('kairat', 'clubs/kairat.e4f57e61.png'),
  ('kauno-zalgiris', 'clubs/kauno-zalgiris.b8317a98.png'),
  ('koln', 'clubs/koln.cf0c193b.png'),
  ('kups', 'clubs/kups.753df9ed.png'),
  ('lask', 'clubs/lask.35073a83.png'),
  ('lazio', 'clubs/lazio.dbae9b4d.png'),
  ('le-havre', 'clubs/le-havre.67267efa.png'),
  ('le-mans', 'clubs/le-mans.c8444f7c.png'),
  ('lecce', 'clubs/lecce.9503a27a.png'),
  ('lech-poznan', 'clubs/lech-poznan.32392ee4.png'),
  ('leeds-united', 'clubs/leeds-united.48ab3b90.png'),
  ('levante', 'clubs/levante.5d92b049.png'),
  ('levski', 'clubs/levski.5f31d41e.png'),
  ('lille', 'clubs/lille.72692c8c.png'),
  ('lillestrom', 'clubs/lillestrom.65fc6cdb.png'),
  ('lincoln-red-imps', 'clubs/lincoln-red-imps.25b6c876.png'),
  ('liverpool', 'clubs/liverpool.40f16f97.png'),
  ('lorient', 'clubs/lorient.d6c4a869.png'),
  ('los-angeles-fc', 'clubs/los-angeles-fc.d20e86de.png'),
  ('lugano', 'clubs/lugano.232c71a4.png'),
  ('lyon', 'clubs/lyon.59cac00c.png'),
  ('mainz-05', 'clubs/mainz-05.236b48ff.png'),
  ('malaga', 'clubs/malaga.ebbdd8c1.png'),
  ('mamelodi-sundowns', 'clubs/mamelodi-sundowns.dd9d1ff7.png'),
  ('manchester-city', 'clubs/manchester-city.99debcb0.png'),
  ('manchester-united', 'clubs/manchester-united.eaf320fd.png'),
  ('marseille', 'clubs/marseille.6495b67e.png'),
  ('mc-alger', 'clubs/mc-alger.b09234f4.png'),
  ('midtjylland', 'clubs/midtjylland.223add08.png'),
  ('milan', 'clubs/milan.a2e6ec63.png'),
  ('mjallby', 'clubs/mjallby.a3560427.png'),
  ('monaco', 'clubs/monaco.1a46b113.png'),
  ('monterrey', 'clubs/monterrey.9be1ffae.png'),
  ('monza', 'clubs/monza.610ed6c8.png'),
  ('napoli', 'clubs/napoli.720bbd0a.png'),
  ('nec-nijmegen', 'clubs/nec-nijmegen.65b962a2.png'),
  ('neftchi-fergana', 'clubs/neftchi-fergana.7c2b8fe9.png'),
  ('neom', 'clubs/neom.e7880896.png'),
  ('newcastle', 'clubs/newcastle.42a24684.png'),
  ('nice', 'clubs/nice.caaeeb84.png'),
  ('nordsjaelland', 'clubs/nordsjaelland.899819e4.png'),
  ('nottingham-forest', 'clubs/nottingham-forest.ddc4d5c7.png'),
  ('ofi', 'clubs/ofi.37de1d27.png'),
  ('olympiacos', 'clubs/olympiacos.897ea6d2.png'),
  ('omonoia', 'clubs/omonoia.5bcd6647.png'),
  ('orlando-pirates', 'clubs/orlando-pirates.a28e5477.png'),
  ('osasuna', 'clubs/osasuna.d89fb658.png'),
  ('pachuca', 'clubs/pachuca.f6095be9.png'),
  ('paderborn', 'clubs/paderborn.8267a9f7.png'),
  ('pafos', 'clubs/pafos.3fe2747b.png'),
  ('pakhtakor', 'clubs/pakhtakor.20c3ee91.png'),
  ('palmeiras', 'clubs/palmeiras.9169f352.png'),
  ('panathinaikos', 'clubs/panathinaikos.002925c7.png'),
  ('paris-fc', 'clubs/paris-fc.d6d7616b.png'),
  ('paris-saint-germain', 'clubs/paris-saint-germain.daeda21a.png'),
  ('parma', 'clubs/parma.3964f4d8.png'),
  ('persepolis', 'clubs/persepolis.8d49be74.png'),
  ('psv', 'clubs/psv.4bd99c3a.png'),
  ('pyramids', 'clubs/pyramids.80a95b15.png'),
  ('racing', 'clubs/racing.17bbb483.png'),
  ('raja-casablanca', 'clubs/raja-casablanca.6abe50cd.png'),
  ('rangers', 'clubs/rangers.de1ef688.png'),
  ('rayo-vallecano', 'clubs/rayo-vallecano.6b52ce1c.png'),
  ('rb-leipzig', 'clubs/rb-leipzig.845410c5.png'),
  ('rc-lens', 'clubs/rc-lens.0193aca6.png'),
  ('real-betis', 'clubs/real-betis.62ee278f.png'),
  ('real-madrid', 'clubs/real-madrid.e3124d64.png'),
  ('real-sociedad', 'clubs/real-sociedad.d4fbbe1f.png'),
  ('rennes', 'clubs/rennes.cac321dd.png'),
  ('riga', 'clubs/riga.046eef51.png'),
  ('river-plate', 'clubs/river-plate.162fb31f.png'),
  ('roma', 'clubs/roma.fbd0875a.png'),
  ('rs-berkane', 'clubs/rs-berkane.a9ff54bc.png'),
  ('s-bratislava', 'clubs/s-bratislava.8a7c26db.png'),
  ('sabah', 'clubs/sabah.2ab988b6.png'),
  ('salzburg', 'clubs/salzburg.80061f64.png'),
  ('sassuolo', 'clubs/sassuolo.7982814c.png'),
  ('sc-braga', 'clubs/sc-braga.541205c0.png'),
  ('schalke-04', 'clubs/schalke-04.b0c7f801.png'),
  ('seattle-sounders-fc', 'clubs/seattle-sounders-fc.2fa82bc0.png'),
  ('sevilla', 'clubs/sevilla.61c717f6.png'),
  ('shabab-al-ahli', 'clubs/shabab-al-ahli.3213f93f.png'),
  ('shakhtar', 'clubs/shakhtar.3d77e742.png'),
  ('shanghai-port', 'clubs/shanghai-port.6afe4d3a.png'),
  ('simba', 'clubs/simba.6fd34707.png'),
  ('sint-truidense', 'clubs/sint-truidense.4c4a16e5.png'),
  ('slavia-praha', 'clubs/slavia-praha.b267d587.png'),
  ('sparta-praha', 'clubs/sparta-praha.5018c5da.png'),
  ('sporting-cp', 'clubs/sporting-cp.7caaf12a.png'),
  ('strasbourg', 'clubs/strasbourg.dda45ee7.png'),
  ('sturm-graz', 'clubs/sturm-graz.1fab1a04.png'),
  ('sunderland', 'clubs/sunderland.f568d3d0.png'),
  ('sv-elversberg', 'clubs/sv-elversberg.0b70db21.png'),
  ('thun', 'clubs/thun.6abdae3c.png'),
  ('torino', 'clubs/torino.38da4c0f.png'),
  ('torreense', 'clubs/torreense.258bdb6d.png'),
  ('tottenham', 'clubs/tottenham.e9b8786a.png'),
  ('toulouse', 'clubs/toulouse.749271af.png'),
  ('trabzonspor', 'clubs/trabzonspor.de90524d.png'),
  ('tractor', 'clubs/tractor.136311db.png'),
  ('troyes', 'clubs/troyes.b62d6793.png'),
  ('twente', 'clubs/twente.8037bc74.png'),
  ('u-craiova', 'clubs/u-craiova.e0a855c8.png'),
  ('udinese', 'clubs/udinese.95ccab40.png'),
  ('ulsan-hd-fc', 'clubs/ulsan-hd-fc.d255640b.png'),
  ('union-berlin', 'clubs/union-berlin.16c6dea6.png'),
  ('union-saint-gilloise', 'clubs/union-saint-gilloise.ced3ca06.png'),
  ('urawa-reds', 'clubs/urawa-reds.95a9fb17.png'),
  ('usm-alger', 'clubs/usm-alger.8d237117.png'),
  ('valencia', 'clubs/valencia.46db3bc3.png'),
  ('venezia', 'clubs/venezia.4530dcdb.png'),
  ('vfb-stuttgart', 'clubs/vfb-stuttgart.6e523236.png'),
  ('viking', 'clubs/viking.403d8bd9.png'),
  ('viktoria-plzen', 'clubs/viktoria-plzen.e4cec15e.png'),
  ('villarreal', 'clubs/villarreal.dafd8eee.png'),
  ('vissel-kobe', 'clubs/vissel-kobe.b1a9f1e6.png'),
  ('werder-bremen', 'clubs/werder-bremen.486352b4.png'),
  ('wydad-ac', 'clubs/wydad-ac.7150524c.png'),
  ('young-africans', 'clubs/young-africans.1060fefd.png'),
  ('zamalek', 'clubs/zamalek.9634b777.png')
on conflict (slug) do nothing;

insert into ops.applied_migrations (version)
values ('0210_club_crests')
on conflict (version) do nothing;

commit;

-- Verification (read-only):
-- select version from ops.applied_migrations
--  where version = '0210_club_crests';                                -- 1 row
-- select status, count(*) from media.club_crests group by status;   -- active 235
-- select id, public from storage.buckets where id = 'crests';        -- crests t
