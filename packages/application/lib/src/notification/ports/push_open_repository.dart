import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Write port over `notification.push_opens` (migration 0069, plan P3-8).
///
/// General contract (Application ADR section 2): never throws, maps driver
/// failures to [ErrorKind.transient].
abstract interface class PushOpenRepository {
  /// Records that [userId] opened a push whose link was [link].
  Future<Result<void>> record({
    required UserId userId,
    required String link,
    required DateTime openedAt,
  });
}
