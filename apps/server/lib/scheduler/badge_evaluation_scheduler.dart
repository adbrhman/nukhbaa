import 'dart:async';

import 'package:server/composition/composition_root.dart';
import 'package:server/scheduler/job_failure.dart';
import 'package:server/scheduler/phased_timer.dart';
import 'package:server/scheduler/single_flight.dart';
import 'package:shared/shared.dart';

/// How often the badge evaluation runs. A run is one grouped read of the
/// whole event stream plus one insert per badge newly earned (see
/// `EvaluateBadges`). Every quarter of an hour it was the largest share of
/// the database's time (10.6% on 2026-10-17), while the badges screen was
/// opened 14 times in two weeks by 10 of 88 players and no push announces a
/// badge. Every three hours, a badge appears within three hours of the act
/// that earned it (script 103).
const Duration badgeEvaluationTick = Duration(hours: 3);

/// How long after boot the first evaluation runs, so it never competes with
/// the startup probe or the first requests.
const Duration badgeEvaluationFirstRunDelay = Duration(minutes: 3);

/// Awards the badges players have earned (P2-6).
///
/// In-process like the other sweeps: one container, one schedule, and the
/// rule itself is unit-tested in `EvaluateBadges`. It never throws and never
/// awaits, so it cannot take the server down; a failed run is logged and
/// simply retried on the next tick. Retrying is safe: every badge event is
/// keyed on the user and the badge, so a repeat writes nothing.
Timer startBadgeEvaluationScheduler(CompositionRoot root) {
  Timer(badgeEvaluationFirstRunDelay, () {
    unawaited(_check(root));
  });
  return phasedPeriodic(badgeEvaluationPhase, badgeEvaluationTick, (_) {
    unawaited(_check(root));
  });
}

/// One run at a time: a tick that fires while the previous run is still
/// going is skipped, not stacked (see single_flight.dart).
final Future<void> Function(CompositionRoot) _check = singleFlight(_checkOnce);

Future<void> _checkOnce(CompositionRoot root) async {
  try {
    final result = await root.evaluateBadges(now: DateTime.now().toUtc());
    switch (result) {
      case Ok<int>(:final value):
        if (value > 0) {
          // ignore: avoid_print
          print('badges: awarded $value badge(s)');
        }
      case Err<int>(:final error):
        // ignore: avoid_print
        print('badge evaluation failed: ${error.code} ${error.message}');
        await reportJobFailure(root, job: 'badge-evaluation', error: error);
    }
  } on Object catch (error, stackTrace) {
    // ignore: avoid_print
    print('badge evaluation threw: $error');
    await reportJobFailure(
      root,
      job: 'badge-evaluation',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
