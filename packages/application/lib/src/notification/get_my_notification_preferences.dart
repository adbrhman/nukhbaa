/// Use-case: read the caller's own notification switches.
library;

import 'package:application/src/identity/authorization.dart';
import 'package:application/src/notification/ports/notification_preference_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Reads the caller's notification switches (P3-1). A caller who never
/// changed anything reads the defaults, all on.
///
/// Only the caller's own, always: the principal is the whole of the
/// authority check, and there is no surface for reading someone else's.
///
/// Never throws; returns a typed [Result].
final class GetMyNotificationPreferences {
  /// Creates the use-case over its repository.
  const GetMyNotificationPreferences({
    required NotificationPreferenceRepository preferences,
  }) : _preferences = preferences;

  final NotificationPreferenceRepository _preferences;

  /// Reads [principal]'s switches.
  Future<Result<NotificationPreferences>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    return _preferences.preferencesOf(principal.userId);
  }
}
