/// Use-case: the crowned champions, for everyone signed in (migration 0077).
library;

import 'package:application/src/identity/authorization.dart';
import 'package:application/src/leaderboard/ports/month_champion_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Lists the crowned champions, newest crowning first. The app shows the
/// newest month's celebration for [celebrationWindow] after its crowning,
/// then keeps the crown beside the champion's name and in the records.
///
/// Never throws; returns a typed [Result].
final class ListMonthChampions {
  /// Creates the use-case over its store.
  const ListMonthChampions({required MonthChampionRepository champions})
    : _champions = champions;

  final MonthChampionRepository _champions;

  /// How long the celebration is shown after a crowning (decided
  /// 2026-09-29).
  static const Duration celebrationWindow = Duration(hours: 48);

  /// Two champions a month at most, so two years of months.
  static const int limit = 48;

  /// Runs the use-case for [principal].
  Future<Result<List<MonthChampion>>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    return _champions.list(limit: limit);
  }
}
