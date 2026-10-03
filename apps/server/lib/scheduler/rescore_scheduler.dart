import 'dart:async';

import 'package:server/composition/composition_root.dart';
import 'package:server/scheduler/job_failure.dart';
import 'package:server/scheduler/single_flight.dart';
import 'package:shared/shared.dart';

/// How often the rescore sweep looks for results left half-scored. Most runs
/// find nothing and cost one indexed read.
const Duration rescoreTick = Duration(minutes: 15);

/// How long after boot the first sweep runs, clear of the startup probe and
/// the other schedulers' first runs.
const Duration rescoreFirstRunDelay = Duration(minutes: 5);

/// Finishes the scoring of recorded results whose scoring failed (see
/// `RescoreUnscoredResults`).
///
/// In-process like every other schedule here: never throws and never awaits,
/// a failed run is logged and retried on the next tick, and single_flight
/// keeps a slow run from being joined by the next one.
Timer startRescoreScheduler(CompositionRoot root) {
  Timer(rescoreFirstRunDelay, () {
    unawaited(_sweep(root));
  });
  return Timer.periodic(rescoreTick, (_) {
    unawaited(_sweep(root));
  });
}

final Future<void> Function(CompositionRoot) _sweep = singleFlight(_sweepOnce);

Future<void> _sweepOnce(CompositionRoot root) async {
  final sweep = root.rescoreUnscoredResults;
  if (sweep == null) {
    return;
  }
  try {
    final result = await sweep(now: DateTime.now().toUtc());
    switch (result) {
      case Ok<int>(:final value):
        if (value > 0) {
          // ignore: avoid_print
          print('rescore sweep: scored $value unfinished fixture(s)');
        }
      case Err<int>(:final error):
        // ignore: avoid_print
        print('rescore sweep failed: ${error.code} ${error.message}');
        await reportJobFailure(
          root,
          job: 'rescore',
          error: error,
          critical: true,
        );
    }
  } on Object catch (error, stackTrace) {
    // ignore: avoid_print
    print('rescore sweep threw: $error');
    await reportJobFailure(
      root,
      job: 'rescore',
      error: error,
      stackTrace: stackTrace,
      critical: true,
    );
  }
}
