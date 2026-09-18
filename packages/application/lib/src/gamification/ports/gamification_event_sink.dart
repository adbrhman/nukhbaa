import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Write port for the append-only gamification stream (migration 0053).
///
/// General contract (Application ADR §2): never throws, maps driver failures
/// to [ErrorKind.transient].
///
/// **Tier-3.** A failure here must never fail the act that produced the
/// event: a user's prediction is saved whether or not its event row was
/// written. Callers therefore ignore the returned error deliberately, and
/// the loss is recoverable — [GamificationEvent.dedupeKey] is unique, so the
/// same event can be re-emitted later without creating a second row.
abstract interface class GamificationEventSink {
  /// Appends [event] to the stream.
  ///
  /// **Idempotent**: an event whose dedupe key is already stored is a no-op
  /// and still returns `Ok`. Nothing here ever updates or deletes a row —
  /// the database rejects both for every role.
  Future<Result<void>> record(GamificationEvent event);
}
