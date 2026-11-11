import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One account the owner admin hid from every board (script 258,
/// migration 0207).
final class HiddenAccount {
  /// Creates the line.
  const HiddenAccount({required this.user, required this.hiddenAt});

  /// The account.
  final User user;

  /// When it was hidden (UTC).
  final DateTime hiddenAt;
}

/// Port for the owner admin's hidden accounts (script 258, migration 0207):
/// `identity.users.hidden_at`.
///
/// A hidden account signs in, predicts and gets its notifications like any
/// player; the board, head-to-head and scoring readers leave it out wherever
/// they leave out a suspended account.
///
/// MUST NOT throw; an infrastructure failure is transient.
abstract interface class HiddenAccountStore {
  /// Every hidden account, the most recently hidden first.
  Future<Result<List<HiddenAccount>>> list();

  /// Hides [target]. `Ok(false)` when no account has that id. Hiding an
  /// account already hidden keeps its first time.
  Future<Result<bool>> hide(UserId target);

  /// Shows [target] again. `Ok(false)` when no account has that id.
  Future<Result<bool>> show(UserId target);
}
