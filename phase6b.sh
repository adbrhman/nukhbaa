#!/usr/bin/env bash
# Phase 6b — Ledger/Social wiring expand (Axiom 4 Amendment): migration 0020
# (ledger.fixture_point_entries, social.fixture_reactions), Contracts DTOs,
# Infrastructure Postgres adapters, composition_root wiring, DTO mappers, and
# the two new client-facing routes:
#   POST /fixtures/{id}/ledger
#   PUT|DELETE|GET /groups/{id}/fixtures/{fixtureId}/reactions
# Additive only. NotifyFixtureScored is intentionally NOT wired here (it would
# touch ScoreFixture's already-completed, tested call site) — deferred to a
# separate follow-up script.
set -euo pipefail
cd "${1:-.}"

mkdir -p supabase/migrations
mkdir -p packages/contracts/lib/src
mkdir -p packages/infrastructure/lib/src/ledger
mkdir -p packages/infrastructure/lib/src/social
mkdir -p apps/server/lib/http
mkdir -p "apps/server/routes/fixtures/[id]/ledger"
mkdir -p "apps/server/routes/groups/[id]/fixtures/[fixtureId]/reactions"

# =============================================================================
# 1. MIGRATION 0020
# =============================================================================
cat > 'supabase/migrations/0020_axiom4_fixture_ledger_social.sql' <<'NUKHBA_EOF'
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
NUKHBA_EOF

echo "Migration 0020 written."

# =============================================================================
# 2. CONTRACTS DTOs
# =============================================================================
cat > 'packages/contracts/lib/src/fixture_ledger_dto.dart' <<'NUKHBA_EOF'
/// Versioned wire shapes for the fixture-scoped Ledger context (API ADR §4;
/// docs/project-context.md, Axiom 4 Amendment — the per-fixture sibling of
/// `ledger_dto.dart`).
///
/// Read-only on the wire (Axioms 2/5): the client never computes or submits a
/// point amount. The command that posts a scored fixture to the ledger
/// (`POST /fixtures/{id}/ledger`) has NO request body; its response is the
/// [PostFixtureToLedgerResponseDto] read shape. Names a participant and
/// fixture by id only (Axiom 4: no group reference).
library;

/// The wire shape of one immutable fixture-scoped ledger movement (read
/// projection of the domain `FixturePointEntry`).
final class FixturePointEntryDto {
  /// Creates a fixture-point-entry DTO.
  const FixturePointEntryDto({
    required this.id,
    required this.participantId,
    required this.fixtureId,
    required this.kind,
    required this.amount,
    required this.sourceRef,
    required this.occurredAt,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field.
  factory FixturePointEntryDto.fromJson(Map<String, Object?> json) {
    return FixturePointEntryDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      id: json['id']! as String,
      participantId: json['participant_id']! as String,
      fixtureId: json['fixture_id']! as String,
      kind: json['kind']! as String,
      amount: json['amount']! as int,
      sourceRef: json['source_ref']! as String,
      occurredAt: json['occurred_at']! as String,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The entry's own id (UUID string).
  final String id;

  /// The owning participant id (UUID string).
  final String participantId;

  /// The fixture this movement derives from (UUID string).
  final String fixtureId;

  /// The entry-kind wire token: `fixture_score` or `correction`.
  final String kind;

  /// The signed point movement (server-computed).
  final int amount;

  /// The provenance handle.
  final String sourceRef;

  /// When the movement occurred (ISO-8601 UTC string).
  final String occurredAt;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'id': id,
    'participant_id': participantId,
    'fixture_id': fixtureId,
    'kind': kind,
    'amount': amount,
    'source_ref': sourceRef,
    'occurred_at': occurredAt,
  };

  @override
  bool operator ==(Object other) =>
      other is FixturePointEntryDto &&
      other.id == id &&
      other.participantId == participantId &&
      other.fixtureId == fixtureId &&
      other.kind == kind &&
      other.amount == amount &&
      other.sourceRef == sourceRef &&
      other.occurredAt == occurredAt &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    id,
    participantId,
    fixtureId,
    kind,
    amount,
    sourceRef,
    occurredAt,
    schemaVersion,
  );
}

/// The wire shape echoed back after an admin posts a scored fixture to the
/// ledger (`POST /fixtures/{id}/ledger`). An **empty** `appendedEntries` list
/// means the fixture was already fully posted (idempotent replay — Axiom 4).
final class PostFixtureToLedgerResponseDto {
  /// Creates a post-fixture-to-ledger response DTO.
  const PostFixtureToLedgerResponseDto({
    required this.fixtureId,
    required this.appendedEntries,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field.
  factory PostFixtureToLedgerResponseDto.fromJson(Map<String, Object?> json) {
    final raw = json['appended_entries']! as List<Object?>;
    return PostFixtureToLedgerResponseDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      fixtureId: json['fixture_id']! as String,
      appendedEntries: raw
          .map(
            (e) => FixturePointEntryDto.fromJson(
              (e! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The fixture that was posted to the ledger (UUID string).
  final String fixtureId;

  /// The entries appended by this post (empty on an idempotent replay).
  final List<FixturePointEntryDto> appendedEntries;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'fixture_id': fixtureId,
    'appended_entries': [for (final e in appendedEntries) e.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is PostFixtureToLedgerResponseDto &&
      other.fixtureId == fixtureId &&
      _listEquals(other.appendedEntries, appendedEntries) &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode =>
      Object.hash(fixtureId, Object.hashAll(appendedEntries), schemaVersion);

  static bool _listEquals(
    List<FixturePointEntryDto> a,
    List<FixturePointEntryDto> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
NUKHBA_EOF

cat > 'packages/contracts/lib/src/fixture_social_dto.dart' <<'NUKHBA_EOF'
/// Versioned wire shapes for the fixture-scoped Social (Tier-3) context (API
/// ADR §4; docs/project-context.md, Axiom 4 Amendment — the per-fixture
/// sibling of `social_dto.dart`).
library;

/// The wire shape of one fixture-scoped reaction (read projection of the
/// domain `FixtureReaction`).
final class FixtureReactionDto {
  /// Creates a fixture-reaction DTO.
  const FixtureReactionDto({
    required this.id,
    required this.groupId,
    required this.fixtureId,
    required this.userId,
    required this.emoji,
    required this.reactedAt,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field.
  factory FixtureReactionDto.fromJson(Map<String, Object?> json) {
    return FixtureReactionDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      id: json['id']! as String,
      groupId: json['group_id']! as String,
      fixtureId: json['fixture_id']! as String,
      userId: json['user_id']! as String,
      emoji: json['emoji']! as String,
      reactedAt: json['reacted_at']! as String,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The reaction id (UUID string).
  final String id;

  /// The group this reaction is scoped to (UUID string).
  final String groupId;

  /// The fixture-result this reaction targets (UUID string).
  final String fixtureId;

  /// The reacting member's user id (UUID string).
  final String userId;

  /// The chosen emoji wire token (one of the closed set).
  final String emoji;

  /// When the reaction was made or last changed (UTC ISO-8601).
  final String reactedAt;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'id': id,
    'group_id': groupId,
    'fixture_id': fixtureId,
    'user_id': userId,
    'emoji': emoji,
    'reacted_at': reactedAt,
  };

  @override
  bool operator ==(Object other) =>
      other is FixtureReactionDto &&
      other.id == id &&
      other.groupId == groupId &&
      other.fixtureId == fixtureId &&
      other.userId == userId &&
      other.emoji == emoji &&
      other.reactedAt == reactedAt &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    id,
    groupId,
    fixtureId,
    userId,
    emoji,
    reactedAt,
    schemaVersion,
  );
}

/// The wire shape of a fixture's reactions within a group — the response of
/// `GET /groups/{id}/fixtures/{fixtureId}/reactions`.
final class FixtureReactionsDto {
  /// Creates a fixture-reactions DTO.
  const FixtureReactionsDto({
    required this.groupId,
    required this.fixtureId,
    required this.reactions,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field.
  factory FixtureReactionsDto.fromJson(Map<String, Object?> json) {
    final raw = json['reactions']! as List<Object?>;
    return FixtureReactionsDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      groupId: json['group_id']! as String,
      fixtureId: json['fixture_id']! as String,
      reactions: raw
          .map(
            (e) => FixtureReactionDto.fromJson(
              (e! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The group this list is scoped to (UUID string).
  final String groupId;

  /// The fixture this list is scoped to (UUID string).
  final String fixtureId;

  /// The reactions, in the server-defined order (reactedAt ascending).
  final List<FixtureReactionDto> reactions;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'group_id': groupId,
    'fixture_id': fixtureId,
    'reactions': [for (final r in reactions) r.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is FixtureReactionsDto &&
      other.groupId == groupId &&
      other.fixtureId == fixtureId &&
      _listEquals(other.reactions, reactions) &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    groupId,
    fixtureId,
    Object.hashAll(reactions),
    schemaVersion,
  );

  static bool _listEquals(
    List<FixtureReactionDto> a,
    List<FixtureReactionDto> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
NUKHBA_EOF

# contracts.dart exports (additive)
C=packages/contracts/lib/contracts.dart
grep -q "src/fixture_ledger_dto.dart" "$C" || \
  sed -i "\#export 'src/ledger_dto.dart';#i export 'src/fixture_ledger_dto.dart';" "$C"
grep -q "src/fixture_social_dto.dart" "$C" || \
  sed -i "\#export 'src/social_dto.dart';#i export 'src/fixture_social_dto.dart';" "$C"

echo "Contracts layer done."

# =============================================================================
# 3. INFRASTRUCTURE ADAPTERS
# =============================================================================
cat > 'packages/infrastructure/lib/src/ledger/postgres_fixture_ledger_repository.dart' <<'NUKHBA_EOF'
import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:postgres/postgres.dart' hide Result;
import 'package:shared/shared.dart';

/// Postgres-backed [FixtureLedgerRepository] over the append-only
/// `ledger.fixture_point_entries` table (Database ADR; migration
/// `0020_axiom4_fixture_ledger_social.sql`) — the per-fixture sibling of
/// [PostgresLedgerRepository].
///
/// Same atomicity/idempotency contract as [PostgresLedgerRepository]: the
/// whole batch is appended inside one transaction, deduped on
/// `(participant_id, fixture_id, entry_kind, source_ref)` via
/// `ON CONFLICT ON CONSTRAINT fixture_point_entries_fixture_score_uniq DO
/// NOTHING`. The adapter is total (never throws); SQL and rows never leak.
final class PostgresFixtureLedgerRepository implements FixtureLedgerRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresFixtureLedgerRepository(this._connection);

  final PostgresConnection _connection;

  static const String _insertEntrySql = '''
INSERT INTO ledger.fixture_point_entries
  (id, participant_id, fixture_id, entry_kind, amount, source_ref, occurred_at)
VALUES
  (@id, @participant_id, @fixture_id, @entry_kind, @amount, @source_ref, @occurred_at)
ON CONFLICT ON CONSTRAINT fixture_point_entries_fixture_score_uniq DO NOTHING
RETURNING id, participant_id, fixture_id, entry_kind, amount, source_ref, occurred_at
''';

  @override
  Future<Result<List<FixturePointEntry>>> appendEntries(
    List<FixturePointEntry> entries,
  ) {
    if (entries.isEmpty) {
      return Future.value(const Result.ok(<FixturePointEntry>[]));
    }
    return _connection.runInTransaction((tx) async {
      final appended = <FixturePointEntry>[];
      for (final entry in entries) {
        final inserted = await tx.query(
          _insertEntrySql,
          parameters: {
            'id': entry.id.value,
            'participant_id': entry.participantId.value,
            'fixture_id': entry.fixture.value,
            'entry_kind': entry.kind.wireValue,
            'amount': entry.amount,
            'source_ref': entry.sourceRef,
            'occurred_at': entry.occurredAt.toUtc(),
          },
        );
        switch (inserted) {
          case Err<List<Map<String, dynamic>>>(:final error):
            return Result.err(_reclassify(error));
          case Ok<List<Map<String, dynamic>>>(:final value):
            if (value.isEmpty) {
              continue;
            }
            final mapped = _mapEntry(value.first);
            if (mapped is Err<FixturePointEntry>) {
              return Result.err(mapped.error);
            }
            appended.add((mapped as Ok<FixturePointEntry>).value);
        }
      }
      return Result.ok(List<FixturePointEntry>.unmodifiable(appended));
    });
  }

  static const String _selectByParticipantSql = '''
SELECT id, participant_id, fixture_id, entry_kind, amount, source_ref, occurred_at
FROM ledger.fixture_point_entries
WHERE participant_id = @participant_id
ORDER BY occurred_at ASC, id ASC
''';

  @override
  Future<Result<List<FixturePointEntry>>> listEntries(
    ParticipantId participantId,
  ) async {
    final result = await _connection.query(
      _selectByParticipantSql,
      parameters: {'participant_id': participantId.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapEntries(value),
    };
  }

  Result<List<FixturePointEntry>> _mapEntries(
    List<Map<String, dynamic>> rows,
  ) {
    final entries = <FixturePointEntry>[];
    for (final row in rows) {
      final mapped = _mapEntry(row);
      if (mapped is Err<FixturePointEntry>) {
        return Result.err(mapped.error);
      }
      entries.add((mapped as Ok<FixturePointEntry>).value);
    }
    return Result.ok(List<FixturePointEntry>.unmodifiable(entries));
  }

  Result<FixturePointEntry> _mapEntry(Map<String, dynamic> row) {
    final idResult = PointEntryId.tryParse(row['id']?.toString());
    final participantIdResult = ParticipantId.tryParse(
      row['participant_id']?.toString(),
    );
    final fixtureResult = FixtureRef.tryParse(row['fixture_id']?.toString());
    final kindResult = EntryKind.tryParse(row['entry_kind']?.toString());
    final amount = _readInt(row['amount']);
    final sourceRefRaw = row['source_ref'];
    final occurredAt = _readUtcTimestamp(row['occurred_at']);

    if (idResult is Err<PointEntryId>) {
      return Result.err(
        _corrupt('id', idResult.error.message),
      );
    }
    if (participantIdResult is Err<ParticipantId>) {
      return Result.err(
        _corrupt('participant_id', participantIdResult.error.message),
      );
    }
    if (fixtureResult is Err<FixtureRef>) {
      return Result.err(_corrupt('fixture_id', fixtureResult.error.message));
    }
    if (kindResult is Err<EntryKind>) {
      return Result.err(_corrupt('entry_kind', kindResult.error.message));
    }
    if (amount == null) {
      return Result.err(_corrupt('amount', 'not an integer'));
    }
    if (sourceRefRaw is! String || sourceRefRaw.isEmpty) {
      return Result.err(_corrupt('source_ref', 'null or empty'));
    }
    if (occurredAt == null) {
      return Result.err(_corrupt('occurred_at', 'not a timestamp'));
    }

    return Result.ok(
      FixturePointEntry.fromStored(
        id: (idResult as Ok<PointEntryId>).value,
        participantId: (participantIdResult as Ok<ParticipantId>).value,
        fixture: (fixtureResult as Ok<FixtureRef>).value,
        kind: (kindResult as Ok<EntryKind>).value,
        amount: amount,
        sourceRef: sourceRefRaw,
        occurredAt: occurredAt,
      ),
    );
  }

  AppError _reclassify(AppError error) {
    final cause = error.cause;
    if (cause is! ServerException) {
      return error;
    }
    final code = cause.code;
    const integrityCodes = {'23505', '23503', '23514'};
    if (code == null || !integrityCodes.contains(code)) {
      return error;
    }
    final constraint = cause.constraintName;
    if (constraint == 'fixture_point_entries_participant_id_fkey') {
      return const AppError.invariant(
        'ledger.participant_not_found',
        'Participant not found',
      );
    }
    if (constraint == 'fixture_point_entries_fixture_score_uniq') {
      return const AppError.invariant(
        'ledger.already_posted',
        'This fixture-score credit was already appended',
      );
    }
    return const AppError.invariant(
      'ledger.integrity_violation',
      'The write violated a ledger integrity rule',
    );
  }

  static int? _readInt(Object? raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is BigInt && raw.isValidInt) {
      return raw.toInt();
    }
    if (raw is String) {
      return int.tryParse(raw);
    }
    return null;
  }

  static DateTime? _readUtcTimestamp(Object? raw) {
    if (raw is DateTime) {
      return raw.toUtc();
    }
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      return parsed?.toUtc();
    }
    return null;
  }

  static AppError _corrupt(String field, String detail) => AppError.transient(
    'ledger.row_corrupt',
    'Stored fixture_point_entries row has invalid $field: $detail',
  );
}
NUKHBA_EOF

cat > 'packages/infrastructure/lib/src/social/postgres_fixture_reaction_repository.dart' <<'NUKHBA_EOF'
import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:postgres/postgres.dart' hide Result;
import 'package:shared/shared.dart';

/// Postgres-backed [FixtureReactionRepository] over the `social.fixture_reactions`
/// table (Database ADR; migration `0020_axiom4_fixture_ledger_social.sql`) —
/// the per-fixture sibling of [PostgresReactionRepository].
final class PostgresFixtureReactionRepository
    implements FixtureReactionRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresFixtureReactionRepository(this._connection);

  final PostgresConnection _connection;

  static const String _upsertSql = '''
INSERT INTO social.fixture_reactions
  (id, group_id, fixture_id, user_id, emoji, reacted_at)
VALUES
  (@id, @group_id, @fixture_id, @user_id, @emoji, @reacted_at)
ON CONFLICT ON CONSTRAINT fixture_reactions_group_fixture_user_uniq
DO UPDATE SET emoji = excluded.emoji, reacted_at = excluded.reacted_at
''';

  @override
  Future<Result<void>> upsertReaction(FixtureReaction reaction) async {
    final result = await _connection.query(
      _upsertSql,
      parameters: {
        'id': reaction.id.value,
        'group_id': reaction.groupId.value,
        'fixture_id': reaction.fixture.value,
        'user_id': reaction.userId.value,
        'emoji': reaction.emoji.wireValue,
        'reacted_at': reaction.reactedAt.toUtc(),
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(
        _reclassify(error),
      ),
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
    };
  }

  static const String _findSql = '''
SELECT id, group_id, fixture_id, user_id, emoji, reacted_at
FROM social.fixture_reactions
WHERE group_id = @group_id AND fixture_id = @fixture_id AND user_id = @user_id
''';

  @override
  Future<Result<FixtureReaction?>> findReaction(
    GroupId groupId,
    FixtureRef fixture,
    UserId userId,
  ) async {
    final result = await _connection.query(
      _findSql,
      parameters: {
        'group_id': groupId.value,
        'fixture_id': fixture.value,
        'user_id': userId.value,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty ? const Result.ok(null) : _mapOne(value.first),
    };
  }

  static const String _listSql = '''
SELECT id, group_id, fixture_id, user_id, emoji, reacted_at
FROM social.fixture_reactions
WHERE group_id = @group_id AND fixture_id = @fixture_id
ORDER BY reacted_at ASC, id ASC
''';

  @override
  Future<Result<List<FixtureReaction>>> listReactionsForFixture(
    GroupId groupId,
    FixtureRef fixture,
  ) async {
    final result = await _connection.query(
      _listSql,
      parameters: {'group_id': groupId.value, 'fixture_id': fixture.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapMany(value),
    };
  }

  static const String _deleteSql = '''
DELETE FROM social.fixture_reactions
WHERE group_id = @group_id AND fixture_id = @fixture_id AND user_id = @user_id
RETURNING id
''';

  @override
  Future<Result<bool>> removeReaction(
    GroupId groupId,
    FixtureRef fixture,
    UserId userId,
  ) async {
    final result = await _connection.query(
      _deleteSql,
      parameters: {
        'group_id': groupId.value,
        'fixture_id': fixture.value,
        'user_id': userId.value,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        value.isNotEmpty,
      ),
    };
  }

  Result<List<FixtureReaction>> _mapMany(List<Map<String, dynamic>> rows) {
    final reactions = <FixtureReaction>[];
    for (final row in rows) {
      final mapped = _mapOne(row);
      if (mapped is Err<FixtureReaction?>) {
        return Result.err(mapped.error);
      }
      final reaction = (mapped as Ok<FixtureReaction?>).value;
      if (reaction != null) {
        reactions.add(reaction);
      }
    }
    return Result.ok(List<FixtureReaction>.unmodifiable(reactions));
  }

  Result<FixtureReaction?> _mapOne(Map<String, dynamic> row) {
    final idResult = ReactionId.tryParse(row['id']?.toString());
    final groupIdResult = GroupId.tryParse(row['group_id']?.toString());
    final fixtureResult = FixtureRef.tryParse(row['fixture_id']?.toString());
    final userIdResult = UserId.tryParse(row['user_id']?.toString());
    final emojiResult = ReactionEmoji.tryParse(row['emoji']?.toString());
    final reactedAt = _readUtcTimestamp(row['reacted_at']);

    if (idResult is Err<ReactionId>) {
      return Result.err(_corrupt('id', idResult.error.message));
    }
    if (groupIdResult is Err<GroupId>) {
      return Result.err(_corrupt('group_id', groupIdResult.error.message));
    }
    if (fixtureResult is Err<FixtureRef>) {
      return Result.err(_corrupt('fixture_id', fixtureResult.error.message));
    }
    if (userIdResult is Err<UserId>) {
      return Result.err(_corrupt('user_id', userIdResult.error.message));
    }
    if (emojiResult is Err<ReactionEmoji>) {
      return Result.err(_corrupt('emoji', emojiResult.error.message));
    }
    if (reactedAt == null) {
      return Result.err(_corrupt('reacted_at', 'not a timestamp'));
    }

    return Result.ok(
      FixtureReaction.fromStored(
        id: (idResult as Ok<ReactionId>).value,
        groupId: (groupIdResult as Ok<GroupId>).value,
        fixture: (fixtureResult as Ok<FixtureRef>).value,
        userId: (userIdResult as Ok<UserId>).value,
        emoji: (emojiResult as Ok<ReactionEmoji>).value,
        reactedAt: reactedAt,
      ),
    );
  }

  AppError _reclassify(AppError error) {
    final cause = error.cause;
    if (cause is! ServerException) {
      return error;
    }
    final code = cause.code;
    const integrityCodes = {'23505', '23503'};
    if (code == null || !integrityCodes.contains(code)) {
      return error;
    }
    final constraint = cause.constraintName;
    if (constraint == 'fixture_reactions_group_fixture_user_uniq') {
      return const AppError.invariant(
        'social.reaction_conflict',
        'A concurrent reaction won the race',
      );
    }
    if (constraint == 'fixture_reactions_group_id_fkey') {
      return const AppError.invariant(
        'social.group_not_found',
        'Group not found',
      );
    }
    if (constraint == 'fixture_reactions_user_id_fkey') {
      return const AppError.invariant(
        'social.user_not_found',
        'User not found',
      );
    }
    return const AppError.invariant(
      'social.integrity_violation',
      'The write violated a social integrity rule',
    );
  }

  static DateTime? _readUtcTimestamp(Object? raw) {
    if (raw is DateTime) {
      return raw.toUtc();
    }
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      return parsed?.toUtc();
    }
    return null;
  }

  static AppError _corrupt(String field, String detail) => AppError.transient(
    'social.row_corrupt',
    'Stored fixture_reactions row has invalid $field: $detail',
  );
}
NUKHBA_EOF

echo "Infrastructure layer done."

# =============================================================================
# 4. composition_root.dart — surgical patches
# =============================================================================
python3 - <<'PYEOF'
import pathlib
p = pathlib.Path('apps/server/lib/composition/composition_root.dart')
s = p.read_text()

def patch(old, new, label):
    global s
    if new.strip() in s:
        print(f'{label}: already patched, skipping')
        return
    assert old in s, f'{label}: anchor not found'
    assert s.count(old) == 1, f'{label}: anchor not unique'
    s = s.replace(old, old + new, 1)
    print(f'{label}: OK')

# 1. Main required-constructor params
patch(
    "    required this.reactToRound,\n"
    "    required this.removeReaction,\n"
    "    required this.listRoundReactions,\n",
    "    required this.postFixtureToLedger,\n"
    "    required this.reactToFixture,\n"
    "    required this.removeFixtureReaction,\n"
    "    required this.listFixtureReactions,\n",
    "main constructor required params",
)

# 2. Optional-constructor params
patch(
    "    ReactToRound? reactToRound,\n"
    "    RemoveReaction? removeReaction,\n"
    "    ListRoundReactions? listRoundReactions,\n",
    "    PostFixtureToLedger? postFixtureToLedger,\n"
    "    ReactToFixture? reactToFixture,\n"
    "    RemoveFixtureReaction? removeFixtureReaction,\n"
    "    ListFixtureReactions? listFixtureReactions,\n",
    "optional constructor params",
)

# 3. Default-init assignments
patch(
    "       reactToRound = reactToRound ?? _absentReactToRound(),\n"
    "       removeReaction = removeReaction ?? _absentRemoveReaction(),\n"
    "       listRoundReactions = listRoundReactions ?? _absentListRoundReactions(),\n",
    "       postFixtureToLedger =\n"
    "           postFixtureToLedger ?? _absentPostFixtureToLedger(),\n"
    "       reactToFixture = reactToFixture ?? _absentReactToFixture(),\n"
    "       removeFixtureReaction =\n"
    "           removeFixtureReaction ?? _absentRemoveFixtureReaction(),\n"
    "       listFixtureReactions =\n"
    "           listFixtureReactions ?? _absentListFixtureReactions(),\n",
    "default-init assignments",
)

# 4. Field declarations
patch(
    "  final ListRoundReactions listRoundReactions;\n",
    "\n"
    "  /// Posts a scored fixture to the append-only Ledger (Axiom 4 Amendment;\n"
    "  /// admin-only, enforced inside the use-case — the per-fixture sibling of\n"
    "  /// [postRoundToLedger]).\n"
    "  final PostFixtureToLedger postFixtureToLedger;\n"
    "\n"
    "  /// Reacts (or changes a reaction) to a fixture-result within a group\n"
    "  /// (member-gated — Axiom 4 Amendment; the per-fixture sibling of\n"
    "  /// [reactToRound]).\n"
    "  final ReactToFixture reactToFixture;\n"
    "\n"
    "  /// Removes the caller's own reaction to a fixture-result within a group\n"
    "  /// (member-gated, idempotent — Axiom 4 Amendment; the per-fixture sibling\n"
    "  /// of [removeReaction]).\n"
    "  final RemoveFixtureReaction removeFixtureReaction;\n"
    "\n"
    "  /// Lists a fixture-result's reactions within a group (member-gated read —\n"
    "  /// Axiom 4 Amendment; the per-fixture sibling of [listRoundReactions]).\n"
    "  final ListFixtureReactions listFixtureReactions;\n",
    "field declarations",
)

# 5. Local repository vars (in the wiring factory)
patch(
    "    final reactionRepository = PostgresReactionRepository(connection);\n",
    "    final fixtureLedgerRepository = PostgresFixtureLedgerRepository(\n"
    "      connection,\n"
    "    );\n"
    "    final fixtureReactionRepository = PostgresFixtureReactionRepository(\n"
    "      connection,\n"
    "    );\n",
    "local repository vars",
)

# 6. Actual wiring
patch(
    "      reactToRound: ReactToRound(\n"
    "        reactions: reactionRepository,\n"
    "        groups: groupRepository,\n"
    "        idGenerator: idGenerator,\n"
    "        clock: clock,\n"
    "      ),\n"
    "      removeReaction: RemoveReaction(\n"
    "        reactions: reactionRepository,\n"
    "        groups: groupRepository,\n"
    "      ),\n"
    "      listRoundReactions: ListRoundReactions(\n"
    "        reactions: reactionRepository,\n"
    "        groups: groupRepository,\n"
    "      ),\n",
    "      postFixtureToLedger: PostFixtureToLedger(\n"
    "        fixtureScoreRepository: fixtureScoreRepository,\n"
    "        fixtureLedgerRepository: fixtureLedgerRepository,\n"
    "        idGenerator: idGenerator,\n"
    "        clock: clock,\n"
    "      ),\n"
    "      reactToFixture: ReactToFixture(\n"
    "        reactions: fixtureReactionRepository,\n"
    "        groups: groupRepository,\n"
    "        idGenerator: idGenerator,\n"
    "        clock: clock,\n"
    "      ),\n"
    "      removeFixtureReaction: RemoveFixtureReaction(\n"
    "        reactions: fixtureReactionRepository,\n"
    "        groups: groupRepository,\n"
    "      ),\n"
    "      listFixtureReactions: ListFixtureReactions(\n"
    "        reactions: fixtureReactionRepository,\n"
    "        groups: groupRepository,\n"
    "      ),\n",
    "actual wiring",
)

# 7. _absent factories
patch(
    "  static ListRoundReactions _absentListRoundReactions() => ListRoundReactions(\n"
    "    reactions: _unwiredReactionRepository,\n"
    "    groups: _unwiredGroupRepository,\n"
    "  );\n",
    "\n"
    "  static PostFixtureToLedger _absentPostFixtureToLedger() =>\n"
    "      PostFixtureToLedger(\n"
    "        fixtureScoreRepository: _unwiredFixtureScoreRepository,\n"
    "        fixtureLedgerRepository: _unwiredFixtureLedgerRepository,\n"
    "        idGenerator: _unwiredIdGenerator,\n"
    "        clock: _unwiredClock,\n"
    "      );\n"
    "\n"
    "  static ReactToFixture _absentReactToFixture() => ReactToFixture(\n"
    "    reactions: _unwiredFixtureReactionRepository,\n"
    "    groups: _unwiredGroupRepository,\n"
    "    idGenerator: _unwiredIdGenerator,\n"
    "    clock: _unwiredClock,\n"
    "  );\n"
    "\n"
    "  static RemoveFixtureReaction _absentRemoveFixtureReaction() =>\n"
    "      RemoveFixtureReaction(\n"
    "        reactions: _unwiredFixtureReactionRepository,\n"
    "        groups: _unwiredGroupRepository,\n"
    "      );\n"
    "\n"
    "  static ListFixtureReactions _absentListFixtureReactions() =>\n"
    "      ListFixtureReactions(\n"
    "        reactions: _unwiredFixtureReactionRepository,\n"
    "        groups: _unwiredGroupRepository,\n"
    "      );\n",
    "_absent factories",
)

# 8. static final unwired repository instances
patch(
    "  static final ActivityFeedReader _unwiredActivityFeedReader =\n"
    "      _UnwiredActivityFeedReader();\n",
    "  static final FixtureLedgerRepository _unwiredFixtureLedgerRepository =\n"
    "      _UnwiredFixtureLedgerRepository();\n"
    "  static final FixtureReactionRepository _unwiredFixtureReactionRepository =\n"
    "      _UnwiredFixtureReactionRepository();\n",
    "static final unwired repository instances",
)

# 9. _Unwired classes
anchor9 = (
    "/// Backs an \"absent\" [GetGroupActivityFeed]'s feed reader: throws if a test\n"
    "/// reaches the social feed slice it never wired.\n"
    "final class _UnwiredActivityFeedReader implements ActivityFeedReader {\n"
)
insertion9 = (
    "/// Backs every \"absent\" fixture-ledger use-case's port (Axiom 4 Amendment):\n"
    "/// any method throws so a test that reaches an unwired slice fails loudly\n"
    "/// instead of touching a real database.\n"
    "final class _UnwiredFixtureLedgerRepository\n"
    "    implements FixtureLedgerRepository {\n"
    "  static Never _unwired() => throw StateError(\n"
    "    'A fixture-ledger use-case was not wired into this root',\n"
    "  );\n"
    "\n"
    "  @override\n"
    "  Future<Result<List<FixturePointEntry>>> appendEntries(\n"
    "    List<FixturePointEntry> entries,\n"
    "  ) => _unwired();\n"
    "\n"
    "  @override\n"
    "  Future<Result<List<FixturePointEntry>>> listEntries(\n"
    "    ParticipantId participantId,\n"
    "  ) => _unwired();\n"
    "}\n"
    "\n"
    "/// Backs every \"absent\" fixture-social use-case's port (Axiom 4 Amendment):\n"
    "/// any method throws so a test that reaches an unwired slice fails loudly\n"
    "/// instead of touching a real database.\n"
    "final class _UnwiredFixtureReactionRepository\n"
    "    implements FixtureReactionRepository {\n"
    "  static Never _unwired() => throw StateError(\n"
    "    'A fixture-social use-case was not wired into this root',\n"
    "  );\n"
    "\n"
    "  @override\n"
    "  Future<Result<void>> upsertReaction(FixtureReaction reaction) =>\n"
    "      _unwired();\n"
    "\n"
    "  @override\n"
    "  Future<Result<FixtureReaction?>> findReaction(\n"
    "    GroupId groupId,\n"
    "    FixtureRef fixture,\n"
    "    UserId userId,\n"
    "  ) => _unwired();\n"
    "\n"
    "  @override\n"
    "  Future<Result<List<FixtureReaction>>> listReactionsForFixture(\n"
    "    GroupId groupId,\n"
    "    FixtureRef fixture,\n"
    "  ) => _unwired();\n"
    "\n"
    "  @override\n"
    "  Future<Result<bool>> removeReaction(\n"
    "    GroupId groupId,\n"
    "    FixtureRef fixture,\n"
    "    UserId userId,\n"
    "  ) => _unwired();\n"
    "}\n"
    "\n"
)
if insertion9.strip().split('\n')[0] not in s:
    assert anchor9 in s, 'unwired classes: anchor not found'
    assert s.count(anchor9) == 1, 'unwired classes: anchor not unique'
    s = s.replace(anchor9, insertion9 + anchor9, 1)
    print('unwired classes: OK')
else:
    print('unwired classes: already patched, skipping')

p.write_text(s)
PYEOF

echo "composition_root.dart patched."

# =============================================================================
# 5. DTO MAPPERS
# =============================================================================
cat > 'apps/server/lib/http/fixture_ledger_dto_mapper.dart' <<'NUKHBA_EOF'
import 'package:contracts/contracts.dart';
import 'package:domain/domain.dart';

/// Projects the fixture-scoped Ledger read values onto their versioned wire
/// shapes (API ADR §4; docs/project-context.md, Axiom 4 Amendment — the
/// per-fixture sibling of `ledger_dto_mapper.dart`).

/// Projects one immutable [FixturePointEntry] onto the wire
/// [FixturePointEntryDto].
FixturePointEntryDto fixturePointEntryToDto(FixturePointEntry entry) {
  return FixturePointEntryDto(
    id: entry.id.value,
    participantId: entry.participantId.value,
    fixtureId: entry.fixture.value,
    kind: entry.kind.wireValue,
    amount: entry.amount,
    sourceRef: entry.sourceRef,
    occurredAt: entry.occurredAt.toUtc().toIso8601String(),
  );
}

/// Shapes the response of `POST /fixtures/{id}/ledger` — the fixture posted
/// plus the entries this post actually appended. An **empty** list means the
/// fixture was already fully posted (idempotent replay — Axiom 4).
Map<String, Object?> postFixtureToLedgerResponseJson(
  String fixtureId,
  List<FixturePointEntry> appendedEntries,
) {
  return PostFixtureToLedgerResponseDto(
    fixtureId: fixtureId,
    appendedEntries: [
      for (final entry in appendedEntries) fixturePointEntryToDto(entry),
    ],
  ).toJson();
}
NUKHBA_EOF

cat > 'apps/server/lib/http/fixture_social_dto_mapper.dart' <<'NUKHBA_EOF'
import 'package:contracts/contracts.dart';
import 'package:domain/domain.dart';

/// Projects the fixture-scoped Social (Tier-3) read values onto their
/// versioned wire shapes (API ADR §4; docs/project-context.md, Axiom 4
/// Amendment — the per-fixture sibling of `social_dto_mapper.dart`).

/// Projects one domain [FixtureReaction] onto the wire [FixtureReactionDto].
FixtureReactionDto fixtureReactionToDto(FixtureReaction reaction) {
  return FixtureReactionDto(
    id: reaction.id.value,
    groupId: reaction.groupId.value,
    fixtureId: reaction.fixture.value,
    userId: reaction.userId.value,
    emoji: reaction.emoji.wireValue,
    reactedAt: reaction.reactedAt.toUtc().toIso8601String(),
  );
}

/// Shapes the response of `GET /groups/{id}/fixtures/{fixtureId}/reactions` —
/// the fixture's reactions within the group, in the server-defined order
/// (reactedAt ascending). An empty list is a legitimate result.
Map<String, Object?> fixtureReactionsJson(
  String groupId,
  String fixtureId,
  List<FixtureReaction> reactions,
) {
  return FixtureReactionsDto(
    groupId: groupId,
    fixtureId: fixtureId,
    reactions: [for (final r in reactions) fixtureReactionToDto(r)],
  ).toJson();
}
NUKHBA_EOF

echo "DTO mappers done."

# =============================================================================
# 6. ROUTES
# =============================================================================
cat > "apps/server/routes/fixtures/[id]/ledger/index.dart" <<'NUKHBA_EOF'
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/fixture_ledger_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `POST /fixtures/{id}/ledger` — post a **scored** fixture to the append-only
/// Ledger (API ADR §2: command intent `PostFixtureToLedger`;
/// docs/project-context.md, Axiom 4 Amendment — the per-fixture sibling of
/// `POST /rounds/{id}/ledger`). Admin-only, enforced inside the use-case
/// (Axioms 2/5).
///
/// No request body: the amounts are copied server-side from the fixture's
/// already-persisted `ParticipantFixtureScore`s. **Idempotent** (Axiom 4):
/// re-posting an already-posted fixture appends nothing new — the response's
/// `appended_entries` is empty.
///
/// The `/fixtures` subtree is already behind `bearerAuth`
/// (`routes/fixtures/_middleware.dart`), which provides the verified
/// [AuthenticatedUser]; an unauthenticated request never reaches this handler.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final result = await root.postFixtureToLedger(
    principal: principal,
    fixtureId: id,
  );

  return switch (result) {
    Ok<List<FixturePointEntry>>(:final value) => Response.json(
      body: postFixtureToLedgerResponseJson(id, value),
    ),
    Err<List<FixturePointEntry>>(:final error) => errorResponse(error),
  };
}
NUKHBA_EOF

cat > "apps/server/routes/groups/[id]/fixtures/[fixtureId]/reactions/index.dart" <<'NUKHBA_EOF'
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/fixture_social_dto_mapper.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `/groups/{id}/fixtures/{fixtureId}/reactions` — a group member's emoji
/// reaction to a fixture-result (docs/project-context.md, Axiom 4 Amendment —
/// the per-fixture sibling of
/// `routes/groups/[id]/rounds/[roundId]/reactions/index.dart`).
///
/// Lives UNDER `/groups/{id}/...` so it inherits the `/groups` `bearerAuth`
/// subtree and is group-scoped by construction. Every authorization decision
/// (the member-only `group.not_a_member` gate, no existence oracle) lives
/// inside the use-case; this route makes none.
///
/// Methods:
///   * `PUT` — react or change (idempotent upsert). Body: `{ "emoji": string }`.
///     → `200` [FixtureReactionDto].
///   * `DELETE` — remove the caller's own reaction (idempotent). → `200`
///     `{ "removed": bool }`.
///   * `GET` — list the fixture's reactions within the group (member-gated).
///     → `200` [FixtureReactionsDto].
///   * anything else → `405`.
Future<Response> onRequest(
  RequestContext context,
  String id,
  String fixtureId,
) async {
  final method = context.request.method;
  return switch (method) {
    HttpMethod.put => _react(context, id, fixtureId),
    HttpMethod.delete => _remove(context, id, fixtureId),
    HttpMethod.get => _list(context, id, fixtureId),
    _ => Response(statusCode: HttpStatus.methodNotAllowed),
  };
}

Future<Response> _react(
  RequestContext context,
  String id,
  String fixtureId,
) async {
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final body = (bodyResult as Ok<Map<String, Object?>>).value;

  final emoji = requireString(body, 'emoji');
  if (emoji is Err<String>) {
    return errorResponse(emoji.error);
  }

  final result = await root.reactToFixture(
    principal: principal,
    groupId: id,
    fixtureId: fixtureId,
    emoji: (emoji as Ok<String>).value,
  );

  return switch (result) {
    Ok<FixtureReaction>(:final value) => Response.json(
      body: fixtureReactionToDto(value).toJson(),
    ),
    Err<FixtureReaction>(:final error) => errorResponse(error),
  };
}

Future<Response> _remove(
  RequestContext context,
  String id,
  String fixtureId,
) async {
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final result = await root.removeFixtureReaction(
    principal: principal,
    groupId: id,
    fixtureId: fixtureId,
  );

  return switch (result) {
    Ok<bool>(:final value) => Response.json(body: {'removed': value}),
    Err<bool>(:final error) => errorResponse(error),
  };
}

Future<Response> _list(
  RequestContext context,
  String id,
  String fixtureId,
) async {
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final result = await root.listFixtureReactions(
    principal: principal,
    groupId: id,
    fixtureId: fixtureId,
  );

  return switch (result) {
    Ok<List<FixtureReaction>>(:final value) => Response.json(
      body: fixtureReactionsJson(id, fixtureId, value),
    ),
    Err<List<FixtureReaction>>(:final error) => errorResponse(error),
  };
}
NUKHBA_EOF

echo "Routes done."

echo ""
echo "DONE — الآن نفّذ:"
echo "  flutter pub get"
echo "  dart analyze packages/contracts packages/infrastructure apps/server"
echo "  flutter test apps/server/test"
