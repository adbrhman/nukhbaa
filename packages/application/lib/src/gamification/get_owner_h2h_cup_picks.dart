// NK310_03
/// Use-case: the Elite Cup of a month with every player's picks, for the
/// owners' page (script 310).
///
/// The same board a player reads (`GetH2hCupBoard`), built by the same code,
/// except that no side is withheld: the owners see both players' picks on
/// every fixture before it kicks off. It is read-only. The route is behind
/// the owners' gate; the role check here is the second lock. It takes its
/// own reader, [H2hCupOwnerPickReader], which the player's use-case never
/// receives.
///
/// Never throws; returns a typed [Result].
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/football_data/provider_sync_rules.dart'
    show riyadhDayOf;
import 'package:application/src/gamification/get_h2h_cup_board.dart';
import 'package:application/src/gamification/ports/h2h_cup_owner_pick_reader.dart';
import 'package:application/src/gamification/ports/h2h_cup_store.dart';
import 'package:application/src/gamification/ports/weekly_league_profile_reader.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Reads the cup of a month with nothing withheld.
final class GetOwnerH2hCupPicks {
  /// Creates the use-case over its collaborators.
  const GetOwnerH2hCupPicks({
    required H2hCupStore cups,
    required H2hCupOwnerPickReader picks,
    required WeeklyLeagueProfileReader profiles,
    required Clock clock,
  }) : _cups = cups,
       _picks = picks,
       _profiles = profiles,
       _clock = clock;

  final H2hCupStore _cups;
  final H2hCupOwnerPickReader _picks;
  final WeeklyLeagueProfileReader _profiles;
  final Clock _clock;

  /// Reads the board of [month] (a month's first day), or of the latest of
  /// the current month and the two before it that holds a cup when null.
  /// A month with no cup reads [H2hCupBoard.none].
  Future<Result<H2hCupBoard>> call({
    required AuthenticatedUser principal,
    DateTime? month,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final nowUtc = _clock.nowUtc().toUtc();

    var shown = H2hLeaguePolicy.monthStartOf(riyadhDayOf(nowUtc));
    var state = H2hCupState.empty;
    if (month != null) {
      shown = DateTime.utc(month.year, month.month);
      final read = await _cups.stateOf(shown);
      if (read is Err<H2hCupState>) {
        return Result.err(read.error);
      }
      state = (read as Ok<H2hCupState>).value;
    } else {
      final current = shown;
      for (final back in const <int>[0, 1, 2]) {
        final candidate = DateTime.utc(current.year, current.month - back);
        if (!H2hLeaguePolicy.usesEliteDraw(candidate)) {
          continue;
        }
        final read = await _cups.stateOf(candidate);
        if (read is Err<H2hCupState>) {
          return Result.err(read.error);
        }
        final found = (read as Ok<H2hCupState>).value;
        if (found.entries.isNotEmpty) {
          shown = candidate;
          state = found;
          break;
        }
      }
    }
    if (state.entries.isEmpty) {
      return const Result.ok(H2hCupBoard.none);
    }

    return H2hCupBoardBuilder.build(
      state: state,
      monthStart: shown,
      caller: principal.userId,
      nowUtc: nowUtc,
      unmasked: true,
      profiles: _profiles,
      readFixtures: (stages) => _picks.fixturesOfUnmasked(stages: stages),
    );
  }
}
