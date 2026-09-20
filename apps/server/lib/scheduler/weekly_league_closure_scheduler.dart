import 'dart:async';

import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';

/// How often the closing check runs. Until a week has ended and its grace
/// has passed, a run is a single cheap read, and an hourly tick judges a
/// week soon after its grace period ends (see `CloseWeeklyLeague`).
const Duration weeklyLeagueClosureTick = Duration(hours: 1);

/// How long after boot the first check runs, so it never competes with the
/// startup probe or the first requests.
const Duration weeklyLeagueClosureFirstRunDelay = Duration(minutes: 2);

/// Judges each weekly-league week once it has ended (P2-5).
///
/// In-process like the other sweeps: one container, one schedule, and the
/// rule itself is unit-tested in `CloseWeeklyLeague`. It never throws and
/// never awaits, so it cannot take the server down; a failed check is logged
/// and simply retried on the next tick. Retrying is safe: every event a week
/// writes is keyed on the user and the week, and a week is marked closed only
/// after all of them were recorded.
Timer startWeeklyLeagueClosureScheduler(CompositionRoot root) {
  Timer(weeklyLeagueClosureFirstRunDelay, () {
    unawaited(_check(root));
  });
  return Timer.periodic(weeklyLeagueClosureTick, (_) {
    unawaited(_check(root));
  });
}

Future<void> _check(CompositionRoot root) async {
  try {
    final result = await root.closeWeeklyLeague(now: DateTime.now().toUtc());
    switch (result) {
      case Ok<int>(:final value):
        if (value > 0) {
          // ignore: avoid_print
          print('weekly league: closed $value week(s)');
        }
      case Err<int>(:final error):
        // ignore: avoid_print
        print('weekly league closure failed: ${error.code} ${error.message}');
    }
  } on Object catch (error) {
    // ignore: avoid_print
    print('weekly league closure threw: $error');
  }
}
