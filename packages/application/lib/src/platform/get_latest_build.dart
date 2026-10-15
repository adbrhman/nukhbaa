import 'package:application/src/platform/ports/app_update_policy_store.dart';
import 'package:application/src/platform/ports/build_info_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Use-case: report the newest published Android build so the client can
/// prompt an in-app update (Platform update-check slice), with the oldest
/// build the service still supports when an admin set one (batch 147).
final class GetLatestBuild {
  /// Creates the use-case with its required [BuildInfoRepository] port and,
  /// optionally, the [policy] that holds the oldest supported build.
  const GetLatestBuild(
    this._buildInfoRepository, {
    AppUpdatePolicyStore? policy,
  }) : _policy = policy;

  final BuildInfoRepository _buildInfoRepository;
  final AppUpdatePolicyStore? _policy;

  /// Executes the check. Never throws; returns a typed [Result]. A minimum
  /// that cannot be read is left out: the release is still answered, and
  /// nobody is held back by a database hiccup.
  Future<Result<LatestBuild>> call() async {
    final Result<LatestBuild> latest = await _buildInfoRepository.fetchLatest();
    final AppUpdatePolicyStore? policy = _policy;
    if (latest is! Ok<LatestBuild> || policy == null) return latest;
    final Result<int?> minimum = await policy.minSupportedBuild();
    return switch (minimum) {
      Ok<int?>(:final value) => Result.ok(
        latest.value.withMinSupportedBuild(value),
      ),
      Err<int?>() => latest,
    };
  }
}
