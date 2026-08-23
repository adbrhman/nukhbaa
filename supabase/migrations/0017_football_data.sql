-- =====================================================================
-- Football Data bounded context (Database ADR §2.2, §3, Axiom 3).
--
-- Scope decision for this batch: `team`, `fixture`, `fixture_result`,
-- and the ACL external-identity mapping table only. `tournament` and
-- `tournament_edition` (also listed as Football Data-owned in ADR-003
-- §2.2) are DEFERRED as documented technical debt: nothing in the
-- current v1 UI consumes tournament-level metadata, and `competition.*`
-- already covers the equivalent concept internally. Adding them now
-- would be dead schema. Revisit if/when an external provider's
-- tournament shape is actually needed.
--
-- The fixture table carries NO competition reference (enforced
-- structurally by omitting the column, per ADR-003 §2.2) and NO
-- provider reference (per ADR-002 §2.10/Axiom 3: manual admin entry
-- is modeled as just another provider behind the ACL, so the fixture
-- shape itself must stay provider-agnostic). Provenance of who/what
-- created a given fixture lives ONLY in the external-identity mapping
-- table below, never on `fixtures` itself.
-- =====================================================================

create schema if not exists football_data;

-- ---------------------------------------------------------------------
-- teams — slowly-changing reference aggregate (Database ADR §2.2).
-- ---------------------------------------------------------------------
create table if not exists football_data.teams (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  short_name  text,
  crest_url   text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint teams_name_not_blank check (btrim(name) <> '')
);

comment on table football_data.teams is
  'Football Data-owned. Canonical team identity, provideragnostic. '
  'Populated today via manual admin entry (see external_identity_map); '
  'may be populated by an automated provider later without this table '
  'changing shape.';

drop trigger if exists teams_set_updated_at on football_data.teams;
create trigger teams_set_updated_at
  before update on football_data.teams
  for each row
  execute function identity.set_updated_at();

-- ---------------------------------------------------------------------
-- fixtures — the universal fact (Axiom 3). No competition_id, no
-- provider_id: both would violate the single-minimal-seam design.
-- ---------------------------------------------------------------------
create table if not exists football_data.fixtures (
  id            uuid primary key default gen_random_uuid(),
  home_team_id  uuid not null references football_data.teams (id) on delete restrict,
  away_team_id  uuid not null references football_data.teams (id) on delete restrict,
  kickoff_at    timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint fixtures_distinct_teams check (home_team_id <> away_team_id)
);

comment on table football_data.fixtures is
  'Football Data-owned universal fact (Axiom 3: single minimal football '
  'seam). Referenced by competition.round_fixtures.fixture_id and '
  'prediction.prediction_scores.fixture_id, both previously opaque UUID '
  'columns with no FK (see 0002_competition.sql, 0003_prediction.sql) — '
  'this migration adds the FK now that the owning table exists.';

create index if not exists fixtures_home_team_idx
  on football_data.fixtures (home_team_id);
create index if not exists fixtures_away_team_idx
  on football_data.fixtures (away_team_id);

drop trigger if exists fixtures_set_updated_at on football_data.fixtures;
create trigger fixtures_set_updated_at
  before update on football_data.fixtures
  for each row
  execute function identity.set_updated_at();

-- ---------------------------------------------------------------------
-- fixture_results — same home/away goal-pair shape as a prediction
-- (prediction.fixture_score_prediction), so scoring stays a straight
-- comparison of two identically-shaped outcomes (Axiom 3).
-- ---------------------------------------------------------------------
create table if not exists football_data.fixture_results (
  fixture_id   uuid primary key references football_data.fixtures (id) on delete restrict,
  home_goals   integer not null check (home_goals >= 0),
  away_goals   integer not null check (away_goals >= 0),
  recorded_at  timestamptz not null default now()
);

comment on table football_data.fixture_results is
  'Football Data-owned. Append-once per fixture (admin ingests the '
  'actual result); no updated_at trigger by design — a correction is a '
  'delete+reinsert via the admin API so the audit trail (Admin ADR / '
  '0010_admin.sql AuditAction.fixture_result_recorded) always reflects '
  'an explicit admin action, never a silent update.';

-- ---------------------------------------------------------------------
-- external_identity_map — the ACL (Application ADR §2.10/§2.12).
-- Manual admin entry is modeled as just another provider: rows with
-- external_source = 'manual_admin' and external_id = the admin-chosen
-- free-text key are exactly as valid as rows from a future automated
-- provider. Reconciliation (external_source + external_id ->
-- canonical_id) happens ONLY here — no other table may encode provider
-- identity.
-- ---------------------------------------------------------------------
create table if not exists football_data.external_identity_map (
  id               uuid primary key default gen_random_uuid(),
  external_source  text not null,
  external_id      text not null,
  canonical_table  text not null check (canonical_table in ('team', 'fixture')),
  canonical_id     uuid not null,
  created_at       timestamptz not null default now(),
  constraint external_identity_map_unique
    unique (external_source, external_id, canonical_table)
);

comment on table football_data.external_identity_map is
  'ACL identity resolution (Application ADR §2.10). Maps '
  '(external_source, external_id) -> canonical team/fixture id. '
  'Manual admin entry is just another provider here — switching to an '
  'automated provider later changes only which adapter writes rows, '
  'never the shape of team/fixture/fixture_result.';

create index if not exists external_identity_map_canonical_idx
  on football_data.external_identity_map (canonical_table, canonical_id);

-- =====================================================================
-- Retroactive FKs on the two previously-opaque fixture_id columns.
-- Safe: both tables confirmed empty (no seed data) as of this migration.
-- =====================================================================

alter table competition.round_fixtures
  add constraint round_fixtures_fixture_fkey
  foreign key (fixture_id) references football_data.fixtures (id) on delete restrict;

alter table prediction.prediction_scores
  add constraint prediction_scores_fixture_fkey
  foreign key (fixture_id) references football_data.fixtures (id) on delete restrict;

-- =====================================================================
-- RLS. Fixtures/teams/results carry no competition reference, so
-- (unlike seasons/rounds/round_fixtures) there is no visibility check
-- to join through — any authenticated user may read them. Writes are
-- server-side only via the admin API (Admin ADR), never client RLS.
-- =====================================================================

alter table football_data.teams enable row level security;
alter table football_data.fixtures enable row level security;
alter table football_data.fixture_results enable row level security;
alter table football_data.external_identity_map enable row level security;

drop policy if exists teams_select_authenticated on football_data.teams;
create policy teams_select_authenticated
  on football_data.teams
  for select
  to authenticated
  using (true);

drop policy if exists fixtures_select_authenticated on football_data.fixtures;
create policy fixtures_select_authenticated
  on football_data.fixtures
  for select
  to authenticated
  using (true);

drop policy if exists fixture_results_select_authenticated on football_data.fixture_results;
create policy fixture_results_select_authenticated
  on football_data.fixture_results
  for select
  to authenticated
  using (true);

-- external_identity_map is an internal ACL detail: no client (including
-- authenticated, non-admin) has any business reading it directly.
drop policy if exists external_identity_map_anon_no_access on football_data.external_identity_map;
create policy external_identity_map_anon_no_access
  on football_data.external_identity_map
  for select
  to anon, authenticated
  using (false);
