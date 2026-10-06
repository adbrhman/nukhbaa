import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Write port over `gamification.screen_views` (migration 0093).
///
/// General contract (Application ADR section 2): never throws, maps driver
/// failures to [ErrorKind.transient].
abstract interface class ScreenViewRepository {
  /// Adds [opens] (screen name to how many times it was opened) to
  /// [userId]'s rows of the Riyadh day [day], a UTC midnight carrying that
  /// day's date. A screen already counted that day is summed into its row.
  Future<Result<void>> add({
    required UserId userId,
    required DateTime day,
    required Map<String, int> opens,
    required DateTime reportedAt,
  });
}
