import 'package:application/src/platform/ports/app_update_policy_store.dart';
import 'package:application/src/platform/ports/build_info_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Use-case: report the newest published Android build so the client can
/// prompt an in-app update (Platform update-check slice), with the oldest
/// build the service still supports when an admin set one (batch 147),
/// and the oldest Google Play build, which has its own minimum (migration
/// 0206, script 253).
final class GetLatestBuild {
  /// Creates the use-case with its required [BuildInfoRepository] port and,
  /// optionally, the [policy] that holds the oldest supported APK build and
  /// the [playPolicy] that holds the oldest supported Play build.
  const GetLatestBuild(
    this._buildInfoRepository, {
    AppUpdatePolicyStore? policy,
    AppUpdatePolicyStore? playPolicy,
  }) : _policy = policy,
       _playPolicy = playPolicy;

  final BuildInfoRepository _buildInfoRepository;
  final AppUpdatePolicyStore? _policy;
  final AppUpdatePolicyStore? _playPolicy;

  /// Executes the check. Never throws; returns a typed [Result]. A minimum
  /// that cannot be read is left out: the release is still answered, and
  /// nobody is held back by a database hiccup.
  Future<Result<LatestBuild>> call() async {
    final Result<LatestBuild> latest = await _buildInfoRepository.fetchLatest();
    final AppUpdatePolicyStore? policy = _policy;
    final AppUpdatePolicyStore? playPolicy = _playPolicy;
    if (latest is! Ok<LatestBuild> || (policy == null && playPolicy == null)) {
      return latest;
    }
    LatestBuild build = latest.value;
    if (policy != null) {
      final Result<int?> minimum = await policy.minSupportedBuild();
      if (minimum case Ok<int?>(:final value)) {
        build = build.withMinSupportedBuild(value);
      }
    }
    if (playPolicy != null) {
      final Result<int?> minimum = await playPolicy.minSupportedBuild();
      if (minimum case Ok<int?>(:final value)) {
        build = build.withMinSupportedPlayBuild(value);
      }
    }
    return Result.ok(build);
  }
}
