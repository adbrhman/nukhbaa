import 'dart:async';

import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';

/// How often the streak-saver sweep wakes up. Well inside its 30-minute
/// window; `proactive_sends` (0066), not this interval, keeps it to one push
/// per player per day.
const Duration streakSaverTick = Duration(minutes: 10);

/// Starts the streak-saver sweep on a timer (plan P3-4b).
///
/// In-process like every other schedule here (see reminder_scheduler.dart).
/// Never throws and never awaits: a sweep that fails is logged and the next
/// tick retries.
Timer startStreakSaverScheduler(CompositionRoot root) {
  return Timer.periodic(streakSaverTick, (_) {
    unawaited(_sweep(root));
  });
}

Future<void> _sweep(CompositionRoot root) async {
  try {
    final result = await root.sendStreakSavers(now: DateTime.now().toUtc());
    switch (result) {
      case Ok<int>(:final value):
        if (value > 0) {
          // ignore: avoid_print
          print('streak-saver sweep: pushed $value player(s)');
        }
      case Err<int>(:final error):
        // ignore: avoid_print
        print('streak-saver sweep failed: ${error.code} ${error.message}');
    }
  } on Object catch (error) {
    // ignore: avoid_print
    print('streak-saver sweep threw: $error');
  }
}
