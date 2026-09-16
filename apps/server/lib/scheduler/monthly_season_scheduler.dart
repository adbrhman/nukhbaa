import 'dart:async';

import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';

/// How often the upcoming-month check runs. The rule creates a month a week
/// before it starts, so a few checks a day leave a wide margin.
const Duration monthlySeasonTick = Duration(hours: 6);

/// How long after boot the first check runs, so it never competes with the
/// startup probe or the first requests.
const Duration monthlySeasonFirstRunDelay = Duration(minutes: 1);

/// Keeps the next monthly contest in place without an admin.
///
/// In-process like the reminder sweep: one container, one schedule, and the
/// rule itself is unit-tested in `EnsureUpcomingMonthlySeasons`. It never
/// throws and never awaits, so it cannot take the server down; a failed check
/// is logged and simply retried on the next tick.
Timer startMonthlySeasonScheduler(CompositionRoot root) {
  Timer(monthlySeasonFirstRunDelay, () {
    unawaited(_check(root));
  });
  return Timer.periodic(monthlySeasonTick, (_) {
    unawaited(_check(root));
  });
}

Future<void> _check(CompositionRoot root) async {
  try {
    final result = await root.ensureUpcomingMonthlySeasons(
      now: DateTime.now().toUtc(),
    );
    switch (result) {
      case Ok<int>(:final value):
        if (value > 0) {
          // ignore: avoid_print
          print('monthly season check: created $value upcoming month(s)');
        }
      case Err<int>(:final error):
        // ignore: avoid_print
        print('monthly season check failed: ${error.code} ${error.message}');
    }
  } on Object catch (error) {
    // ignore: avoid_print
    print('monthly season check threw: $error');
  }
}
