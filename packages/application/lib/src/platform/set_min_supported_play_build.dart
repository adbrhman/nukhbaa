/// Use-case: the admin sets or clears the oldest Google Play build the
/// service still supports (migration 0206, script 253).
library;

import 'package:application/src/identity/authorization.dart';
import 'package:application/src/platform/ports/app_update_policy_store.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Stores [buildNumber] as the oldest supported Play build, or clears it
/// (null). Admin only.
///
/// Unlike the APK minimum ([SetMinSupportedBuild]), the admin types the
/// number: the Play bundle is built by its own run, whose number no APK
/// release carries, and only the admin knows which versionCode Google
/// Play has made live. A number below 1 or above Play's own ceiling
/// ([maxVersionCode]) is refused, `app.play_build_invalid`, nothing
/// stored. The [policy] is the Play store
/// (`PostgresPlayUpdatePolicyStore`), never the APK's.
///
/// Never throws; returns a typed [Result] with the stored minimum.
final class SetMinSupportedPlayBuild {
  /// Creates the use-case over the Play [policy].
  const SetMinSupportedPlayBuild(this._policy);

  final AppUpdatePolicyStore _policy;

  /// The highest versionCode Google Play accepts.
  static const int maxVersionCode = 2100000000;

  /// Runs the use-case for [principal].
  Future<Result<int?>> call({
    required AuthenticatedUser principal,
    required int? buildNumber,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    if (buildNumber != null &&
        (buildNumber < 1 || buildNumber > maxVersionCode)) {
      return const Result.err(
        AppError.validation(
          'app.play_build_invalid',
          'اكتب رقم إصدار Google Play صحيحًا أكبر من صفر، أو اتركه فارغًا '
              'لإلغاء الحد.',
        ),
      );
    }
    return _policy.setMinSupportedBuild(
      buildNumber: buildNumber,
      by: principal.userId,
    );
  }
}
