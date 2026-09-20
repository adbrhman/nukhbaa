import 'dart:async';

import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';

/// How often the settlement check runs. Once every finished day is settled a
/// run is a single cheap read, and an hourly tick keeps a day settled soon
/// after its grace period ends (see `SettleMatchDays`).
const Duration matchDaySettlementTick = Duration(hours: 1);

/// How long after boot the first check runs, so it never competes with the
/// startup probe, the first requests or the other schedulers' first runs.
const Duration matchDaySettlementFirstRunDelay = Duration(minutes: 2);

/// Freezes each Riyadh match day once it has ended (P1-5).
///
/// In-process like the other sweeps: one container, one schedule, and the rule
/// itself is unit-tested in `SettleMatchDays`. It never throws and never
/// awaits, so it cannot take the server down; a failed check is logged and
/// simply retried on the next tick, and the streak calendar falls back to
/// computing unsettled days live in the meantime.
Timer startMatchDaySettlementScheduler(CompositionRoot root) {
  Timer(matchDaySettlementFirstRunDelay, () {
    unawaited(_check(root));
  });
  return Timer.periodic(matchDaySettlementTick, (_) {
    unawaited(_check(root));
  });
}

Future<void> _check(CompositionRoot root) async {
  try {
    final result = await root.settleMatchDays(now: DateTime.now().toUtc());
    switch (result) {
      case Ok<int>(:final value):
        if (value > 0) {
          // ignore: avoid_print
          print('match-day settlement: settled $value day(s)');
        }
      case Err<int>(:final error):
        // ignore: avoid_print
        print('match-day settlement failed: ${error.code} ${error.message}');
    }
  } on Object catch (error) {
    // ignore: avoid_print
    print('match-day settlement threw: $error');
  }
}
