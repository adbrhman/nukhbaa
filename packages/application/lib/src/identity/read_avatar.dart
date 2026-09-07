/// Use-case: read a platform user's stored profile picture.
library;

import 'package:application/src/identity/authorization.dart';
import 'package:application/src/identity/ports/user_directory.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Serves any authenticated caller's request for ANOTHER user's profile
/// picture (or their own) -- avatars are visible platform-wide by design
/// (Decided 2026-09-07: report-then-remove moderation, no per-viewer gate).
/// The only authority check is that the caller is an authenticated platform
/// user at all; unlike [SetAvatar]/[ClearAvatar] there is no ownership
/// condition, since [targetUserId] need not equal [principal]'s own id.
final class ReadAvatar {
  /// Creates the use-case over its [UserDirectory] port.
  const ReadAvatar({required UserDirectory userDirectory})
    : _userDirectory = userDirectory;

  final UserDirectory _userDirectory;

  /// Reads [targetUserId]'s stored picture, or `Ok(null)` when they have
  /// none.
  Future<Result<StoredAvatar?>> call({
    required AuthenticatedUser principal,
    required UserId targetUserId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    return _userDirectory.readAvatar(targetUserId);
  }
}
