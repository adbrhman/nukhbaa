import 'package:application/src/common/clock.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/leaderboard/ports/sporting_season_standings_reader.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: the current sporting season's standings -- every monthly
/// contest from September to August summed per user, most points first. The
/// user on top when August closes is the season champion.
///
/// A read-side projection over the per-month fixture standings: the points
/// are the ones `ScoreFixture` stored, only summed across months here.
/// Visible to any signed-in user, like the monthly board every user is
/// enrolled in.
///
/// Never throws; returns a typed [Result].
final class GetSportingSeasonLeaderboard {
  /// Creates the use-case over its collaborators.
  const GetSportingSeasonLeaderboard({
    required SportingSeasonStandingsReader reader,
    required Clock clock,
  }) : _reader = reader,
       _clock = clock;

  final SportingSeasonStandingsReader _reader;
  final Clock _clock;

  /// Returns the ranked board of the season containing "now".
  Future<Result<SportingSeasonLeaderboard>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final season = SportingSeason.containing(_clock.nowUtc());
    final standingsResult = await _reader.standings(season);
    if (standingsResult is Err<List<SportingSeasonStanding>>) {
      return Result.err(standingsResult.error);
    }

    return SportingSeasonLeaderboard.rank(
      season: season,
      standings: (standingsResult as Ok<List<SportingSeasonStanding>>).value,
    );
  }
}
