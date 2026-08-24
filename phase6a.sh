#!/usr/bin/env bash
# Phase 6a — Ledger/Social/Notification expand (Axiom 4 Amendment: Round ->
# monthly competition, per-fixture Ledger/Social/Notification siblings).
# Additive only: new domain entities (FixturePointEntry, FixtureReaction),
# additive enum values (EntryKind.fixtureScore, NotificationKind.fixtureScored,
# ActivityEventType.fixtureScored), new application ports
# (FixtureLedgerRepository, FixtureReactionRepository) and new use-cases
# (PostFixtureToLedger, ReactToFixture, RemoveFixtureReaction,
# ListFixtureReactions, NotifyFixtureScored). Nothing existing is deleted or
# renamed; GetRoundLeaderboard has no fixture sibling (a single-fixture
# "leaderboard" is not meaningful -- ranking stays a season-scoped concern).
set -euo pipefail
cd "${1:-.}"

mkdir -p packages/domain/lib/src/ledger packages/domain/lib/src/social
mkdir -p packages/domain/test/ledger packages/domain/test/social
mkdir -p packages/application/lib/src/ledger/ports
mkdir -p packages/application/lib/src/social/ports
mkdir -p packages/application/lib/src/notification
mkdir -p packages/application/test/ledger packages/application/test/social

# =============================================================================
# DOMAIN
# =============================================================================

# -----------------------------------------------------------------------------
# packages/domain/lib/src/ledger/fixture_point_entry.dart
# -----------------------------------------------------------------------------
cat > 'packages/domain/lib/src/ledger/fixture_point_entry.dart' <<'NUKHBA_EOF'
import 'package:domain/src/competition/fixture_ref.dart';
import 'package:domain/src/competition/participant_id.dart';
import 'package:domain/src/ledger/entry_kind.dart';
import 'package:domain/src/ledger/point_entry_id.dart';
import 'package:shared/shared.dart';

/// A single, **immutable, append-only** movement of points in the Ledger,
/// scoped to one **fixture** rather than one round (docs/project-context.md,
/// Axiom 4 Amendment) — the per-fixture sibling of [PointEntry].
///
/// [PointEntry.roundId] is a required, non-nullable, non-mutable field
/// (Axiom 5: an entry, once constructed, is final — there is no copy-with),
/// so a fixture-scoped credit cannot be expressed by that type without
/// breaking every existing caller. This is therefore a **separate aggregate**
/// naming its origin by [fixture] instead of a round id — exactly the same
/// reasoning that produced `FixturePrediction` alongside `Prediction` and
/// `ParticipantFixtureScore` alongside `RoundScore` in earlier phases of this
/// amendment.
///
/// Carries no group reference (Axiom 4: the one score, ranked everywhere).
/// [amount] is server-computed only (Axiom 2) and non-negative for
/// [EntryKind.fixtureScore] (mirrors the scored fixture's
/// `ParticipantFixtureScore.points`); a [EntryKind.correction] may be
/// negative. There is deliberately no mutation API — correcting a past
/// mistake means appending a new [EntryKind.correction] entry, never
/// changing an existing one (Axiom 5), enforced structurally here and
/// physically by the migration (Axiom 6, the backstop).
///
/// Pure and immutable; value-comparable by all fields.
final class FixturePointEntry {
  const FixturePointEntry._({
    required this.id,
    required this.participantId,
    required this.fixture,
    required this.kind,
    required this.amount,
    required this.sourceRef,
    required this.occurredAt,
  });

  /// Rehydrates an entry from already-trusted stored fields (infrastructure
  /// mapper). The stored values were validated by [create] (and the DB check
  /// constraints, Axiom 6) before they were ever written, so no
  /// re-validation is performed here.
  const FixturePointEntry.fromStored({
    required this.id,
    required this.participantId,
    required this.fixture,
    required this.kind,
    required this.amount,
    required this.sourceRef,
    required this.occurredAt,
  });

  /// Creates a validated fixture-scoped point entry from server-side inputs.
  ///
  /// Enforced invariants (kept total — no exception escapes a command
  /// path), mirroring [PointEntry.create]:
  /// * [occurredAt] must be UTC.
  /// * a [kind] that [EntryKind.requiresNonNegativeAmount] (a
  ///   [EntryKind.fixtureScore] credit) must have a non-negative [amount].
  /// * [sourceRef] must be non-empty.
  static Result<FixturePointEntry> create({
    required PointEntryId id,
    required ParticipantId participantId,
    required FixtureRef fixture,
    required EntryKind kind,
    required int amount,
    required String sourceRef,
    required DateTime occurredAt,
  }) {
    if (!occurredAt.isUtc) {
      return const Result.err(
        AppError.validation(
          'ledger.entry_occurred_at_not_utc',
          'occurredAt must be provided in UTC',
        ),
      );
    }
    if (sourceRef.isEmpty) {
      return const Result.err(
        AppError.validation(
          'ledger.entry_source_ref_empty',
          'A point entry must carry a non-empty source reference',
        ),
      );
    }
    if (kind.requiresNonNegativeAmount && amount < 0) {
      return Result.err(
        AppError.validation(
          'ledger.entry_amount_negative',
          'A ${kind.wireValue} entry amount must not be negative',
        ),
      );
    }
    return Result.ok(
      FixturePointEntry._(
        id: id,
        participantId: participantId,
        fixture: fixture,
        kind: kind,
        amount: amount,
        sourceRef: sourceRef,
        occurredAt: occurredAt,
      ),
    );
  }

  /// The entry's own stable identity.
  final PointEntryId id;

  /// The participant this movement belongs to (by id).
  final ParticipantId participantId;

  /// The fixture this movement derives from (by id — Axiom 3). Combined with
  /// [participantId] and [kind] this is the append-only dedupe key for a
  /// [EntryKind.fixtureScore] credit (Axiom 4: no double-credit on re-post).
  final FixtureRef fixture;

  /// Why the points moved (the closed [EntryKind] classification).
  final EntryKind kind;

  /// The signed point movement. Server-computed only (Axiom 2).
  final int amount;

  /// The provenance handle recording where this entry came from. Never
  /// empty; server-set.
  final String sourceRef;

  /// When the movement occurred (UTC), for stream ordering and audit.
  final DateTime occurredAt;

  @override
  bool operator ==(Object other) =>
      other is FixturePointEntry &&
      other.id == id &&
      other.participantId == participantId &&
      other.fixture == fixture &&
      other.kind == kind &&
      other.amount == amount &&
      other.sourceRef == sourceRef &&
      other.occurredAt == occurredAt;

  @override
  int get hashCode => Object.hash(
    id,
    participantId,
    fixture,
    kind,
    amount,
    sourceRef,
    occurredAt,
  );

  @override
  String toString() =>
      'FixturePointEntry(${id.value}, participant: ${participantId.value}, '
      'fixture: ${fixture.value}, ${kind.wireValue}, amount: $amount)';
}
NUKHBA_EOF

# -----------------------------------------------------------------------------
# packages/domain/lib/src/social/fixture_reaction.dart
# -----------------------------------------------------------------------------
cat > 'packages/domain/lib/src/social/fixture_reaction.dart' <<'NUKHBA_EOF'
import 'package:domain/src/competition/fixture_ref.dart';
import 'package:domain/src/group/group_id.dart';
import 'package:domain/src/identity/user_id.dart';
import 'package:domain/src/social/reaction_emoji.dart';
import 'package:domain/src/social/reaction_id.dart';
import 'package:shared/shared.dart';

/// A member's emoji reaction to a **fixture**-result within a private group
/// (docs/project-context.md, Axiom 4 Amendment) — the per-fixture sibling of
/// [Reaction].
///
/// [Reaction.roundId] is a required, non-nullable, non-mutable field, so a
/// fixture-scoped reaction cannot be expressed by that type without breaking
/// every existing caller (mirrors why [FixturePointEntry] is a separate
/// aggregate rather than an edit to [PointEntry]). This targets a
/// *fixture*-result by [fixture] instead of a round id; a member has at most
/// one live reaction per fixture-result within a group — uniqueness of
/// `(groupId, fixture, userId)` is enforced structurally in the schema + the
/// use-case, not re-checked here (mirror of [Reaction]).
///
/// Carries no points field (Axiom 5) and no open-graph edge (ADR-001).
/// Pure and immutable; a member swapping their emoji is an idempotent upsert
/// on the unique key (see [changeEmoji]), never a second row.
final class FixtureReaction {
  const FixtureReaction._({
    required this.id,
    required this.groupId,
    required this.fixture,
    required this.userId,
    required this.emoji,
    required this.reactedAt,
  });

  /// Rehydrates a [FixtureReaction] from already-trusted stored fields (used
  /// by the infrastructure mapper). Performs no validation beyond typing —
  /// callers creating a *new* reaction from untrusted input must use
  /// [create].
  const FixtureReaction.fromStored({
    required this.id,
    required this.groupId,
    required this.fixture,
    required this.userId,
    required this.emoji,
    required this.reactedAt,
  });

  /// Creates a new fixture reaction from validated inputs.
  static Result<FixtureReaction> create({
    required ReactionId id,
    required GroupId groupId,
    required FixtureRef fixture,
    required UserId userId,
    required ReactionEmoji emoji,
    required DateTime reactedAt,
  }) {
    if (!reactedAt.isUtc) {
      return const Result.err(
        AppError.validation(
          'social.reaction_reacted_at_not_utc',
          'reactedAt must be provided in UTC',
        ),
      );
    }
    return Result.ok(
      FixtureReaction._(
        id: id,
        groupId: groupId,
        fixture: fixture,
        userId: userId,
        emoji: emoji,
        reactedAt: reactedAt,
      ),
    );
  }

  /// The reaction identity.
  final ReactionId id;

  /// The group this reaction is scoped to (the social container).
  final GroupId groupId;

  /// The fixture-result this reaction targets (by id — Axiom 3).
  final FixtureRef fixture;

  /// The reacting member's platform user id (bound from the verified token
  /// by the use-case, never a request body — Security ADR §2).
  final UserId userId;

  /// The chosen emoji from the closed set.
  final ReactionEmoji emoji;

  /// When the reaction was made or last changed (UTC).
  final DateTime reactedAt;

  /// Returns a copy carrying a new [emoji] and refreshed [reactedAt] (a
  /// member swapping their reaction). The identity + `(groupId, fixture,
  /// userId)` key are unchanged, so persisting this is an idempotent upsert
  /// on the unique key, not a second row. [reactedAt] must be UTC.
  Result<FixtureReaction> changeEmoji(
    ReactionEmoji newEmoji,
    DateTime reactedAt,
  ) {
    if (!reactedAt.isUtc) {
      return const Result.err(
        AppError.validation(
          'social.reaction_reacted_at_not_utc',
          'reactedAt must be provided in UTC',
        ),
      );
    }
    return Result.ok(
      FixtureReaction._(
        id: id,
        groupId: groupId,
        fixture: fixture,
        userId: userId,
        emoji: newEmoji,
        reactedAt: reactedAt,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FixtureReaction &&
      other.id == id &&
      other.groupId == groupId &&
      other.fixture == fixture &&
      other.userId == userId &&
      other.emoji == emoji &&
      other.reactedAt == reactedAt;

  @override
  int get hashCode =>
      Object.hash(id, groupId, fixture, userId, emoji, reactedAt);

  @override
  String toString() =>
      'FixtureReaction(${id.value}, group: ${groupId.value}, '
      'fixture: ${fixture.value}, user: ${userId.value}, '
      '${emoji.wireValue})';
}
NUKHBA_EOF

# -----------------------------------------------------------------------------
# Additive patch: EntryKind.fixtureScore (packages/domain/lib/src/ledger/entry_kind.dart)
# -----------------------------------------------------------------------------
python3 - <<'PYEOF'
import pathlib
p = pathlib.Path('packages/domain/lib/src/ledger/entry_kind.dart')
s = p.read_text()

if 'fixtureScore' not in s:
    old_enum = "enum EntryKind {\n  /// The points credited for a participant's scored round.\n  roundScore,\n"
    assert old_enum in s, 'enum EntryKind anchor not found'
    new_enum = old_enum + (
        "\n  /// The points credited for a participant's scored fixture (Axiom 4\n"
        "  /// Amendment; the per-fixture sibling of [roundScore]).\n"
        "  fixtureScore,\n"
    )
    s = s.replace(old_enum, new_enum, 1)

    old_wire = "  String get wireValue => switch (this) {\n    EntryKind.roundScore => 'round_score',\n"
    assert old_wire in s, 'wireValue switch anchor not found'
    new_wire = old_wire + "    EntryKind.fixtureScore => 'fixture_score',\n"
    s = s.replace(old_wire, new_wire, 1)

    old_nonneg = "bool get requiresNonNegativeAmount => this == EntryKind.roundScore;"
    assert old_nonneg in s, 'requiresNonNegativeAmount anchor not found'
    new_nonneg = (
        "bool get requiresNonNegativeAmount =>\n"
        "      this == EntryKind.roundScore || this == EntryKind.fixtureScore;"
    )
    s = s.replace(old_nonneg, new_nonneg, 1)

    old_dedupe = "bool get isDedupedPerRound => this == EntryKind.roundScore;"
    assert old_dedupe in s, 'isDedupedPerRound anchor not found'
    new_dedupe = (
        "bool get isDedupedPerRound => this == EntryKind.roundScore;\n\n"
        "  /// Whether an entry of this kind participates in the fixture-scoped\n"
        "  /// append-only dedupe key (Axiom 4 Amendment; the per-fixture sibling of\n"
        "  /// [isDedupedPerRound]). Only [fixtureScore] is deduped on\n"
        "  /// `(participant, fixture, kind)`.\n"
        "  bool get isDedupedPerFixture => this == EntryKind.fixtureScore;"
    )
    s = s.replace(old_dedupe, new_dedupe, 1)

    p.write_text(s)
    print('entry_kind.dart patched OK')
else:
    print('entry_kind.dart already patched, skipping')
PYEOF

# -----------------------------------------------------------------------------
# Additive patch: NotificationKind.fixtureScored
# -----------------------------------------------------------------------------
python3 - <<'PYEOF'
import pathlib
p = pathlib.Path('packages/domain/lib/src/notification/notification_kind.dart')
s = p.read_text()

if 'fixtureScored' not in s:
    old_enum = "  reactionReceived;\n"
    assert s.count(old_enum) == 1, 'enum terminator anchor not found/unique'
    new_enum = (
        "  reactionReceived,\n\n"
        "  /// A fixture the recipient predicted was scored (its result was posted)\n"
        "  /// (docs/project-context.md, Axiom 4 Amendment — the per-fixture sibling\n"
        "  /// of [roundScored]). Subject references the scored fixture.\n"
        "  fixtureScored;\n"
    )
    s = s.replace(old_enum, new_enum, 1)

    old_wire = "    NotificationKind.reactionReceived => 'reaction_received',\n"
    assert old_wire in s, 'wireValue switch anchor not found'
    new_wire = old_wire + "    NotificationKind.fixtureScored => 'fixture_scored',\n"
    s = s.replace(old_wire, new_wire, 1)

    p.write_text(s)
    print('notification_kind.dart patched OK')
else:
    print('notification_kind.dart already patched, skipping')
PYEOF

# -----------------------------------------------------------------------------
# Additive patch: NotificationSubject.fixtureScored (+ fixture field)
# -----------------------------------------------------------------------------
python3 - <<'PYEOF'
import pathlib
p = pathlib.Path('packages/domain/lib/src/notification/notification_subject.dart')
s = p.read_text()

if 'fixtureScored' not in s:
    old_import = "import 'package:domain/src/competition/round_id.dart';\n"
    assert old_import in s, 'round_id import anchor not found'
    new_import = "import 'package:domain/src/competition/fixture_ref.dart';\n" + old_import
    s = s.replace(old_import, new_import, 1)

    old_ctor = (
        "  const NotificationSubject._({\n"
        "    required this.kind,\n"
        "    this.roundId,\n"
        "    this.groupId,\n"
        "    this.actorUserId,\n"
        "  });\n"
    )
    assert old_ctor in s, 'private ctor anchor not found'
    new_ctor = (
        "  const NotificationSubject._({\n"
        "    required this.kind,\n"
        "    this.roundId,\n"
        "    this.groupId,\n"
        "    this.actorUserId,\n"
        "    this.fixture,\n"
        "  });\n"
    )
    s = s.replace(old_ctor, new_ctor, 1)

    old_stored = (
        "  const NotificationSubject.fromStored({\n"
        "    required this.kind,\n"
        "    this.roundId,\n"
        "    this.groupId,\n"
        "    this.actorUserId,\n"
        "  });\n"
    )
    assert old_stored in s, 'fromStored ctor anchor not found'
    new_stored = (
        "  const NotificationSubject.fromStored({\n"
        "    required this.kind,\n"
        "    this.roundId,\n"
        "    this.groupId,\n"
        "    this.actorUserId,\n"
        "    this.fixture,\n"
        "  });\n"
    )
    s = s.replace(old_stored, new_stored, 1)

    old_factory_anchor = "  /// The kind this subject belongs to (matches the owning notification's kind).\n"
    assert old_factory_anchor in s, 'field-section anchor not found'
    new_factory = (
        "  /// The subject of a `fixtureScored` notification — the scored [fixture]\n"
        "  /// (docs/project-context.md, Axiom 4 Amendment; the per-fixture sibling of\n"
        "  /// [roundScored]).\n"
        "  static NotificationSubject fixtureScored({required FixtureRef fixture}) =>\n"
        "      NotificationSubject._(\n"
        "        kind: NotificationKind.fixtureScored,\n"
        "        fixture: fixture,\n"
        "      );\n\n"
    ) + old_factory_anchor
    s = s.replace(old_factory_anchor, new_factory, 1)

    old_field = "  final UserId? actorUserId;\n"
    assert old_field in s, 'actorUserId field anchor not found'
    new_field = old_field + (
        "\n  /// The fixture involved (`fixtureScored`); else null (Axiom 4 Amendment).\n"
        "  final FixtureRef? fixture;\n"
    )
    s = s.replace(old_field, new_field, 1)

    old_dedupe = "    NotificationKind.reactionReceived =>\n"
    assert old_dedupe in s, 'dedupeRef switch anchor not found'
    new_dedupe = (
        "    NotificationKind.fixtureScored => 'fixture:${fixture!.value}',\n"
        + old_dedupe
    )
    s = s.replace(old_dedupe, new_dedupe, 1)

    old_eq = "      other.actorUserId == actorUserId;\n"
    assert old_eq in s, 'operator== anchor not found'
    new_eq = "      other.actorUserId == actorUserId &&\n      other.fixture == fixture;\n"
    s = s.replace(old_eq, new_eq, 1)

    old_hash = "int get hashCode => Object.hash(kind, roundId, groupId, actorUserId);"
    assert old_hash in s, 'hashCode anchor not found'
    new_hash = (
        "int get hashCode =>\n"
        "      Object.hash(kind, roundId, groupId, actorUserId, fixture);"
    )
    s = s.replace(old_hash, new_hash, 1)

    p.write_text(s)
    print('notification_subject.dart patched OK')
else:
    print('notification_subject.dart already patched, skipping')
PYEOF

# -----------------------------------------------------------------------------
# Additive patch: ActivityEventType.fixtureScored
# -----------------------------------------------------------------------------
python3 - <<'PYEOF'
import pathlib
p = pathlib.Path('packages/application/lib/src/social/activity_event.dart')
s = p.read_text()

if 'fixtureScored' not in s:
    old_import = "import 'package:domain/domain.dart';\n"
    assert old_import in s, 'domain import anchor not found'

    old_enum = "  rankShift;\n"
    assert s.count(old_enum) == 1, 'enum terminator anchor not found/unique'
    new_enum = (
        "  rankShift,\n\n"
        "  /// A fixture in a competition the group's members play was scored (its\n"
        "  /// result was posted) (docs/project-context.md, Axiom 4 Amendment; the\n"
        "  /// per-fixture sibling of [roundScored]). Carries the fixture id.\n"
        "  fixtureScored;\n"
    )
    s = s.replace(old_enum, new_enum, 1)

    old_wire = "    ActivityEventType.rankShift => 'rank_shift',\n"
    assert old_wire in s, 'wireValue switch anchor not found'
    new_wire = old_wire + "    ActivityEventType.fixtureScored => 'fixture_scored',\n"
    s = s.replace(old_wire, new_wire, 1)

    old_factory_anchor = "  /// The event type discriminator.\n"
    assert old_factory_anchor in s, 'field-section anchor not found'
    new_factory = (
        "  /// A fixture-scored event (Axiom 4 Amendment).\n"
        "  static ActivityEvent fixtureScored({\n"
        "    required GroupId groupId,\n"
        "    required FixtureRef fixture,\n"
        "    required DateTime occurredAt,\n"
        "  }) => ActivityEvent._(\n"
        "    type: ActivityEventType.fixtureScored,\n"
        "    groupId: groupId,\n"
        "    fixture: fixture,\n"
        "    occurredAt: occurredAt,\n"
        "  );\n\n"
    ) + old_factory_anchor
    s = s.replace(old_factory_anchor, new_factory, 1)

    old_ctor = (
        "  const ActivityEvent._({\n"
        "    required this.type,\n"
        "    required this.groupId,\n"
        "    required this.occurredAt,\n"
        "    this.roundId,\n"
        "    this.userId,\n"
        "    this.oldRank,\n"
        "    this.newRank,\n"
        "  });\n"
    )
    assert old_ctor in s, 'private ctor anchor not found'
    new_ctor = (
        "  const ActivityEvent._({\n"
        "    required this.type,\n"
        "    required this.groupId,\n"
        "    required this.occurredAt,\n"
        "    this.roundId,\n"
        "    this.userId,\n"
        "    this.oldRank,\n"
        "    this.newRank,\n"
        "    this.fixture,\n"
        "  });\n"
    )
    s = s.replace(old_ctor, new_ctor, 1)

    old_field = "  /// The round involved (for `roundScored`); else null.\n  final RoundId? roundId;\n"
    assert old_field in s, 'roundId field anchor not found'
    new_field = old_field + (
        "\n  /// The fixture involved (for `fixtureScored`); else null (Axiom 4\n"
        "  /// Amendment).\n"
        "  final FixtureRef? fixture;\n"
    )
    s = s.replace(old_field, new_field, 1)

    old_eq = "      other.newRank == newRank;\n"
    assert old_eq in s, 'operator== anchor not found'
    new_eq = "      other.newRank == newRank &&\n      other.fixture == fixture;\n"
    s = s.replace(old_eq, new_eq, 1)

    old_hash = "Object.hash(type, groupId, occurredAt, roundId, userId, oldRank, newRank);"
    assert old_hash in s, 'hashCode anchor not found'
    new_hash = (
        "Object.hash(\n"
        "        type, groupId, occurredAt, roundId, userId, oldRank, newRank, fixture,\n"
        "      );"
    )
    s = s.replace(old_hash, new_hash, 1)

    p.write_text(s)
    print('activity_event.dart patched OK')
else:
    print('activity_event.dart already patched, skipping')
PYEOF

# -----------------------------------------------------------------------------
# domain.dart exports (additive)
# -----------------------------------------------------------------------------
D=packages/domain/lib/domain.dart
grep -q "src/ledger/fixture_point_entry.dart" "$D" || \
  sed -i "\#export 'src/ledger/point_entry.dart';#i export 'src/ledger/fixture_point_entry.dart';" "$D"
grep -q "src/social/fixture_reaction.dart" "$D" || \
  sed -i "\#export 'src/social/reaction.dart';#i export 'src/social/fixture_reaction.dart';" "$D"

# -----------------------------------------------------------------------------
# domain unit tests
# -----------------------------------------------------------------------------
cat > 'packages/domain/test/ledger/fixture_point_entry_test.dart' <<'NUKHBA_EOF'
import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('FixturePointEntry.create', () {
    test('creates a valid fixtureScore credit', () {
      final result = FixturePointEntry.create(
        id: const PointEntryId('11111111-1111-1111-1111-111111111111'),
        participantId: const ParticipantId('participant-1'),
        fixture: const FixtureRef('22222222-2222-2222-2222-222222222222'),
        kind: EntryKind.fixtureScore,
        amount: 6,
        sourceRef: 'fixture_score:f1:p1',
        occurredAt: DateTime.utc(2026, 8, 1),
      );
      expect(result, isA<Ok<FixturePointEntry>>());
    });

    test('rejects a non-UTC occurredAt', () {
      final result = FixturePointEntry.create(
        id: const PointEntryId('11111111-1111-1111-1111-111111111111'),
        participantId: const ParticipantId('participant-1'),
        fixture: const FixtureRef('22222222-2222-2222-2222-222222222222'),
        kind: EntryKind.fixtureScore,
        amount: 3,
        sourceRef: 'fixture_score:f1:p1',
        occurredAt: DateTime(2026, 8, 1),
      );
      expect(result, isA<Err<FixturePointEntry>>());
      expect(
        (result as Err<FixturePointEntry>).error.code,
        'ledger.entry_occurred_at_not_utc',
      );
    });

    test('rejects a negative amount for a fixtureScore credit', () {
      final result = FixturePointEntry.create(
        id: const PointEntryId('11111111-1111-1111-1111-111111111111'),
        participantId: const ParticipantId('participant-1'),
        fixture: const FixtureRef('22222222-2222-2222-2222-222222222222'),
        kind: EntryKind.fixtureScore,
        amount: -1,
        sourceRef: 'fixture_score:f1:p1',
        occurredAt: DateTime.utc(2026, 8, 1),
      );
      expect(result, isA<Err<FixturePointEntry>>());
      expect(
        (result as Err<FixturePointEntry>).error.code,
        'ledger.entry_amount_negative',
      );
    });

    test('allows a negative amount for a correction', () {
      final result = FixturePointEntry.create(
        id: const PointEntryId('11111111-1111-1111-1111-111111111111'),
        participantId: const ParticipantId('participant-1'),
        fixture: const FixtureRef('22222222-2222-2222-2222-222222222222'),
        kind: EntryKind.correction,
        amount: -3,
        sourceRef: 'correction:justification',
        occurredAt: DateTime.utc(2026, 8, 1),
      );
      expect(result, isA<Ok<FixturePointEntry>>());
    });

    test('rejects an empty sourceRef', () {
      final result = FixturePointEntry.create(
        id: const PointEntryId('11111111-1111-1111-1111-111111111111'),
        participantId: const ParticipantId('participant-1'),
        fixture: const FixtureRef('22222222-2222-2222-2222-222222222222'),
        kind: EntryKind.fixtureScore,
        amount: 3,
        sourceRef: '',
        occurredAt: DateTime.utc(2026, 8, 1),
      );
      expect(result, isA<Err<FixturePointEntry>>());
      expect(
        (result as Err<FixturePointEntry>).error.code,
        'ledger.entry_source_ref_empty',
      );
    });
  });

  group('EntryKind.fixtureScore', () {
    test('round-trips through wireValue/tryParse', () {
      expect(EntryKind.fixtureScore.wireValue, 'fixture_score');
      final parsed = EntryKind.tryParse('fixture_score');
      expect(parsed, isA<Ok<EntryKind>>());
      expect((parsed as Ok<EntryKind>).value, EntryKind.fixtureScore);
    });

    test('requires a non-negative amount', () {
      expect(EntryKind.fixtureScore.requiresNonNegativeAmount, isTrue);
    });

    test('is deduped per fixture, not per round', () {
      expect(EntryKind.fixtureScore.isDedupedPerFixture, isTrue);
      expect(EntryKind.fixtureScore.isDedupedPerRound, isFalse);
    });
  });
}
NUKHBA_EOF

cat > 'packages/domain/test/social/fixture_reaction_test.dart' <<'NUKHBA_EOF'
import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('FixtureReaction.create', () {
    test('creates a valid reaction', () {
      final emoji = ReactionEmoji.tryParse('🔥') as Ok<ReactionEmoji>;
      final result = FixtureReaction.create(
        id: const ReactionId('11111111-1111-1111-1111-111111111111'),
        groupId: const GroupId('22222222-2222-2222-2222-222222222222'),
        fixture: const FixtureRef('33333333-3333-3333-3333-333333333333'),
        userId: const UserId('44444444-4444-4444-4444-444444444444'),
        emoji: emoji.value,
        reactedAt: DateTime.utc(2026, 8, 1),
      );
      expect(result, isA<Ok<FixtureReaction>>());
    });

    test('rejects a non-UTC reactedAt', () {
      final emoji = ReactionEmoji.tryParse('🔥') as Ok<ReactionEmoji>;
      final result = FixtureReaction.create(
        id: const ReactionId('11111111-1111-1111-1111-111111111111'),
        groupId: const GroupId('22222222-2222-2222-2222-222222222222'),
        fixture: const FixtureRef('33333333-3333-3333-3333-333333333333'),
        userId: const UserId('44444444-4444-4444-4444-444444444444'),
        emoji: emoji.value,
        reactedAt: DateTime(2026, 8, 1),
      );
      expect(result, isA<Err<FixtureReaction>>());
    });
  });

  group('FixtureReaction.changeEmoji', () {
    test('preserves identity while swapping the emoji', () {
      final first = ReactionEmoji.tryParse('🔥') as Ok<ReactionEmoji>;
      final second = ReactionEmoji.tryParse('😂') as Ok<ReactionEmoji>;
      final created =
          FixtureReaction.create(
                id: const ReactionId('11111111-1111-1111-1111-111111111111'),
                groupId: const GroupId('22222222-2222-2222-2222-222222222222'),
                fixture: const FixtureRef(
                  '33333333-3333-3333-3333-333333333333',
                ),
                userId: const UserId('44444444-4444-4444-4444-444444444444'),
                emoji: first.value,
                reactedAt: DateTime.utc(2026, 8, 1),
              )
              as Ok<FixtureReaction>;

      final changed = created.value.changeEmoji(
        second.value,
        DateTime.utc(2026, 8, 2),
      );

      expect(changed, isA<Ok<FixtureReaction>>());
      final value = (changed as Ok<FixtureReaction>).value;
      expect(value.id, created.value.id);
      expect(value.fixture, created.value.fixture);
      expect(value.emoji, second.value);
    });
  });
}
NUKHBA_EOF

echo "Domain layer done."

# =============================================================================
# APPLICATION
# =============================================================================

# -----------------------------------------------------------------------------
# packages/application/lib/src/ledger/ports/fixture_ledger_repository.dart
# -----------------------------------------------------------------------------
cat > 'packages/application/lib/src/ledger/ports/fixture_ledger_repository.dart' <<'NUKHBA_EOF'
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Persistence port for the append-only **fixture-scoped** Ledger
/// (docs/project-context.md, Axiom 4 Amendment) — the per-fixture sibling of
/// [LedgerRepository], kept as its own port for the same reason
/// [FixturePredictionRepository] is separate from `PredictionRepository`:
/// editing an existing `abstract interface class` would break every current
/// implementer.
///
/// **Known gap (documented, not silently accepted):** [LedgerBalance] is
/// currently projected only from [LedgerRepository.listEntries] (round-scoped
/// entries). A participant's true balance now spans two streams
/// (round-scoped legacy entries + fixture-scoped entries via this port).
/// Unifying the balance projection across both is deferred to Phase 7
/// (contract) of this amendment, mirroring the reproducibility gap already
/// documented on `ScoreFixture`.
///
/// General contract for every method (Application ADR §2), mirroring
/// [LedgerRepository]:
/// * MUST NOT throw — every outcome is a typed [Result].
/// * MUST map infrastructure failures to [ErrorKind.transient].
/// * MUST map a storage-only integrity conflict to [ErrorKind.invariant].
abstract interface class FixtureLedgerRepository {
  /// Appends [entries] to the fixture-scoped ledger **atomically** and
  /// **idempotently** on the natural dedupe key `(participant_id, fixture_id,
  /// entry_kind)` for a kind that [EntryKind.isDedupedPerFixture] (a
  /// `fixture_score` credit): re-appending an already-present row is
  /// skipped, never duplicated (Axiom 4).
  ///
  /// Returns the subset of [entries] that were **actually appended**.
  Future<Result<List<FixturePointEntry>>> appendEntries(
    List<FixturePointEntry> entries,
  );

  /// Lists every [FixturePointEntry] for [participantId], in stream order
  /// (occurred-at ascending, then entry id for a stable tie-break).
  Future<Result<List<FixturePointEntry>>> listEntries(
    ParticipantId participantId,
  );
}
NUKHBA_EOF

# -----------------------------------------------------------------------------
# packages/application/lib/src/ledger/post_fixture_to_ledger.dart
# -----------------------------------------------------------------------------
cat > 'packages/application/lib/src/ledger/post_fixture_to_ledger.dart' <<'NUKHBA_EOF'
import 'package:application/src/common/clock.dart';
import 'package:application/src/common/id_generator.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/ledger/ports/fixture_ledger_repository.dart';
import 'package:application/src/scoring/ports/fixture_score_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

final class PostFixtureToLedger {
  const PostFixtureToLedger({
    required FixtureScoreRepository fixtureScoreRepository,
    required FixtureLedgerRepository fixtureLedgerRepository,
    required IdGenerator idGenerator,
    required Clock clock,
  }) : _scores = fixtureScoreRepository,
       _ledger = fixtureLedgerRepository,
       _ids = idGenerator,
       _clock = clock;

  final FixtureScoreRepository _scores;
  final FixtureLedgerRepository _ledger;
  final IdGenerator _ids;
  final Clock _clock;

  Future<Result<List<FixturePointEntry>>> call({
    required AuthenticatedUser principal,
    required String fixtureId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final fixtureRefResult = FixtureRef.tryParse(fixtureId);
    if (fixtureRefResult is Err<FixtureRef>) {
      return Result.err(fixtureRefResult.error);
    }
    final fixture = (fixtureRefResult as Ok<FixtureRef>).value;

    final scoresResult = await _scores.listByFixture(fixture);
    if (scoresResult is Err<List<ParticipantFixtureScore>>) {
      return Result.err(scoresResult.error);
    }
    final fixtureScores =
        (scoresResult as Ok<List<ParticipantFixtureScore>>).value;

    final now = _clock.nowUtc();
    final entries = <FixturePointEntry>[];
    for (final score in fixtureScores) {
      final idResult = PointEntryId.tryParse(_ids.newUuid());
      if (idResult is Err<PointEntryId>) {
        return Result.err(idResult.error);
      }
      final entryResult = FixturePointEntry.create(
        id: (idResult as Ok<PointEntryId>).value,
        participantId: score.participantId,
        fixture: fixture,
        kind: EntryKind.fixtureScore,
        amount: score.points,
        sourceRef:
            'fixture_score:${fixture.value}:${score.participantId.value}',
        occurredAt: now,
      );
      if (entryResult is Err<FixturePointEntry>) {
        return Result.err(entryResult.error);
      }
      entries.add((entryResult as Ok<FixturePointEntry>).value);
    }

    return _ledger.appendEntries(entries);
  }
}
NUKHBA_EOF

# -----------------------------------------------------------------------------
# packages/application/lib/src/social/ports/fixture_reaction_repository.dart
# -----------------------------------------------------------------------------
cat > 'packages/application/lib/src/social/ports/fixture_reaction_repository.dart' <<'NUKHBA_EOF'
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

abstract interface class FixtureReactionRepository {
  Future<Result<void>> upsertReaction(FixtureReaction reaction);

  Future<Result<FixtureReaction?>> findReaction(
    GroupId groupId,
    FixtureRef fixture,
    UserId userId,
  );

  Future<Result<List<FixtureReaction>>> listReactionsForFixture(
    GroupId groupId,
    FixtureRef fixture,
  );

  Future<Result<bool>> removeReaction(
    GroupId groupId,
    FixtureRef fixture,
    UserId userId,
  );
}
NUKHBA_EOF

# -----------------------------------------------------------------------------
# packages/application/lib/src/social/react_to_fixture.dart
# -----------------------------------------------------------------------------
cat > 'packages/application/lib/src/social/react_to_fixture.dart' <<'NUKHBA_EOF'
import 'package:application/src/common/clock.dart';
import 'package:application/src/common/id_generator.dart';
import 'package:application/src/group/ports/group_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/social/ports/fixture_reaction_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

final class ReactToFixture {
  const ReactToFixture({
    required FixtureReactionRepository reactions,
    required GroupRepository groups,
    required IdGenerator idGenerator,
    required Clock clock,
  }) : _reactions = reactions,
       _groups = groups,
       _idGenerator = idGenerator,
       _clock = clock;

  final FixtureReactionRepository _reactions;
  final GroupRepository _groups;
  final IdGenerator _idGenerator;
  final Clock _clock;

  Future<Result<FixtureReaction>> call({
    required AuthenticatedUser principal,
    required String groupId,
    required String fixtureId,
    required String emoji,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final gIdResult = GroupId.tryParse(groupId);
    if (gIdResult is Err<GroupId>) {
      return Result.err(gIdResult.error);
    }
    final gId = (gIdResult as Ok<GroupId>).value;

    final fixtureRefResult = FixtureRef.tryParse(fixtureId);
    if (fixtureRefResult is Err<FixtureRef>) {
      return Result.err(fixtureRefResult.error);
    }
    final fixture = (fixtureRefResult as Ok<FixtureRef>).value;

    final emojiResult = ReactionEmoji.tryParse(emoji);
    if (emojiResult is Err<ReactionEmoji>) {
      return Result.err(emojiResult.error);
    }
    final chosen = (emojiResult as Ok<ReactionEmoji>).value;

    final gate = await _requireMember(gId, principal.userId);
    if (gate is Err<void>) {
      return Result.err(gate.error);
    }

    final existingResult = await _reactions.findReaction(
      gId,
      fixture,
      principal.userId,
    );
    if (existingResult is Err<FixtureReaction?>) {
      return Result.err(existingResult.error);
    }
    final existing = (existingResult as Ok<FixtureReaction?>).value;

    final now = _clock.nowUtc();
    final Result<FixtureReaction> built;
    if (existing != null) {
      built = existing.changeEmoji(chosen, now);
    } else {
      final idResult = ReactionId.tryParse(_idGenerator.newUuid());
      if (idResult is Err<ReactionId>) {
        return Result.err(idResult.error);
      }
      built = FixtureReaction.create(
        id: (idResult as Ok<ReactionId>).value,
        groupId: gId,
        fixture: fixture,
        userId: principal.userId,
        emoji: chosen,
        reactedAt: now,
      );
    }
    if (built is Err<FixtureReaction>) {
      return Result.err(built.error);
    }
    final reaction = (built as Ok<FixtureReaction>).value;

    final saved = await _reactions.upsertReaction(reaction);
    return switch (saved) {
      Ok<void>() => Result.ok(reaction),
      Err<void>(:final error) => await _resolveConflict(
        error,
        gId,
        fixture,
        principal.userId,
        chosen,
      ),
    };
  }

  Future<Result<void>> _requireMember(GroupId groupId, UserId userId) async {
    final membershipResult = await _groups.findMembership(groupId, userId);
    if (membershipResult is Err<GroupMembership?>) {
      return Result.err(membershipResult.error);
    }
    final membership = (membershipResult as Ok<GroupMembership?>).value;
    if (membership == null) {
      return const Result.err(
        AppError.authorization(
          'group.not_a_member',
          'Only a member of the group may react in it',
        ),
      );
    }
    return const Result.ok(null);
  }

  Future<Result<FixtureReaction>> _resolveConflict(
    AppError error,
    GroupId groupId,
    FixtureRef fixture,
    UserId userId,
    ReactionEmoji chosen,
  ) async {
    if (error.code != 'social.reaction_conflict') {
      return Result.err(error);
    }
    final reread = await _reactions.findReaction(groupId, fixture, userId);
    if (reread is Err<FixtureReaction?>) {
      return Result.err(reread.error);
    }
    final winning = (reread as Ok<FixtureReaction?>).value;
    if (winning == null) {
      return Result.err(error);
    }
    final updated = winning.changeEmoji(chosen, _clock.nowUtc());
    if (updated is Err<FixtureReaction>) {
      return Result.err(updated.error);
    }
    final reaction = (updated as Ok<FixtureReaction>).value;
    final resaved = await _reactions.upsertReaction(reaction);
    return switch (resaved) {
      Ok<void>() => Result.ok(reaction),
      Err<void>(:final error) => Result.err(error),
    };
  }
}
NUKHBA_EOF

# -----------------------------------------------------------------------------
# packages/application/lib/src/social/remove_fixture_reaction.dart
# -----------------------------------------------------------------------------
cat > 'packages/application/lib/src/social/remove_fixture_reaction.dart' <<'NUKHBA_EOF'
import 'package:application/src/group/ports/group_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/social/ports/fixture_reaction_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

final class RemoveFixtureReaction {
  const RemoveFixtureReaction({
    required FixtureReactionRepository reactions,
    required GroupRepository groups,
  }) : _reactions = reactions,
       _groups = groups;

  final FixtureReactionRepository _reactions;
  final GroupRepository _groups;

  Future<Result<bool>> call({
    required AuthenticatedUser principal,
    required String groupId,
    required String fixtureId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final gIdResult = GroupId.tryParse(groupId);
    if (gIdResult is Err<GroupId>) {
      return Result.err(gIdResult.error);
    }
    final gId = (gIdResult as Ok<GroupId>).value;

    final fixtureRefResult = FixtureRef.tryParse(fixtureId);
    if (fixtureRefResult is Err<FixtureRef>) {
      return Result.err(fixtureRefResult.error);
    }
    final fixture = (fixtureRefResult as Ok<FixtureRef>).value;

    final membershipResult = await _groups.findMembership(
      gId,
      principal.userId,
    );
    if (membershipResult is Err<GroupMembership?>) {
      return Result.err(membershipResult.error);
    }
    final membership = (membershipResult as Ok<GroupMembership?>).value;
    if (membership == null) {
      return const Result.err(
        AppError.authorization(
          'group.not_a_member',
          'Only a member of the group may remove a reaction in it',
        ),
      );
    }

    return _reactions.removeReaction(gId, fixture, principal.userId);
  }
}
NUKHBA_EOF

# -----------------------------------------------------------------------------
# packages/application/lib/src/social/list_fixture_reactions.dart
# -----------------------------------------------------------------------------
cat > 'packages/application/lib/src/social/list_fixture_reactions.dart' <<'NUKHBA_EOF'
import 'package:application/src/group/ports/group_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/social/ports/fixture_reaction_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

final class ListFixtureReactions {
  const ListFixtureReactions({
    required FixtureReactionRepository reactions,
    required GroupRepository groups,
  }) : _reactions = reactions,
       _groups = groups;

  final FixtureReactionRepository _reactions;
  final GroupRepository _groups;

  Future<Result<List<FixtureReaction>>> call({
    required AuthenticatedUser principal,
    required String groupId,
    required String fixtureId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final gIdResult = GroupId.tryParse(groupId);
    if (gIdResult is Err<GroupId>) {
      return Result.err(gIdResult.error);
    }
    final gId = (gIdResult as Ok<GroupId>).value;

    final fixtureRefResult = FixtureRef.tryParse(fixtureId);
    if (fixtureRefResult is Err<FixtureRef>) {
      return Result.err(fixtureRefResult.error);
    }
    final fixture = (fixtureRefResult as Ok<FixtureRef>).value;

    final membershipResult = await _groups.findMembership(
      gId,
      principal.userId,
    );
    if (membershipResult is Err<GroupMembership?>) {
      return Result.err(membershipResult.error);
    }
    final membership = (membershipResult as Ok<GroupMembership?>).value;
    if (membership == null) {
      return const Result.err(
        AppError.authorization(
          'group.not_a_member',
          'Only a member of the group may view its reactions',
        ),
      );
    }

    return _reactions.listReactionsForFixture(gId, fixture);
  }
}
NUKHBA_EOF

# -----------------------------------------------------------------------------
# packages/application/lib/src/notification/notify_fixture_scored.dart
# -----------------------------------------------------------------------------
cat > 'packages/application/lib/src/notification/notify_fixture_scored.dart' <<'NUKHBA_EOF'
import 'package:application/src/notification/create_notification.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

final class NotifyFixtureScored {
  const NotifyFixtureScored({required CreateNotification create})
    : _create = create;

  final CreateNotification _create;

  Future<Result<bool>> call({
    required UserId recipientId,
    required String fixtureId,
  }) async {
    final fixtureRefResult = FixtureRef.tryParse(fixtureId);
    if (fixtureRefResult is Err<FixtureRef>) {
      return Result.err(fixtureRefResult.error);
    }
    final fixture = (fixtureRefResult as Ok<FixtureRef>).value;

    return _create(
      recipientId: recipientId,
      kind: NotificationKind.fixtureScored,
      subject: NotificationSubject.fixtureScored(fixture: fixture),
    );
  }
}
NUKHBA_EOF

echo "Application layer done."

# -----------------------------------------------------------------------------
# application.dart exports (additive)
# -----------------------------------------------------------------------------
A=packages/application/lib/application.dart
grep -q "src/ledger/ports/fixture_ledger_repository.dart" "$A" || \
  sed -i "\#export 'src/ledger/ports/ledger_repository.dart';#i export 'src/ledger/ports/fixture_ledger_repository.dart';" "$A"
grep -q "src/ledger/post_fixture_to_ledger.dart" "$A" || \
  sed -i "\#export 'src/ledger/post_round_to_ledger.dart';#i export 'src/ledger/post_fixture_to_ledger.dart';" "$A"
grep -q "src/social/ports/fixture_reaction_repository.dart" "$A" || \
  sed -i "\#export 'src/social/ports/reaction_repository.dart';#i export 'src/social/ports/fixture_reaction_repository.dart';" "$A"
grep -q "src/social/react_to_fixture.dart" "$A" || \
  sed -i "\#export 'src/social/react_to_round.dart';#i export 'src/social/react_to_fixture.dart';" "$A"
grep -q "src/social/remove_fixture_reaction.dart" "$A" || \
  sed -i "\#export 'src/social/remove_reaction.dart';#i export 'src/social/remove_fixture_reaction.dart';" "$A"
grep -q "src/social/list_fixture_reactions.dart" "$A" || \
  sed -i "\#export 'src/social/list_round_reactions.dart';#i export 'src/social/list_fixture_reactions.dart';" "$A"
grep -q "src/notification/notify_fixture_scored.dart" "$A" || \
  sed -i "\#export 'src/notification/notify_round_scored.dart';#i export 'src/notification/notify_fixture_scored.dart';" "$A"

echo ""
echo "DONE — الآن نفّذ:"
echo "  flutter pub get"
echo "  dart analyze packages/domain packages/application"
echo "  flutter test packages/domain/test/ledger packages/domain/test/social"
