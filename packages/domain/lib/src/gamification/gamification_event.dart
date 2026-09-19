import 'package:domain/src/competition/fixture_ref.dart';
import 'package:domain/src/gamification/gamification_event_id.dart';
import 'package:domain/src/gamification/gamification_event_type.dart';
import 'package:domain/src/identity/user_id.dart';
import 'package:domain/src/prediction/prediction_id.dart';
import 'package:shared/shared.dart';

/// One immutable fact in the gamification stream (migration 0053).
///
/// It carries NO points. An award is an entry in `ledger.*`; this event may
/// only point at the thing it concerns through [refType]/[refId]. Two ledgers
/// would mean two disagreeing standings — the dual-scoring-path risk the
/// Axiom 4 Amendment closed.
///
/// [dedupeKey] is what makes every emitter safe to re-run: the database holds
/// a unique index on it, so a replayed job writes nothing the second time.
final class GamificationEvent {
  const GamificationEvent._({
    required this.id,
    required this.userId,
    required this.type,
    required this.dedupeKey,
    required this.occurredAt,
    required this.refType,
    required this.refId,
    required this.payload,
    required this.ruleVersion,
  });

  /// The generation of the point rules in force since the system was switched
  /// on. Decided 2026-09-19: there is no backfill of earlier predictions, so
  /// no event exists with a lower version.
  static const int currentRuleVersion = 1;

  /// A first-time prediction submission.
  ///
  /// [id] comes from the `IdGenerator` port; the dedupe key is the prediction
  /// itself, so an amend or a replayed insert never records a second
  /// placement.
  static Result<GamificationEvent> predictionPlaced({
    required String id,
    required UserId userId,
    required PredictionId predictionId,
    required FixtureRef fixture,
    required DateTime occurredAt,
  }) {
    final idResult = GamificationEventId.tryParse(id);
    if (idResult is Err<GamificationEventId>) {
      return Result.err(idResult.error);
    }
    return Result.ok(
      GamificationEvent._(
        id: (idResult as Ok<GamificationEventId>).value,
        userId: userId,
        type: GamificationEventType.predictionPlaced,
        dedupeKey:
            '${GamificationEventType.predictionPlaced.wireName}:'
            '${predictionId.value}',
        occurredAt: occurredAt.toUtc(),
        refType: 'fixture',
        refId: fixture.value,
        payload: const <String, Object?>{},
        ruleVersion: currentRuleVersion,
      ),
    );
  }

  /// A participant covered every fixture of the Riyadh match day [day].
  ///
  /// [day] is a UTC midnight carrying that Riyadh day's date; the caller
  /// derives it (`riyadhDayOf`) because the domain has no clock and no zone.
  ///
  /// The dedupe key is the user and the day, which is what makes the rule
  /// "what completes is never un-completed" hold mechanically: the day is
  /// recorded once however many predictions complete it, a re-evaluation
  /// after a late fixture is added writes nothing, and the stream rejects
  /// UPDATE and DELETE for every role.
  ///
  /// [fixtureCount] is how many fixtures the day held at the moment it
  /// completed — audit only, since a later count may legitimately differ.
  static Result<GamificationEvent> dailyChallengeCompleted({
    required String id,
    required UserId userId,
    required DateTime day,
    required int fixtureCount,
    required DateTime occurredAt,
  }) {
    final idResult = GamificationEventId.tryParse(id);
    if (idResult is Err<GamificationEventId>) {
      return Result.err(idResult.error);
    }
    if (fixtureCount <= 0) {
      return const Result.err(
        AppError.invariant(
          'gamification.daily_challenge_empty_day',
          'A day with no fixtures cannot be completed',
        ),
      );
    }
    final isoDay = _isoDay(day);
    return Result.ok(
      GamificationEvent._(
        id: (idResult as Ok<GamificationEventId>).value,
        userId: userId,
        type: GamificationEventType.dailyChallengeCompleted,
        dedupeKey:
            '${GamificationEventType.dailyChallengeCompleted.wireName}:'
            '${userId.value}:$isoDay',
        occurredAt: occurredAt.toUtc(),
        // About a day, which is not a row anywhere: ref_type and ref_id are
        // both null, and the database enforces that they move together.
        refType: null,
        refId: null,
        payload: <String, Object?>{'day': isoDay, 'fixtures': fixtureCount},
        ruleVersion: currentRuleVersion,
      ),
    );
  }

  static String _isoDay(DateTime day) {
    final utc = day.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
  }

  /// This row's own identity.
  final GamificationEventId id;

  /// Whose event this is.
  final UserId userId;

  /// What happened.
  final GamificationEventType type;

  /// The emitter's idempotency key; unique across the whole stream.
  final String dedupeKey;

  /// What the event is about (`fixture`, `badge`, ...), or `null`.
  final String? refType;

  /// The id of the thing named by [refType], or `null`. Both are null or
  /// both are set — the database enforces the pairing.
  final String? refId;

  /// Anything else worth auditing, stored as `jsonb`.
  final Map<String, Object?> payload;

  /// The rule generation that produced this event.
  final int ruleVersion;

  /// When the fact happened (UTC), not when the row was written.
  final DateTime occurredAt;
}
