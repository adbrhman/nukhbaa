import 'dart:async';

import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';

/// How often the badge evaluation runs. A run is one grouped read of the
/// event stream plus one insert per badge newly earned, so a quarter of an
/// hour keeps a badge close behind the act that earned it (see
/// `EvaluateBadges`).
const Duration badgeEvaluationTick = Duration(minutes: 15);

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
  return Timer.periodic(badgeEvaluationTick, (_) {
    unawaited(_check(root));
  });
}

Future<void> _check(CompositionRoot root) async {
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
    }
  } on Object catch (error) {
    // ignore: avoid_print
    print('badge evaluation threw: $error');
  }
}
