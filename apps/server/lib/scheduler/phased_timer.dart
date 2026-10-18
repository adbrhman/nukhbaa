/// Keeps the in-process schedulers from firing in the same second.
library;

import 'dart:async';

/// Every scheduler used to start its `Timer.periodic` at boot, all within the
/// same millisecond. A 5, 10, 15 and 30 minute tick then meet at every
/// half hour: on 2026-10-16 at 12:19:38 five jobs (h2h, badges, rescore,
/// referrals, overtaken) asked for a connection in the same second, beside
/// the players' requests, on a server with 0.2 vCPU. Each job now starts its
/// period after a phase of its own, below a minute. Every tick is a whole
/// number of minutes, so two phases that differ by less than a minute never
/// meet again (audit NUKHBA-007b, script 99). The weekly league was deleted
/// on 2026-10-18 (script 114), with its closure and overtaken jobs.
const Duration providerLivePhase = Duration.zero;

/// See [providerLivePhase].
const Duration providerFixturesPhase = Duration(seconds: 2);

/// See [providerLivePhase].
const Duration notificationQueuePhase = Duration(seconds: 4);

/// See [providerLivePhase].
const Duration h2hLeaguePhase = Duration(seconds: 8);

/// See [providerLivePhase].
const Duration reminderPhase = Duration(seconds: 12);

/// See [providerLivePhase].
const Duration preMatchPhase = Duration(seconds: 16);

/// See [providerLivePhase].
const Duration streakSaverPhase = Duration(seconds: 20);

/// See [providerLivePhase].
const Duration incompleteDayPhase = Duration(seconds: 24);

/// See [providerLivePhase].
const Duration providerResultsPhase = Duration(seconds: 28);

/// See [providerLivePhase].
const Duration badgeEvaluationPhase = Duration(seconds: 32);

/// See [providerLivePhase].
const Duration rescorePhase = Duration(seconds: 36);

/// See [providerLivePhase].
const Duration referralQualificationPhase = Duration(seconds: 44);

/// See [providerLivePhase].
const Duration matchDaySettlementPhase = Duration(seconds: 48);

/// See [providerLivePhase].
const Duration monthlySeasonPhase = Duration(seconds: 56);

/// Makes a one-shot timer; [Timer.new] in production.
typedef OneShotTimerFactory =
    Timer Function(Duration duration, void Function() callback);

/// Makes a periodic timer; [Timer.periodic] in production.
typedef PeriodicTimerFactory =
    Timer Function(Duration period, void Function(Timer timer) callback);

/// Calls [run] every [tick], the first time at [phase] + [tick].
///
/// The returned timer cancels both the wait for [phase] and the period.
/// [once] and [every] exist for tests.
Timer phasedPeriodic(
  Duration phase,
  Duration tick,
  void Function(Timer timer) run, {
  OneShotTimerFactory once = Timer.new,
  PeriodicTimerFactory every = Timer.periodic,
}) {
  final PhasedTimer timer = PhasedTimer._();
  timer._wait = once(phase, () {
    if (timer._cancelled) {
      return;
    }
    timer._period = every(tick, run);
  });
  return timer;
}

/// The timer [phasedPeriodic] returns.
final class PhasedTimer implements Timer {
  PhasedTimer._();

  Timer? _wait;
  Timer? _period;
  bool _cancelled = false;

  @override
  bool get isActive => !_cancelled;

  @override
  int get tick => _period?.tick ?? 0;

  @override
  void cancel() {
    _cancelled = true;
    _wait?.cancel();
    _period?.cancel();
  }
}
