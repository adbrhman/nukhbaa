import 'dart:async';

import 'package:server/composition/composition_root.dart';
import 'package:server/scheduler/job_failure.dart';
import 'package:server/scheduler/single_flight.dart';
import 'package:shared/shared.dart';

/// How often the "N matches still to predict" sweep wakes up. Well inside
/// its 30-minute window; `incomplete_day_sends` (0106), not this interval,
/// keeps it to one push per player per day.
const Duration incompleteDayTick = Duration(minutes: 10);

/// Starts the "N matches still to predict" sweep on a timer (batch 117).
///
/// In-process like every other schedule here (see reminder_scheduler.dart).
/// Never throws and never awaits: a sweep that fails is logged and the next
/// tick retries.
Timer startIncompleteDayScheduler(CompositionRoot root) {
  return Timer.periodic(incompleteDayTick, (_) {
    unawaited(_sweep(root));
  });
}

/// One run at a time: a tick that fires while the previous run is still
/// going is skipped, not stacked (see single_flight.dart).
final Future<void> Function(CompositionRoot) _sweep = singleFlight(_sweepOnce);

Future<void> _sweepOnce(CompositionRoot root) async {
  try {
    final result = await root.sendIncompleteDayReminders(
      now: DateTime.now().toUtc(),
    );
    switch (result) {
      case Ok<int>(:final value):
        if (value > 0) {
          // ignore: avoid_print
          print('incomplete-day sweep: pushed $value player(s)');
        }
      case Err<int>(:final error):
        // ignore: avoid_print
        print('incomplete-day sweep failed: ${error.code} ${error.message}');
        await reportJobFailure(root, job: 'incomplete-day', error: error);
    }
  } on Object catch (error, stackTrace) {
    // ignore: avoid_print
    print('incomplete-day sweep threw: $error');
    await reportJobFailure(
      root,
      job: 'incomplete-day',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
