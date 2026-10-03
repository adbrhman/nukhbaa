import 'package:shared/shared.dart';

/// Port over `ops.claim_error_alert()` (migration 0089): whether the admins
/// hear about one occurrence of an error, and why.
///
/// General contract (Application ADR section 2): never throws, maps driver
/// failures to [ErrorKind.transient].
abstract interface class ErrorAlertRepository {
  /// Claims the alert for the error [groupId] after an occurrence ([isNew]:
  /// its first; [reopened]: a fixed error came back). Answers the reason --
  /// `reopened`, `new_critical`, `new_in_release` or `hourly_spike` -- or
  /// null when there is nothing to tell or the error already alerted within
  /// the hour.
  Future<Result<String?>> claim({
    required int groupId,
    required bool isNew,
    required bool reopened,
    required DateTime at,
  });
}
