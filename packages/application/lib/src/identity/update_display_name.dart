/// Use-case: change the caller's own platform display name.
library;

import 'package:application/src/identity/authorization.dart';
import 'package:application/src/identity/ports/user_directory.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Lets an authenticated user rename themselves (Layer 1 platform authority
/// only — every user may change their OWN name; there is no "rename another
/// user" surface, mirroring how `RenameGroup` gates on owner-only but here the
/// "owner" of an identity is always its own principal, so no repository
/// lookup is needed to establish that authority).
///
/// Validation lives on the domain ([User.validateDisplayName]); this
/// use-case's only job is the authority check and delegating the write to
/// [UserDirectory.updateDisplayName]. Never throws; returns a typed [Result].
final class UpdateDisplayName {
  /// Creates the use-case over its [UserDirectory] port.
  const UpdateDisplayName({required UserDirectory userDirectory})
    : _userDirectory = userDirectory;

  final UserDirectory _userDirectory;

  /// Renames [principal] to [displayName].
  Future<Result<User>> call({
    required AuthenticatedUser principal,
    required String displayName,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final validated = User.validateDisplayName(displayName);
    if (validated is Err<String>) {
      return Result.err(validated.error);
    }

    return _userDirectory.updateDisplayName(
      principal.userId,
      (validated as Ok<String>).value,
    );
  }
}
