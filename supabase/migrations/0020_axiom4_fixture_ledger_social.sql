-- Migration 0020 — Axiom 4 Amendment, Phase 6b (Ledger/Social wiring expand):
-- physical backing for the per-fixture Ledger/Social contexts added in
-- Phase 6a (domain.FixturePointEntry / FixtureReaction,
-- application.PostFixtureToLedger / ReactToFixture / RemoveFixtureReaction /
-- ListFixtureReactions).
--
-- Two additions, ALL additive (Platform ADR: forward-only, expand-only).
-- Nothing here touches ledger.point_entries, social.reactions, or their RLS —
-- the round-scoped tables stay exactly as they are until Phase 7 (contract).
--
--   1. ledger.entry_kind — ADD VALUE 'fixture_score' (mirrors domain
--      EntryKind.fixtureScore, Phase 6a).
--   2. ledger.fixture_point_entries — the per-fixture sibling of
--      ledger.point_entries (Axiom 5: append-only, immutable — same
--      backstop trigger reused via a NEW trigger instance, since a trigger
--      is bound to one table).
--   3. social.fixture_reactions — the per-fixture sibling of
--      social.reactions, reusing the existing social.reaction_kind enum
--      (Phase 6a's FixtureReaction wraps the same closed emoji set).
--
-- Forward-only, expand-only. Safe to re-run: every statement is guarded.

-- ---------------------------------------------------------------------------
-- 1. ledger.entry_kind — additive enum value
-- ---------------------------------------------------------------------------
alter type ledger.entry_kind add value if not exists 'fixture_score';

-- ---------------------------------------------------------------------------
-- 2. ledger.fixture_point_entries
-- ---------------------------------------------------------------------------
create table if not exists ledger.fixture_point_entries (
  id             uuid primary key,
  participant_id uuid not null
    constraint fixture_point_entries_participant_id_fkey
      references competition.participants (id) on delete restrict,
  -- Opaque reference to the Football-Data fixture (no FK yet, Axiom 3) —
  -- mirrors prediction.fixture_predictions.fixture_id.
  fixture_id     uuid not null,
  entry_kind     ledger.entry_kind not null,
  amount         integer not null,
  source_ref     text not null,
  occurred_at    timestamptz not null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint fixture_point_entries_fixture_score_nonneg
    check (entry_kind <> 'fixture_score' or amount >= 0),
  constraint fixture_point_entries_source_ref_nonempty
    check (length(source_ref) > 0),
  -- The append-only dedupe key (Axiom 4 Amendment; per-fixture sibling of
  -- point_entries_round_score_uniq). Referenced by name in the adapter's
  -- `ON CONFLICT ON CONSTRAINT`.
  constraint fixture_point_entries_fixture_score_uniq
    unique (participant_id, fixture_id, entry_kind, source_ref)
);

comment on table ledger.fixture_point_entries is
  'The append-only fixture-scoped PointEntry stream (Axiom 4 Amendment; '
  'per-fixture sibling of ledger.point_entries). One immutable row per '
  'movement; participant + fixture by id only. NEVER updated or deleted '
  '(revoked privileges + immutability trigger, mirrored below).';

create index if not exists fixture_point_entries_participant_stream_idx
  on ledger.fixture_point_entries (participant_id, occurred_at, id);
create index if not exists fixture_point_entries_fixture_idx
  on ledger.fixture_point_entries (fixture_id);

drop trigger if exists fixture_point_entries_set_updated_at
  on ledger.fixture_point_entries;
create trigger fixture_point_entries_set_updated_at
  before update on ledger.fixture_point_entries
  for each row execute function identity.set_updated_at();

-- Reuses the existing ledger.reject_entry_mutation() function (table-agnostic
-- trigger body) — a NEW trigger instance is required since a trigger binds to
-- one table, but the enforced rule is identical (Axiom 5/6).
drop trigger if exists fixture_point_entries_reject_mutation
  on ledger.fixture_point_entries;
create trigger fixture_point_entries_reject_mutation
  before update or delete on ledger.fixture_point_entries
  for each row execute function ledger.reject_entry_mutation();

alter table ledger.fixture_point_entries enable row level security;

revoke insert, update, delete, truncate
  on ledger.fixture_point_entries
  from anon, authenticated;

grant select on ledger.fixture_point_entries to authenticated;

drop policy if exists fixture_point_entries_select_own
  on ledger.fixture_point_entries;
create policy fixture_point_entries_select_own
  on ledger.fixture_point_entries
  for select
  to authenticated
  using (
    exists (
      select 1
      from competition.participants pa
      where pa.id = fixture_point_entries.participant_id
        and pa.user_id = auth.uid()
    )
  );

drop policy if exists fixture_point_entries_anon_no_access
  on ledger.fixture_point_entries;
create policy fixture_point_entries_anon_no_access
  on ledger.fixture_point_entries for select to anon using (false);

-- ---------------------------------------------------------------------------
-- 3. social.fixture_reactions
-- ---------------------------------------------------------------------------
create table if not exists social.fixture_reactions (
  id         uuid primary key,
  group_id   uuid not null,
  -- Opaque reference to the Football-Data fixture (no FK yet, Axiom 3) —
  -- mirrors prediction.fixture_predictions.fixture_id. Unlike social.reactions
  -- (round_id FK'd to competition.rounds), there is no fixtures table yet, so
  -- there is nothing to cascade from.
  fixture_id uuid not null,
  user_id    uuid not null,
  emoji      social.reaction_kind not null,
  reacted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fixture_reactions_group_id_fkey
    foreign key (group_id) references "group".groups (id) on delete cascade,
  constraint fixture_reactions_user_id_fkey
    foreign key (user_id) references identity.users (id) on delete restrict,
  constraint fixture_reactions_group_fixture_user_uniq
    unique (group_id, fixture_id, user_id)
);

comment on table social.fixture_reactions is
  'A member''s single emoji reaction to a fixture-result within a group '
  '(Axiom 4 Amendment; per-fixture sibling of social.reactions). '
  '(group_id, fixture_id, user_id) is unique = one live reaction per member '
  'per fixture-result (re-react = idempotent upsert). Carries NO points '
  '(Axiom 5) and NO open-graph edge (ADR-001).';

drop trigger if exists fixture_reactions_set_updated_at
  on social.fixture_reactions;
create trigger fixture_reactions_set_updated_at
  before update on social.fixture_reactions
  for each row
  execute function identity.set_updated_at();

alter table social.fixture_reactions enable row level security;

revoke insert, update, delete, truncate on social.fixture_reactions
  from anon, authenticated;
grant select on social.fixture_reactions to authenticated;

drop policy if exists fixture_reactions_select_member
  on social.fixture_reactions;
create policy fixture_reactions_select_member
  on social.fixture_reactions
  for select
  to authenticated
  using (
    exists (
      select 1
      from "group".group_memberships m
      where m.group_id = fixture_reactions.group_id
        and m.user_id = auth.uid()
    )
  );

drop policy if exists fixture_reactions_anon_no_access
  on social.fixture_reactions;
create policy fixture_reactions_anon_no_access
  on social.fixture_reactions
  for select
  to anon
  using (false);
