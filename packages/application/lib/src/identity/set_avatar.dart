/// Use-case: change the caller's own profile picture.
library;

import 'package:application/src/identity/authorization.dart';
import 'package:application/src/identity/ports/user_directory.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Lets an authenticated user set/replace their OWN profile picture (Layer 1
/// platform authority only -- mirrors [UpdateDisplayName]: every user may
/// change their own picture; there is no "set another user's picture"
/// surface, so no repository lookup is needed to establish that authority --
/// the "owner" of an identity is always its own principal).
///
/// Validation lives on the domain ([User.validateAvatar]); this use-case's
/// only job is the authority check and delegating the write to
/// [UserDirectory.setAvatar]. Never throws; returns a typed [Result].
final class SetAvatar {
  /// Creates the use-case over its [UserDirectory] port.
  const SetAvatar({required UserDirectory userDirectory})
    : _userDirectory = userDirectory;

  final UserDirectory _userDirectory;

  /// Sets [principal]'s picture to [bytes] (already read whole by the
  /// transport), stamped with content type [mime].
  Future<Result<User>> call({
    required AuthenticatedUser principal,
    required List<int> bytes,
    required String mime,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final validated = User.validateAvatar(bytes.length, mime);
    if (validated is Err<void>) {
      return Result.err(validated.error);
    }

    return _userDirectory.setAvatar(principal.userId, bytes, mime);
  }
}
