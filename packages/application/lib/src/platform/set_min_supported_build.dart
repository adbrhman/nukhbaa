/// Use-case: the admin sets or clears the oldest Android build the service
/// still supports (migration 0113, batch 147).
library;

import 'package:application/src/identity/authorization.dart';
import 'package:application/src/platform/ports/app_update_policy_store.dart';
import 'package:application/src/platform/ports/build_info_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// The update policy after a change: the newest release's build number
/// and the oldest one still supported, either null when unknown or unset.
final class AppUpdatePolicy {
  /// Creates the policy.
  const AppUpdatePolicy({this.latestBuild, this.minSupportedBuild});

  /// The newest published release's build number.
  final int? latestBuild;

  /// The oldest supported build number; null asks nobody to update.
  final int? minSupportedBuild;
}

/// Makes the newest release the oldest supported build ([toLatest]), or
/// clears the minimum. Admin only.
///
/// The minimum is always a published release: an admin cannot type a
/// number, so no build that does not exist can lock everyone out. A newest
/// release with no build number (published before batch 147) is refused,
/// `app.build_number_unknown`.
///
/// Never throws; returns a typed [Result].
final class SetMinSupportedBuild {
  /// Creates the use-case over its collaborators.
  const SetMinSupportedBuild({
    required AppUpdatePolicyStore policy,
    required BuildInfoRepository builds,
  }) : _policy = policy,
       _builds = builds;

  final AppUpdatePolicyStore _policy;
  final BuildInfoRepository _builds;

  /// Runs the use-case for [principal].
  Future<Result<AppUpdatePolicy>> call({
    required AuthenticatedUser principal,
    required bool toLatest,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final Result<LatestBuild> latest = await _builds.fetchLatest();
    final int? latestBuild = switch (latest) {
      Ok<LatestBuild>(:final value) => value.buildNumber,
      Err<LatestBuild>() => null,
    };
    if (toLatest && latest is Err<LatestBuild>) {
      return Result.err(latest.error);
    }
    if (toLatest && latestBuild == null) {
      return const Result.err(
        AppError.validation(
          'app.build_number_unknown',
          'أحدث إصدار منشور لا يحمل رقمًا بعد. انشر إصدارًا جديدًا ثم حاول.',
        ),
      );
    }
    final Result<int?> stored = await _policy.setMinSupportedBuild(
      buildNumber: toLatest ? latestBuild : null,
      by: principal.userId,
    );
    return switch (stored) {
      Ok<int?>(:final value) => Result.ok(
        AppUpdatePolicy(latestBuild: latestBuild, minSupportedBuild: value),
      ),
      Err<int?>(:final error) => Result.err(error),
    };
  }
}
