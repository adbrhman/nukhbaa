/// Use-case: change the caller's own notification switches.
library;

import 'package:application/src/identity/authorization.dart';
import 'package:application/src/notification/ports/notification_preference_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Stores the caller's notification switches (P3-1) and returns what was
/// stored.
///
/// The owner comes from the verified principal, never from the request
/// body, so a caller can only ever change their own. Idempotent: storing the
/// same switches twice leaves one row with the same values.
///
/// Never throws; returns a typed [Result].
final class UpdateMyNotificationPreferences {
  /// Creates the use-case over its repository.
  const UpdateMyNotificationPreferences({
    required NotificationPreferenceRepository preferences,
  }) : _preferences = preferences;

  final NotificationPreferenceRepository _preferences;

  /// Stores [preferences] as [principal]'s switches.
  Future<Result<NotificationPreferences>> call({
    required AuthenticatedUser principal,
    required NotificationPreferences preferences,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    return _preferences.save(principal.userId, preferences);
  }
}
