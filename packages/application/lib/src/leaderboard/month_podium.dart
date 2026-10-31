/// The podium of a crowned month: its second and third places (migration
/// 0191, decided by the owner on 2026-11-01).
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/leaderboard/month_final_board.dart';
import 'package:application/src/leaderboard/ports/month_champion_repository.dart';
import 'package:application/src/leaderboard/ports/month_podium_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Use-case: the admin fixes a crowned month's podium. Admin only.
///
/// The second and third places are the first two players of the month's
/// final board after its champion(s), in the board's own order (prediction
/// points, invitation points, exact scorelines, right outcomes, the earlier
/// join): the server decides, the admin only asks. Their figures are frozen
/// as they stood. Setting it again answers the podium already set.
///
/// Refused when the month is not found (`champion.month_not_found`) or not
/// crowned yet (`champion.not_crowned`). A month with fewer players than
/// places gets the places it has.
///
/// Never throws; returns a typed [Result] carrying the month's podium.
final class AdminSetMonthPodium {
  /// Creates the use-case over its collaborators.
  const AdminSetMonthPodium({
    required MonthChampionRepository champions,
    required MonthPodiumRepository podium,
    required MonthFinalBoard board,
    required Clock clock,
  }) : _champions = champions,
       _podium = podium,
       _board = board,
       _clock = clock;

  final MonthChampionRepository _champions;
  final MonthPodiumRepository _podium;
  final MonthFinalBoard _board;
  final Clock _clock;

  /// The places on the podium after the champion(s).
  static const List<int> places = <int>[2, 3];

  /// Runs the use-case for [principal].
  Future<Result<List<MonthPodiumPlace>>> call({
    required AuthenticatedUser principal,
    required String seasonId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final idResult = SeasonId.tryParse(seasonId);
    if (idResult is Err<SeasonId>) {
      return Result.err(idResult.error);
    }
    final season = (idResult as Ok<SeasonId>).value;

    final existing = await _podium.of(season);
    if (existing is Err<List<MonthPodiumPlace>>) {
      return Result.err(existing.error);
    }
    if ((existing as Ok<List<MonthPodiumPlace>>).value.isNotEmpty) {
      return existing;
    }

    final monthResult = await _champions.month(season);
    if (monthResult is Err<ChampionMonth?>) {
      return Result.err(monthResult.error);
    }
    final month = (monthResult as Ok<ChampionMonth?>).value;
    if (month == null) {
      return const Result.err(
        AppError.invariant('champion.month_not_found', 'الشهر غير موجود'),
      );
    }
    if (month.crowned.isEmpty) {
      return const Result.err(
        AppError.invariant(
          'champion.not_crowned',
          'تُثبَّت المنصة بعد تتويج بطل الشهر',
        ),
      );
    }

    final boardResult = await _board.top(
      month,
      limit: month.crowned.length + places.length,
    );
    if (boardResult is Err<List<ChampionCandidate>>) {
      return Result.err(boardResult.error);
    }
    final crowned = month.crowned.toSet();
    final next = [
      for (final line in (boardResult as Ok<List<ChampionCandidate>>).value)
        if (!crowned.contains(line.userId)) line,
    ];
    final toSet = <PodiumPlaceToSet>[
      for (var i = 0; i < next.length && i < places.length; i++)
        PodiumPlaceToSet(
          place: places[i],
          userId: next[i].userId,
          points: next[i].entry.totalPoints,
          exactCount: next[i].entry.exactCount,
          decidedCount: next[i].entry.decidedCount,
        ),
    ];
    if (toSet.isEmpty) {
      return const Result.ok(<MonthPodiumPlace>[]);
    }
    final stored = await _podium.set(
      season: season,
      places: toSet,
      setBy: principal.userId,
      setAt: _clock.nowUtc(),
    );
    if (stored is Err<void>) {
      return Result.err(stored.error);
    }
    return _podium.of(season);
  }
}

/// Use-case: every month's podium, for everyone signed in -- the
/// celebration draws the newest one beside its champion.
///
/// Never throws; returns a typed [Result].
final class ListMonthPodium {
  /// Creates the use-case over its store.
  const ListMonthPodium({required MonthPodiumRepository podium})
    : _podium = podium;

  final MonthPodiumRepository _podium;

  /// Two places a month, so two years of months.
  static const int limit = 48;

  /// Runs the use-case for [principal].
  Future<Result<List<MonthPodiumPlace>>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    return _podium.list(limit: limit);
  }
}
