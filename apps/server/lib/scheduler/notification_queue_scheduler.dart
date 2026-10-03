import 'dart:async';

import 'package:server/composition/composition_root.dart';
import 'package:server/scheduler/job_failure.dart';
import 'package:server/scheduler/single_flight.dart';
import 'package:shared/shared.dart';

/// How often the deferred-push queue is swept.
///
/// A push queued until 08:00 goes out within this much of it. The claim in
/// the queue (migration 0064), not this interval, is what keeps a push from
/// going out twice.
const Duration notificationQueueTick = Duration(minutes: 5);

/// Starts the deferred-push sweep on a timer (P3-2).
///
/// In-process like every other schedule here (see reminder_scheduler.dart).
/// Never throws and never awaits: a sweep that fails is logged and the
/// waiting pushes are picked up on the next tick.
Timer startNotificationQueueScheduler(CompositionRoot root) {
  return Timer.periodic(notificationQueueTick, (_) {
    unawaited(_sweep(root));
  });
}

/// One run at a time: a tick that fires while the previous run is still
/// going is skipped, not stacked (see single_flight.dart).
final Future<void> Function(CompositionRoot) _sweep = singleFlight(_sweepOnce);

Future<void> _sweepOnce(CompositionRoot root) async {
  try {
    final result = await root.flushNotificationQueue(
      now: DateTime.now().toUtc(),
    );
    switch (result) {
      case Ok<int>(:final value):
        if (value > 0) {
          // ignore: avoid_print
          print('notification queue: delivered $value deferred push(es)');
        }
      case Err<int>(:final error):
        // ignore: avoid_print
        print('notification queue failed: ${error.code} ${error.message}');
        await reportJobFailure(root, job: 'notification-queue', error: error);
    }
  } on Object catch (error, stackTrace) {
    // ignore: avoid_print
    print('notification queue threw: $error');
    await reportJobFailure(
      root,
      job: 'notification-queue',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
