import 'package:domain/src/competition/competition_id.dart';
import 'package:shared/shared.dart';

/// The identity of a [GamificationEvent] — one row of the append-only
/// `gamification.events` stream (migration 0053).
///
/// A value object (Coding Standards ADR, Section 2), canonically a UUID
/// matching that table's primary key. Distinct from the event's
/// `dedupe_key`, which is the natural idempotency key the emitter composes:
/// the id identifies the row, the dedupe key identifies the fact.
final class GamificationEventId extends EntityId {
  /// Creates a [GamificationEventId] from its canonical UUID string.
  const GamificationEventId(super.value);

  /// Parses a [GamificationEventId] from an untrusted [raw] string, returning
  /// a validation [AppError] when it is absent or not a canonical UUID.
  static Result<GamificationEventId> tryParse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const Result.err(
        AppError.validation(
          'gamification.event_id_empty',
          'Gamification event id is required',
        ),
      );
    }
    if (!uuidPattern.hasMatch(raw)) {
      return const Result.err(
        AppError.validation(
          'gamification.event_id_malformed',
          'Gamification event id must be a UUID',
        ),
      );
    }
    return Result.ok(GamificationEventId(raw));
  }
}
