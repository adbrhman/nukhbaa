import 'package:application/src/common/clock.dart';
import 'package:application/src/common/id_generator.dart';
import 'package:application/src/football_data/provider_sync_rules.dart'
    show riyadhDayOf;
import 'package:application/src/gamification/ports/h2h_control_store.dart';
import 'package:application/src/gamification/ports/h2h_round_store.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Use-case: an admin withdraws a mistaken round (migration 0100).
///
/// Only the last round of a month, and only before its first kickoff froze
/// it: the store returns an invariant error otherwise. Numbering stays
/// gap-free, and nobody's played round disappears.
///
/// **The day stays out (0101)**, when [controls] is given: the withdrawn
/// round's day is excluded first, so the scheduler does not approve it again
/// five minutes later. An admin who approves that day by hand lifts the
/// exclusion. Should the withdrawal fail, an exclusion made here is lifted
/// again; the withdrawal is written to the admin log.
///
/// Never throws; returns a typed [Result].
final class WithdrawH2hRound {
  /// Creates the use-case over its store.
  const WithdrawH2hRound({
    required H2hRoundStore rounds,
    H2hControlStore? controls,
    Clock? clock,
    IdGenerator? idGenerator,
  }) : _rounds = rounds,
       _controls = controls,
       _clock = clock,
       _ids = idGenerator;

  final H2hRoundStore _rounds;
  final H2hControlStore? _controls;
  final Clock? _clock;
  final IdGenerator? _ids;

  /// Withdraws [roundId] for [principal], an admin.
  Future<Result<void>> call({
    required AuthenticatedUser principal,
    required H2hRoundId roundId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final controls = _controls;
    final clock = _clock;
    if (controls == null || clock == null) {
      return _rounds.withdraw(roundId);
    }

    final dayResult = await _dayOf(roundId, clock.nowUtc());
    if (dayResult is Err<H2hRound?>) {
      return Result.err(dayResult.error);
    }
    final round = (dayResult as Ok<H2hRound?>).value;
    if (round == null) {
      // Not a round of this month or the next: the store says why.
      return _rounds.withdraw(roundId);
    }

    final excluded = await controls.exclude(
      day: round.day,
      by: principal.userId,
    );
    if (excluded is Err<bool>) {
      return Result.err(excluded.error);
    }
    final fresh = (excluded as Ok<bool>).value;

    final withdrawn = await _rounds.withdraw(roundId);
    if (withdrawn is Err<void>) {
      if (fresh) {
        await controls.include(round.day);
      }
      return withdrawn;
    }

    final ids = _ids;
    if (ids != null) {
      // The log is a record, not a condition: the withdrawal stands.
      await controls.record(
        id: ids.newUuid(),
        action: H2hAdminActionKind.roundWithdrawn,
        by: principal.userId,
        detail: {'round': round.number, 'day': _isoDay(round.day)},
      );
    }
    return const Result.ok(null);
  }

  /// The round [roundId] among this month's and the next month's, or null.
  Future<Result<H2hRound?>> _dayOf(H2hRoundId roundId, DateTime now) async {
    final month = H2hLeaguePolicy.monthStartOf(riyadhDayOf(now));
    for (final start in [month, DateTime.utc(month.year, month.month + 1)]) {
      final list = await _rounds.roundsOf(start);
      if (list is Err<List<H2hRound>>) {
        return Result.err(list.error);
      }
      for (final round in (list as Ok<List<H2hRound>>).value) {
        if (round.id == roundId) {
          return Result.ok(round);
        }
      }
    }
    return const Result.ok(null);
  }

  static String _isoDay(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}
