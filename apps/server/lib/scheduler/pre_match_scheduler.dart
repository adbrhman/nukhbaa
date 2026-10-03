import 'dart:async';

import 'package:server/composition/composition_root.dart';
import 'package:server/scheduler/job_failure.dart';
import 'package:server/scheduler/single_flight.dart';
import 'package:shared/shared.dart';

/// How often the pre-match sweep wakes up: well inside its 30-minute window,
/// so every fixture is seen at least once. `proactive_sends` (migration
/// 0066), not this interval, keeps a push from going out twice.
const Duration preMatchTick = Duration(minutes: 10);

/// Starts the pre-match sweep on a timer (plan P3-4a).
///
/// In-process like every other schedule here (see reminder_scheduler.dart).
/// Never throws and never awaits: a sweep that fails is logged and the next
/// tick retries.
Timer startPreMatchScheduler(CompositionRoot root) {
  return Timer.periodic(preMatchTick, (_) {
    unawaited(_sweep(root));
  });
}

/// One run at a time: a tick that fires while the previous run is still
/// going is skipped, not stacked (see single_flight.dart).
final Future<void> Function(CompositionRoot) _sweep = singleFlight(_sweepOnce);

Future<void> _sweepOnce(CompositionRoot root) async {
  try {
    final result = await root.sendPreMatchReminders(
      now: DateTime.now().toUtc(),
    );
    switch (result) {
      case Ok<int>(:final value):
        if (value > 0) {
          // ignore: avoid_print
          print('pre-match sweep: pushed $value follower(s)');
        }
      case Err<int>(:final error):
        // ignore: avoid_print
        print('pre-match sweep failed: ${error.code} ${error.message}');
        await reportJobFailure(root, job: 'pre-match', error: error);
    }
  } on Object catch (error, stackTrace) {
    // ignore: avoid_print
    print('pre-match sweep threw: $error');
    await reportJobFailure(
      root,
      job: 'pre-match',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
