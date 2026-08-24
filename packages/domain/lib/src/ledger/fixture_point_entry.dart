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
