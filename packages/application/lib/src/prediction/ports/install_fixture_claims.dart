import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Port for "one account per match on one phone" (migration 0197, decided
/// by the owner on 2026-11-02): the first account that predicts a match
/// from an install holds that match on it.
///
/// MUST NOT throw; a driver failure is [ErrorKind.transient].
abstract interface class InstallFixtureClaims {
  /// Claims [fixture] on the install [installId] for [userId] when no
  /// account holds it there yet, and answers the account that holds it now:
  /// [userId] after a first claim or a repeat, another account otherwise.
  Future<Result<UserId>> claim({
    required String installId,
    required FixtureRef fixture,
    required UserId userId,
  });
}
