/// Use-case: bind a device's push-notification token to the caller.
library;

import 'package:application/src/identity/authorization.dart';
import 'package:application/src/notification/ports/device_token_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Lets an authenticated user register their OWN device's FCM token (mirrors
/// [SetAvatar]/[UpdateDisplayName]: every user may register a token for
/// themselves; there is no "register a token for another user" surface, so
/// no repository lookup is needed to establish authority — the owner of a
/// device registration is always its own principal).
///
/// A token is a Firebase-issued opaque string, not a platform business
/// value: the only validation here is "non-empty" and "platform is one this
/// backend can send to" — the format itself is Firebase's contract, not
/// ours. The repository upserts by token (migration 0039), so a re-register
/// (app reinstall, token refresh, a different user signing in on the same
/// device) is idempotent by construction, never a duplicate row.
///
/// Never throws; returns a typed [Result].
final class RegisterDeviceToken {
  /// Creates the use-case over its [DeviceTokenRepository] port.
  const RegisterDeviceToken({required DeviceTokenRepository deviceTokens})
    : _deviceTokens = deviceTokens;

  final DeviceTokenRepository _deviceTokens;

  /// Supported values for [platform] (Android only today; migration 0039's
  /// check constraint is the backstop behind this, not the first line of
  /// defense).
  static const Set<String> supportedPlatforms = {'android', 'ios'};

  /// Registers [token] for [principal] on [platform].
  Future<Result<void>> call({
    required AuthenticatedUser principal,
    required String token,
    required String platform,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    if (token.trim().isEmpty) {
      return const Result.err(
        AppError.validation(
          'notification.device_token_empty',
          'رمز الجهاز فارغ',
        ),
      );
    }
    if (!supportedPlatforms.contains(platform)) {
      return const Result.err(
        AppError.validation(
          'notification.device_token_platform_unsupported',
          'المنصة غير مدعومة',
        ),
      );
    }

    return _deviceTokens.upsert(
      userId: principal.userId,
      token: token,
      platform: platform,
    );
  }
}
