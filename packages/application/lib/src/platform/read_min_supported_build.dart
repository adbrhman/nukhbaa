/// Use-case: the oldest Android build the service still supports, as the
/// server's build gate reads it (script 148).
library;

import 'package:application/src/platform/ports/app_update_policy_store.dart';
import 'package:shared/shared.dart';

/// Reads the minimum an admin set (migration 0113), or `Ok(null)` when none
/// is set.
///
/// No principal: the gate runs before any route, on every request, and the
/// minimum is already public (`GET /app/latest-build` sends it). The store
/// it is given is the composition root's cached one, so the gate costs no
/// query per request.
///
/// Never throws; returns a typed [Result].
final class ReadMinSupportedBuild {
  /// Creates the use-case over [policy].
  const ReadMinSupportedBuild(this._policy);

  final AppUpdatePolicyStore _policy;

  /// The minimum, or `Ok(null)`.
  Future<Result<int?>> call() => _policy.minSupportedBuild();
}
