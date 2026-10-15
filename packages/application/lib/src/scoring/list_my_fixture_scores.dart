import 'package:application/src/identity/authorization.dart';
import 'package:application/src/scoring/my_fixture_score.dart';
import 'package:application/src/scoring/ports/my_fixture_score_reader.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: the caller's own grades, points and final scores, for
/// every prediction that has one, in a single read (script 75).
///
/// The app showed them by asking [GetFixtureScores] once per finished match
/// card and once per row of "my predictions" -- four queries and every
/// participant's score each time, again every 2 minutes while a score was
/// pending -- which timed out 389 times on the night of 2026-10-14/15.
///
/// **Visibility:** always the caller's own rows; the reader is scoped to
/// `principal.userId`, so nothing here can reveal another user's score.
/// A prediction on a fixture an admin hid may be among them: the app only
/// shows a row next to a prediction `GET /me/fixture-predictions` listed.
///
/// Never throws; returns a typed [Result].
final class ListMyFixtureScores {
  /// Creates the use-case over its port.
  const ListMyFixtureScores({required MyFixtureScoreReader reader})
    : _reader = reader;

  final MyFixtureScoreReader _reader;

  /// Lists every [MyFixtureScore] of [principal].
  Future<Result<List<MyFixtureScore>>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    return _reader.listByUser(principal.userId);
  }
}
