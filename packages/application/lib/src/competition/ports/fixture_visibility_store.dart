import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Hides fixtures from the players and shows them again (migration 0098,
/// `competition.fixture_schedules.hidden_at`).
///
/// Its own port rather than a method on `FixtureScheduleRepository`: a
/// schedule correction must never touch visibility, and visibility must
/// never touch the schedule.
abstract interface class FixtureVisibilityStore {
  /// Hides [fixtures] when [hidden] is true, shows them otherwise, and
  /// answers the fixtures whose state actually changed: one already in the
  /// asked state, or with no schedule row, is left out.
  Future<Result<List<FixtureRef>>> setHidden(
    List<FixtureRef> fixtures, {
    required bool hidden,
  });
}
