/// Use-case: what the admin sees before crowning a month (migration 0077).
/// Admin only.
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/leaderboard/month_final_board.dart';
import 'package:application/src/leaderboard/ports/month_champion_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// The crowning preview of one month.
final class ChampionCandidates {
  /// Creates the preview.
  const ChampionCandidates({
    required this.month,
    required this.ended,
    required this.candidates,
  });

  /// The month, with its unscored fixtures and anyone already crowned.
  final ChampionMonth month;

  /// Whether the month is over (its end has passed).
  final bool ended;

  /// The top of its final board; every player ranked first is included.
  final List<ChampionCandidate> candidates;
}

/// Reads the preview of [seasonId]'s crowning: whether the month is over,
/// how many of its fixtures still have no result, who is already crowned,
/// and the top of its final board.
///
/// Never throws; returns a typed [Result].
final class AdminGetChampionCandidates {
  /// Creates the use-case over its collaborators.
  const AdminGetChampionCandidates({
    required MonthChampionRepository champions,
    required MonthFinalBoard board,
    required Clock clock,
  }) : _champions = champions,
       _board = board,
       _clock = clock;

  final MonthChampionRepository _champions;
  final MonthFinalBoard _board;
  final Clock _clock;

  /// How many lines of the board the preview shows (more when more players
  /// share first place).
  static const int previewSize = 5;

  /// Runs the use-case for [principal].
  Future<Result<ChampionCandidates>> call({
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
    final monthResult = await _champions.month(
      (idResult as Ok<SeasonId>).value,
    );
    if (monthResult is Err<ChampionMonth?>) {
      return Result.err(monthResult.error);
    }
    final month = (monthResult as Ok<ChampionMonth?>).value;
    if (month == null) {
      return const Result.err(
        AppError.invariant('champion.month_not_found', 'الشهر غير موجود'),
      );
    }
    final boardResult = await _board.top(month, limit: previewSize);
    if (boardResult is Err<List<ChampionCandidate>>) {
      return Result.err(boardResult.error);
    }
    return Result.ok(
      ChampionCandidates(
        month: month,
        ended: !_clock.nowUtc().isBefore(month.endAt),
        candidates: (boardResult as Ok<List<ChampionCandidate>>).value,
      ),
    );
  }
}
