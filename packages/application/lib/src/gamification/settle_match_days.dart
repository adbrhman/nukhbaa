import 'package:application/src/football_data/provider_sync_rules.dart'
    show riyadhDayOf;
import 'package:application/src/gamification/ports/match_day_settlement_store.dart';
import 'package:shared/shared.dart';

/// Use-case: settles (freezes) the Riyadh match days that have ended (P1-5).
///
/// The streak calendar used to derive match days live from the current
/// fixture schedule, so a fixture that was moved, added or removed re-wrote
/// days that were already over. Settling records each finished day once, with
/// the number of fixtures it had, and the calendar reads it as it was.
///
/// **Which days.** Every day from the one after the newest settled day (the
/// first run starts at the earliest scheduled fixture) through the last day
/// that ended at least [grace] ago, Riyadh time. The grace keeps a late
/// kickoff correction, made just after midnight, from being frozen out.
///
/// **Catch-up.** A missed run is made good by the next one, [maxDaysPerRun]
/// days at a time, so a long outage cannot turn into one enormous statement.
///
/// **Idempotent.** Settling a day that is already settled changes nothing,
/// so the job is safe to run as often as the scheduler likes.
///
/// Never throws; returns a typed [Result] with the number of days settled.
final class SettleMatchDays {
  /// Creates the use-case over its [store].
  const SettleMatchDays({
    required MatchDaySettlementStore store,
    this.grace = const Duration(hours: 3),
    this.maxDaysPerRun = 120,
  }) : _store = store;

  final MatchDaySettlementStore _store;

  /// How long a Riyadh day must have been over before it is settled.
  final Duration grace;

  /// The most days a single run settles.
  final int maxDaysPerRun;

  /// Settles what is due as of [now].
  Future<Result<int>> call({required DateTime now}) async {
    // The Riyadh day that is still open `grace` ago; every day before it is
    // over.
    final open = riyadhDayOf(now.toUtc().subtract(grace));
    final through = open.subtract(const Duration(days: 1));

    final lastResult = await _store.lastSettledDay();
    if (lastResult is Err<DateTime?>) {
      return Result.err(lastResult.error);
    }
    final last = (lastResult as Ok<DateTime?>).value;

    final DateTime from;
    if (last == null) {
      final firstResult = await _store.firstFixtureDay();
      if (firstResult is Err<DateTime?>) {
        return Result.err(firstResult.error);
      }
      final first = (firstResult as Ok<DateTime?>).value;
      if (first == null) {
        return const Result.ok(0);
      }
      from = first;
    } else {
      from = last.add(const Duration(days: 1));
    }
    if (from.isAfter(through)) {
      return const Result.ok(0);
    }

    final cap = from.add(Duration(days: maxDaysPerRun - 1));
    final upTo = cap.isBefore(through) ? cap : through;
    return _store.settle(from: from, through: upTo);
  }
}
