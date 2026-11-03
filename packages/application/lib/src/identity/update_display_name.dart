/// Use-case: choose the caller's own platform display name, once.
library;

import 'package:application/src/identity/authorization.dart';
import 'package:application/src/identity/ports/user_directory.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Lets an authenticated user choose their display name exactly once.
///
/// The platform rule is unchanged: a display name is chosen once and is
/// immutable from then on. Registration chooses it up front; an account
/// created without that step (a first Google sign-in, or a row older than the
/// display-name feature) still carries the name the database assigned on its
/// own ([User.hasAutomaticDisplayName]), and this use-case is where that one
/// choice is made. A name that was already chosen is refused.
///
/// Only the caller's own name (Layer 1 authority); validation lives on the
/// domain ([User.validateDisplayName], then [User.newAccountNameError]: a
/// new account's real name). Never throws; returns a typed [Result].
final class UpdateDisplayName {
  /// Creates the use-case over its [UserDirectory] port.
  const UpdateDisplayName({required UserDirectory userDirectory})
    : _userDirectory = userDirectory;

  final UserDirectory _userDirectory;

  /// Sets [principal]'s display name to [displayName], if it was never
  /// chosen.
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
    final String chosen = (validated as Ok<String>).value;

    final Result<User?> current = await _userDirectory.findUser(
      principal.userId,
    );
    final User user;
    switch (current) {
      case Err<User?>(:final error):
        return Result.err(error);
      case Ok<User?>(value: null):
        return const Result.err(
          AppError.invariant('identity.user_not_found', 'الحساب غير موجود'),
        );
      case Ok<User?>(value: final User found):
        user = found;
    }

    if (!user.hasAutomaticDisplayName) {
      return const Result.err(_immutable);
    }
    if (chosen == user.automaticDisplayName) {
      return const Result.err(
        AppError.validation(
          'identity.display_name_is_default',
          'اختر اسماً يعرفك به الآخرون، غير بداية بريدك الإلكتروني',
        ),
      );
    }

    // A new account's real name (2026-11-02, refined 2026-11-03). Checked
    // last, so a name already chosen still answers that it is immutable.
    final AppError? refused = User.newAccountNameError(chosen);
    if (refused != null) {
      return Result.err(refused);
    }

    // Written only while the name read above is still the stored one
    // (audit 33): of two requests that both read the automatic name, the
    // second matches nothing and is refused instead of overwriting the
    // first's choice.
    final Result<User?> saved = await _userDirectory.replaceDisplayName(
      principal.userId,
      expected: user.displayName,
      displayName: chosen,
    );
    return switch (saved) {
      Ok<User?>(value: final User written) => Result.ok(written),
      Ok<User?>() => const Result.err(_immutable),
      Err<User?>(:final error) => Result.err(error),
    };
  }
}

/// A name already chosen: found so on reading, or written by another
/// request between the read and the write.
const AppError _immutable = AppError.invariant(
  'identity.display_name_immutable',
  'اخترت اسمك مسبقاً، ولا يمكن تغييره',
);
