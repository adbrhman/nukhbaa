import 'dart:async';

import 'package:server/scheduler/badge_evaluation_scheduler.dart';
import 'package:server/scheduler/h2h_league_scheduler.dart';
import 'package:server/scheduler/incomplete_day_scheduler.dart';
import 'package:server/scheduler/match_day_settlement_scheduler.dart';
import 'package:server/scheduler/monthly_season_scheduler.dart';
import 'package:server/scheduler/notification_queue_scheduler.dart';
import 'package:server/scheduler/phased_timer.dart';
import 'package:server/scheduler/pre_match_scheduler.dart';
import 'package:server/scheduler/provider_sync_scheduler.dart';
import 'package:server/scheduler/referral_qualification_scheduler.dart';
import 'package:server/scheduler/reminder_scheduler.dart';
import 'package:server/scheduler/rescore_scheduler.dart';
import 'package:server/scheduler/streak_saver_scheduler.dart';
import 'package:test/test.dart';

/// A timer that only records whether it was cancelled.
final class _FakeTimer implements Timer {
  bool cancelled = false;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;

  @override
  void cancel() => cancelled = true;
}

void main() {
  group('phasedPeriodic', () {
    late List<Duration> onceDurations;
    late List<void Function()> onceCallbacks;
    late List<Duration> periods;
    late List<void Function(Timer)> periodCallbacks;
    late List<_FakeTimer> made;

    Timer once(Duration d, void Function() cb) {
      onceDurations.add(d);
      onceCallbacks.add(cb);
      final t = _FakeTimer();
      made.add(t);
      return t;
    }

    Timer every(Duration d, void Function(Timer) cb) {
      periods.add(d);
      periodCallbacks.add(cb);
      final t = _FakeTimer();
      made.add(t);
      return t;
    }

    setUp(() {
      onceDurations = [];
      onceCallbacks = [];
      periods = [];
      periodCallbacks = [];
      made = [];
    });

    test('waits for the phase, then runs on the tick', () {
      var runs = 0;
      phasedPeriodic(
        const Duration(seconds: 12),
        const Duration(minutes: 10),
        (_) => runs++,
        once: once,
        every: every,
      );

      expect(onceDurations, [const Duration(seconds: 12)]);
      expect(periods, isEmpty, reason: 'no period before the phase');

      onceCallbacks.single();
      expect(periods, [const Duration(minutes: 10)]);
      expect(runs, 0, reason: 'the first run is one tick after the phase');

      periodCallbacks.single(made.last);
      periodCallbacks.single(made.last);
      expect(runs, 2);
    });

    test('cancelled during the phase, the period never starts', () {
      final timer = phasedPeriodic(
        const Duration(seconds: 4),
        const Duration(minutes: 5),
        (_) {},
        once: once,
        every: every,
      );

      timer.cancel();
      expect(made.single.cancelled, isTrue);
      onceCallbacks.single();
      expect(periods, isEmpty);
      expect(timer.isActive, isFalse);
    });

    test('cancelled after the phase, the period stops', () {
      final timer = phasedPeriodic(
        Duration.zero,
        const Duration(minutes: 2),
        (_) {},
        once: once,
        every: every,
      );
      onceCallbacks.single();

      timer.cancel();
      expect(made.last.cancelled, isTrue);
    });
  });

  test('no two schedulers ever fire in the same second', () {
    // Every scheduler's (phase, tick). Two jobs meet only when their phases
    // differ by a multiple of the greatest common divisor of their ticks.
    final jobs = <String, (Duration, Duration)>{
      'provider live': (providerLivePhase, providerLiveTick),
      'provider fixtures': (providerFixturesPhase, providerFixturesTick),
      'provider results': (providerResultsPhase, providerResultsTick),
      'notification queue': (notificationQueuePhase, notificationQueueTick),
      'h2h league': (h2hLeaguePhase, h2hLeagueTick),
      'reminder': (reminderPhase, reminderTick),
      'pre-match': (preMatchPhase, preMatchTick),
      'streak saver': (streakSaverPhase, streakSaverTick),
      'incomplete day': (incompleteDayPhase, incompleteDayTick),
      'badge evaluation': (badgeEvaluationPhase, badgeEvaluationTick),
      'rescore': (rescorePhase, rescoreTick),
      'referral qualification': (
        referralQualificationPhase,
        referralQualificationTick,
      ),
      'match-day settlement': (matchDaySettlementPhase, matchDaySettlementTick),
      'monthly season': (monthlySeasonPhase, monthlySeasonTick),
    };
    int gcd(int a, int b) => b == 0 ? a : gcd(b, a % b);
    final names = jobs.keys.toList();
    for (var i = 0; i < names.length; i++) {
      for (var j = i + 1; j < names.length; j++) {
        final (pa, ta) = jobs[names[i]]!;
        final (pb, tb) = jobs[names[j]]!;
        final g = gcd(ta.inSeconds, tb.inSeconds);
        final diff = (pa.inSeconds - pb.inSeconds).abs();
        expect(
          diff % g,
          isNot(0),
          reason: '${names[i]} and ${names[j]} fire together',
        );
      }
    }
  });
}
