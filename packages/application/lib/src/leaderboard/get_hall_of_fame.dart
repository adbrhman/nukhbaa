import 'package:application/src/identity/authorization.dart';
import 'package:application/src/leaderboard/ports/leaderboard_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: the platform-wide, all-time standings ("Hall of Fame")
/// (Application ADR §2: query separated from command; mirrors
/// [GetSeasonLeaderboard] exactly, aggregated across every season instead of
/// scoped to one).
///
/// A Hall of Fame is a **read-side projection** over the ratified append-only
/// ledger (Axiom 5) — the use-case reads the per-user point totals via
/// [LeaderboardRepository.allTimeStandings] and ranks them with the pure
/// domain [HallOfFame.rank] (total order: points desc, user-id asc;
/// standard-competition "1224" ranks). It never computes or stores a points
/// total of its own.
///
/// **Visibility (deliberately public, unlike the season board):** any
/// authenticated user may view it — there is no membership gate, because a
/// Hall of Fame's whole purpose is to be seen by everyone (Layer 1 platform
/// authority only: `Authorization.requireRole(principal, PlatformRole.user)`).
///
/// Never throws; returns a typed [Result].
final class GetHallOfFame {
  /// Creates the use-case over its collaborator.
  const GetHallOfFame({required LeaderboardRepository leaderboardRepository})
    : _leaderboard = leaderboardRepository;

  final LeaderboardRepository _leaderboard;

  /// The default page size for a request that does not specify [limit].
  static const int defaultLimit = 100;

  /// The maximum page size any caller may request — an untrusted [limit] is
  /// clamped into `[1, maxLimit]` rather than rejected, so this read can never
  /// trigger an unbounded scan.
  static const int maxLimit = 500;

  /// Returns the ranked [HallOfFame], visible to any authenticated
  /// [principal].
  Future<Result<HallOfFame>> call({
    required AuthenticatedUser principal,
    int? limit,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final clamped = _clamp(limit);

    final standingsResult = await _leaderboard.allTimeStandings(limit: clamped);
    if (standingsResult is Err<List<HallOfFameEntry>>) {
      return Result.err(standingsResult.error);
    }
    final projections = (standingsResult as Ok<List<HallOfFameEntry>>).value;

    return HallOfFame.rank(projections: projections);
  }

  static int _clamp(int? requested) {
    if (requested == null || requested < 1) {
      return defaultLimit;
    }
    if (requested > maxLimit) {
      return maxLimit;
    }
    return requested;
  }
}
