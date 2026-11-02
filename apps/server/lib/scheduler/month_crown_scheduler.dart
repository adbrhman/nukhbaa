import 'dart:async';

import 'package:application/application.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/scheduler/job_failure.dart';
import 'package:server/scheduler/phased_timer.dart';
import 'package:server/scheduler/single_flight.dart';
import 'package:shared/shared.dart';

/// How often the month's crowning is looked at. Outside the first three
/// days of a month it finds nothing to look at and costs one small read; in
/// them it crowns within two minutes of the moment the last result settles.
const Duration monthCrownTick = Duration(minutes: 2);

/// How long after boot the first look runs, clear of the startup probe and
/// the other schedulers' first runs.
const Duration monthCrownFirstRunDelay = Duration(minutes: 3);

/// Crowns each month by itself once its last match is over (see
/// `AutoCrownMonths`, script 204).
///
/// In-process like every other schedule here: never throws and never awaits,
/// a failed run is logged and retried on the next tick, and single_flight
/// keeps a slow run from being joined by the next one.
Timer startMonthCrownScheduler(CompositionRoot root) {
  Timer(monthCrownFirstRunDelay, () {
    unawaited(_look(root));
  });
  return phasedPeriodic(monthCrownPhase, monthCrownTick, (_) {
    unawaited(_look(root));
  });
}

final Future<void> Function(CompositionRoot) _look = singleFlight(_lookOnce);

Future<void> _lookOnce(CompositionRoot root) async {
  final crown = root.autoCrownMonths;
  if (crown == null) {
    return;
  }
  try {
    final result = await crown(now: DateTime.now().toUtc());
    switch (result) {
      case Ok<List<AutoCrownOutcome>>(:final value):
        for (final outcome in value) {
          if (outcome.step != AutoCrownStep.settled) {
            // ignore: avoid_print
            print('month crown: $outcome');
          }
        }
      case Err<List<AutoCrownOutcome>>(:final error):
        // ignore: avoid_print
        print('month crown failed: ${error.code} ${error.message}');
        await reportJobFailure(
          root,
          job: 'month-crown',
          error: error,
          critical: true,
        );
    }
  } on Object catch (error, stackTrace) {
    // ignore: avoid_print
    print('month crown threw: $error');
    await reportJobFailure(
      root,
      job: 'month-crown',
      error: error,
      stackTrace: stackTrace,
      critical: true,
    );
  }
}
