/// Use-case: an admin sets the prize of a month ahead of its crowning
/// (migration 0199, script 204). Admin only.
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/leaderboard/admin_crown_month_champions.dart';
import 'package:application/src/leaderboard/ports/month_champion_repository.dart';
import 'package:application/src/leaderboard/ports/month_crown_store.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Sets or replaces the prize the month will be crowned with: the
/// automatic crowning takes it (`AutoCrownMonths`), and a month left
/// without one takes the previous month's.
///
/// The prize is trimmed, 1 to 80 letters (the champion's own bound,
/// migration 0078). Refused for a blank or longer prize
/// (`champion.prize_blank`, `champion.prize_too_long`), a month that does
/// not exist (`champion.month_not_found`) or one already crowned
/// (`champion.already_crowned`).
///
/// Never throws; returns the prize as stored.
final class AdminSetMonthPrize {
  /// Creates the use-case over its collaborators.
  const AdminSetMonthPrize({
    required MonthChampionRepository champions,
    required MonthCrownStore store,
    required Clock clock,
  }) : _champions = champions,
       _store = store,
       _clock = clock;

  final MonthChampionRepository _champions;
  final MonthCrownStore _store;
  final Clock _clock;

  /// Runs the use-case for [principal].
  Future<Result<String>> call({
    required AuthenticatedUser principal,
    required String seasonId,
    required String? prize,
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

    final String trimmed = prize?.trim() ?? '';
    if (trimmed.isEmpty) {
      return const Result.err(
        AppError.validation('champion.prize_blank', 'اكتب الجائزة'),
      );
    }
    if (trimmed.length > AdminCrownMonthChampions.maxPrizeLength) {
      return const Result.err(
        AppError.validation(
          'champion.prize_too_long',
          'نص الجائزة أطول من 80 حرفًا',
        ),
      );
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
    if (month.crowned.isNotEmpty) {
      return const Result.err(
        AppError.invariant(
          'champion.already_crowned',
          'هذا الشهر متوَّج مسبقًا',
        ),
      );
    }

    final saved = await _store.setPrize(
      season: season,
      prize: trimmed,
      setBy: principal.userId,
      setAt: _clock.nowUtc(),
    );
    if (saved is Err<void>) {
      return Result.err(saved.error);
    }
    return Result.ok(trimmed);
  }
}
