/// Use-case: a player deletes his own account (audit M-05, script 113).
library;

import 'package:application/src/identity/ports/account_deletion.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Lets a player delete his OWN account, as Google Play requires. Self-only:
/// the account comes from the verified principal, never the request. The
/// owner's decision (M-05): the account is anonymised, its points and
/// predictions stay in the record. Deleting twice converges: the second call
/// finds nothing to do and still succeeds.
final class DeleteMyAccount {
  /// Creates the use-case over its [AccountDeletion] port.
  const DeleteMyAccount({required AccountDeletion accounts})
    : _accounts = accounts;

  final AccountDeletion _accounts;

  /// Deletes [principal]'s account. Only a plain player's: an admin's is
  /// refused (`identity.admin_account_kept`), so the platform cannot lose an
  /// admin to a tap in the app.
  Future<Result<void>> call({required AuthenticatedUser principal}) async {
    if (principal.role != PlatformRole.user) {
      return const Result.err(
        AppError.invariant(
          'identity.admin_account_kept',
          'An administrator account cannot be deleted from the app',
        ),
      );
    }
    final Result<bool> result = await _accounts.anonymise(principal.userId);
    return switch (result) {
      Ok<bool>() => const Result.ok(null),
      Err<bool>(:final error) => Result.err(error),
    };
  }
}
