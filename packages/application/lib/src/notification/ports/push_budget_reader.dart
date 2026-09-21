import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Read port for the shared weekly budget of proactive pushes (plan P3-3,
/// [NotificationGate.weeklyBudget]).
///
/// General contract (Application ADR section 2): never throws, maps driver
/// failures to [ErrorKind.transient].
abstract interface class PushBudgetReader {
  /// How many proactive pushes each of [userIds] was sent on or after
  /// [fromDate] (`YYYY-MM-DD`, a Riyadh day), every type together: the daily
  /// reminders in `reminder_sends` (0040) plus the rows of `proactive_sends`
  /// (0066). A user with none is absent from the map.
  Future<Result<Map<String, int>>> sentCountsSince({
    required List<UserId> userIds,
    required String fromDate,
  });
}
