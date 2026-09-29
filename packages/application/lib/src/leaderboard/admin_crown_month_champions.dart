/// Use-case: an admin crowns a month's champion, or two champions level on
/// every tie-break (migration 0077). Admin only.
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/leaderboard/month_final_board.dart';
import 'package:application/src/leaderboard/ports/month_champion_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Crowns [userIds] in a month, from its final board.
///
/// Refused, each with its own code, when: the month is not over
/// (`champion.month_not_over`); it is already crowned
/// (`champion.already_crowned`); some fixture has no result yet and the admin
/// did not confirm crowning anyway (`champion.fixtures_unscored`); a chosen
/// player is not ranked first on the final board (`champion.not_first`).
/// The admin decides between one and two champions when two players share
/// first place; a player not ranked first can never be chosen.
///
/// The final figures are frozen into the record as they stood. Never throws;
/// returns a typed [Result] carrying the month's champions.
final class AdminCrownMonthChampions {
  /// Creates the use-case over its collaborators.
  const AdminCrownMonthChampions({
    required MonthChampionRepository champions,
    required MonthFinalBoard board,
    required Clock clock,
  }) : _champions = champions,
       _board = board,
       _clock = clock;

  final MonthChampionRepository _champions;
  final MonthFinalBoard _board;
  final Clock _clock;

  /// The most champions one month can have.
  static const int maxChampions = 2;

  /// The longest prize text, the database's own bound (migration 0078).
  static const int maxPrizeLength = 80;

  /// Runs the use-case for [principal]. [force] confirms crowning while some
  /// fixtures still have no result (a postponed match, say). [prize] is what
  /// the champion wins ("150 ريال سعودي"); blank means none.
  Future<Result<List<MonthChampion>>> call({
    required AuthenticatedUser principal,
    required String seasonId,
    required List<String>? userIds,
    required bool force,
    String? prize,
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

    final chosenResult = _parseChosen(userIds);
    if (chosenResult is Err<List<UserId>>) {
      return Result.err(chosenResult.error);
    }
    final chosen = (chosenResult as Ok<List<UserId>>).value;
    final prizeResult = _parsePrize(prize);
    if (prizeResult is Err<String?>) {
      return Result.err(prizeResult.error);
    }
    final cleanPrize = (prizeResult as Ok<String?>).value;

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
    final now = _clock.nowUtc();
    if (now.isBefore(month.endAt)) {
      return const Result.err(
        AppError.invariant(
          'champion.month_not_over',
          'لا يُتوَّج الشهر قبل انتهائه',
        ),
      );
    }
    if (month.crowned.isNotEmpty) {
      return const Result.err(
        AppError.invariant(
          'champion.already_crowned',
          'هذا الشهر متوَّج مسبقًا',
        ),
      );
    }
    if (month.unscoredFixtures > 0 && !force) {
      return Result.err(
        AppError.invariant(
          'champion.fixtures_unscored',
          'مباريات بلا نتيجة بعد: ${month.unscoredFixtures}',
        ),
      );
    }

    final boardResult = await _board.top(month, limit: maxChampions);
    if (boardResult is Err<List<ChampionCandidate>>) {
      return Result.err(boardResult.error);
    }
    final leaders = <String, ChampionCandidate>{
      for (final line in (boardResult as Ok<List<ChampionCandidate>>).value)
        if (line.entry.rank == 1) line.userId.value: line,
    };
    final toCrown = <ChampionToCrown>[];
    for (final userId in chosen) {
      final line = leaders[userId.value];
      if (line == null) {
        return const Result.err(
          AppError.invariant(
            'champion.not_first',
            'لا يُتوَّج إلا صاحب المركز الأول في الترتيب النهائي',
          ),
        );
      }
      toCrown.add(
        ChampionToCrown(
          userId: userId,
          points: line.entry.totalPoints,
          exactCount: line.entry.exactCount,
          decidedCount: line.entry.decidedCount,
          referralPoints: line.entry.referralPoints,
          prize: cleanPrize,
        ),
      );
    }

    final crowned = await _champions.crown(
      season: season,
      champions: toCrown,
      crownedBy: principal.userId,
      crownedAt: now,
    );
    if (crowned is Err<void>) {
      return Result.err(crowned.error);
    }
    final listed = await _champions.list(limit: 50);
    if (listed is Err<List<MonthChampion>>) {
      return Result.err(listed.error);
    }
    return Result.ok(
      (listed as Ok<List<MonthChampion>>).value
          .where((champion) => champion.seasonId == season)
          .toList(growable: false),
    );
  }

  /// The prize trimmed, null when blank, refused past [maxPrizeLength].
  static Result<String?> _parsePrize(String? raw) {
    final String trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) {
      return const Result.ok(null);
    }
    if (trimmed.length > maxPrizeLength) {
      return const Result.err(
        AppError.validation(
          'champion.prize_too_long',
          'نص الجائزة أطول من 80 حرفًا',
        ),
      );
    }
    return Result.ok(trimmed);
  }

  static Result<List<UserId>> _parseChosen(List<String>? raw) {
    if (raw == null || raw.isEmpty || raw.length > maxChampions) {
      return const Result.err(
        AppError.validation(
          'champion.choose_one_or_two',
          'اختر بطلًا واحدًا أو بطلين',
        ),
      );
    }
    final out = <UserId>[];
    for (final value in raw) {
      final parsed = UserId.tryParse(value);
      if (parsed is Err<UserId>) {
        return Result.err(parsed.error);
      }
      final id = (parsed as Ok<UserId>).value;
      if (out.contains(id)) {
        return const Result.err(
          AppError.validation(
            'champion.choose_one_or_two',
            'اختر بطلًا واحدًا أو بطلين',
          ),
        );
      }
      out.add(id);
    }
    return Result.ok(out);
  }
}
