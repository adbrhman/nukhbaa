import 'dart:async';

import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';

/// How often the reminder sweep wakes up.
///
/// Shorter than the use-case's firing window, so a tick can never step over
/// it; the send ledger (migration 0040), not this interval, is what prevents a
/// duplicate notification.
const Duration reminderTick = Duration(minutes: 10);

/// Starts the prediction-reminder sweep on a timer.
///
/// Deliberately in-process rather than pg_cron: one container, one schedule,
/// and the whole decision lives in Dart where it is unit-tested. A restart
/// costs at most one tick, and the ledger makes a replay harmless.
///
/// Never throws and never awaits: the timer must not be able to take the
/// server down, and a sweep that fails is logged and retried next tick.
Timer startReminderScheduler(CompositionRoot root) {
  return Timer.periodic(reminderTick, (_) {
    unawaited(_sweep(root));
  });
}

Future<void> _sweep(CompositionRoot root) async {
  try {
    final result = await root.sendPredictionReminders(
      now: DateTime.now().toUtc(),
    );
    switch (result) {
      case Ok<int>(:final value):
        if (value > 0) {
          // ignore: avoid_print -- the container log is the only observability
          // this deployment has.
          print('reminder sweep: notified $value user(s)');
        }
      case Err<int>(:final error):
        // ignore: avoid_print
        print('reminder sweep failed: ${error.code} ${error.message}');
    }
  } on Object catch (error) {
    // ignore: avoid_print
    print('reminder sweep threw: $error');
  }
}
