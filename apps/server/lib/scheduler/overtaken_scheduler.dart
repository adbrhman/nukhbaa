import 'dart:async';

import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';

/// How often the overtaken sweep wakes up. Each sweep compares the
/// groups with the previous one (0067), so the interval is how fresh an
/// overtaken push can be.
const Duration overtakenTick = Duration(minutes: 30);

/// Starts the overtaken sweep on a timer (plan P3-4c).
///
/// In-process like every other schedule here (see reminder_scheduler.dart).
/// Never throws and never awaits: a sweep that fails is logged and the next
/// tick retries.
Timer startOvertakenScheduler(CompositionRoot root) {
  return Timer.periodic(overtakenTick, (_) {
    unawaited(_sweep(root));
  });
}

Future<void> _sweep(CompositionRoot root) async {
  try {
    final result = await root.sendOvertakenPushes(now: DateTime.now().toUtc());
    switch (result) {
      case Ok<int>(:final value):
        if (value > 0) {
          // ignore: avoid_print
          print('overtaken sweep: pushed $value player(s)');
        }
      case Err<int>(:final error):
        // ignore: avoid_print
        print('overtaken sweep failed: ${error.code} ${error.message}');
    }
  } on Object catch (error) {
    // ignore: avoid_print
    print('overtaken sweep threw: $error');
  }
}
