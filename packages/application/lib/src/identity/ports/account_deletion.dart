import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Write port over `identity.delete_account` (migration 0178, audit M-05).
///
/// General contract (Application ADR section 2): never throws, maps driver
/// failures to [ErrorKind.transient].
abstract interface class AccountDeletion {
  /// Anonymises [userId]'s account for good: suspended, its e-mail, name,
  /// picture, push tokens and sign-in erased, its points and predictions
  /// kept. `true` when it was deleted now, `false` when there was nothing to
  /// do (already deleted, or not a plain player's account).
  Future<Result<bool>> anonymise(UserId userId);
}
