import 'package:application/src/identity/authorization.dart';
import 'package:application/src/scoring/ports/fixture_score_counter.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: how many players were scored on each of up to
/// [maxFixtures] fixtures, in one read (batch 156). Backs the admin's
/// "المباريات المحتسبة", which used to send one request per match played
/// this month, six at a time, and held most of the server's database
/// connections while it did. Admin only.
///
/// Never throws; returns a typed [Result].
final class AdminCountFixtureScores {
  /// Creates the use-case over its collaborator.
  const AdminCountFixtureScores({required FixtureScoreCounter counter})
    : _counter = counter;

  final FixtureScoreCounter _counter;

  /// The most fixtures one read may name.
  static const int maxFixtures = 200;

  /// Counts the scores of [fixtureIds] (a repeated id once) for
  /// [principal]. More than [maxFixtures] ids is `admin.too_many_fixtures`;
  /// an id that is not a fixture id is refused like everywhere else.
  Future<Result<Map<String, int>>> call({
    required AuthenticatedUser principal,
    required List<String> fixtureIds,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final Set<String> unique = fixtureIds.toSet();
    if (unique.length > maxFixtures) {
      return const Result.err(
        AppError.validation(
          'admin.too_many_fixtures',
          'At most $maxFixtures fixtures in one read',
        ),
      );
    }
    final List<FixtureRef> fixtures = <FixtureRef>[];
    for (final String id in unique) {
      final Result<FixtureRef> parsed = FixtureRef.tryParse(id);
      switch (parsed) {
        case Ok<FixtureRef>(:final value):
          fixtures.add(value);
        case Err<FixtureRef>(:final error):
          return Result.err(error);
      }
    }
    if (fixtures.isEmpty) return const Result.ok(<String, int>{});
    return _counter.countByFixtures(fixtures);
  }
}
