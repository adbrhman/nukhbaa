/// Use-case: remove the caller's own profile picture.
library;

import 'package:application/src/identity/authorization.dart';
import 'package:application/src/identity/ports/user_directory.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Lets an authenticated user remove their OWN profile picture. Mirrors
/// [SetAvatar]/[UpdateDisplayName]: self-only authority, no repository lookup
/// needed. Delegates the idempotent removal to [UserDirectory.clearAvatar] --
/// clearing an absent picture succeeds, so a retried removal converges
/// instead of erroring on a state the caller already wanted.
final class ClearAvatar {
  /// Creates the use-case over its [UserDirectory] port.
  const ClearAvatar({required UserDirectory userDirectory})
    : _userDirectory = userDirectory;

  final UserDirectory _userDirectory;

  /// Removes [principal]'s current picture, if any.
  Future<Result<User>> call({required AuthenticatedUser principal}) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    return _userDirectory.clearAvatar(principal.userId);
  }
}
