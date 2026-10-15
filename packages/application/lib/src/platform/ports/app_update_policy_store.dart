import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Port for the oldest Android build the service still supports (migration
/// 0113, batch 147). Implemented in Infrastructure over
/// `ops.app_update_policy`.
abstract interface class AppUpdatePolicyStore {
  /// The oldest supported build number, or `Ok(null)` when none is set.
  Future<Result<int?>> minSupportedBuild();

  /// Stores [buildNumber] (null clears it) as set [by]; answers the stored
  /// value.
  Future<Result<int?>> setMinSupportedBuild({
    required int? buildNumber,
    required UserId by,
  });
}
