/// Use-case: what the admin sees before crowning a month (migration 0077).
/// Admin only.
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/leaderboard/month_final_board.dart';
import 'package:application/src/leaderboard/ports/month_champion_repository.dart';
import 'package:application/src/leaderboard/ports/month_crown_store.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// The crowning preview of one month.
final class ChampionCandidates {
  /// Creates the preview.
  const ChampionCandidates({
    required this.month,
    required this.ended,
    required this.candidates,
    this.plannedPrize,
  });

  /// The month, with its unscored fixtures and anyone already crowned.
  final ChampionMonth month;

  /// Whether the month is over (its end has passed).
  final bool ended;

  /// The top of its final board; every player level with the first for
  /// the crown is included, and ranked first.
  final List<ChampionCandidate> candidates;

  /// The prize the automatic crowning would give (migration 0199): the one
  /// set ahead for the month, else the previous month's; null when there
  /// is none or no store was given.
  final String? plannedPrize;
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
    MonthCrownStore? crownStore,
  }) : _champions = champions,
       _board = board,
       _clock = clock,
       _crownStore = crownStore;

  final MonthChampionRepository _champions;
  final MonthFinalBoard _board;
  final Clock _clock;

  /// Optional: without it the preview carries no planned prize.
  final MonthCrownStore? _crownStore;

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
    final lines = (boardResult as Ok<List<ChampionCandidate>>).value;
    // Every player level with the first for the crown is shown first, so
    // the admin may choose him whatever his join time (L-29).
    final candidates = <ChampionCandidate>[];
    for (final line in lines) {
      if (line.entry.rank == 1 ||
          !MonthFinalBoard.levelForCrown(line.entry, lines.first.entry)) {
        candidates.add(line);
        continue;
      }
      final first = line.entry.withRank(1);
      if (first is Err<FixtureLeaderboardEntry>) {
        return Result.err(first.error);
      }
      candidates.add(
        ChampionCandidate(
          entry: (first as Ok<FixtureLeaderboardEntry>).value,
          userId: line.userId,
        ),
      );
    }

    String? plannedPrize;
    final store = _crownStore;
    if (store != null && month.crowned.isEmpty) {
      final prize = await store.prizeFor(month.seasonId);
      if (prize is Err<String?>) {
        return Result.err(prize.error);
      }
      plannedPrize = (prize as Ok<String?>).value;
    }

    return Result.ok(
      ChampionCandidates(
        month: month,
        ended: !_clock.nowUtc().isBefore(month.endAt),
        candidates: List<ChampionCandidate>.unmodifiable(candidates),
        plannedPrize: plannedPrize,
      ),
    );
  }
}
