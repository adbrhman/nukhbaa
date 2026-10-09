import 'dart:async';

import 'package:application/application.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/scheduler/job_failure.dart';
import 'package:server/scheduler/single_flight.dart';
import 'package:shared/shared.dart';

/// How often the head-to-head jobs run. A round locks at its first kickoff,
/// so the tick bounds how late a lock can come; outside those moments a run
/// is a handful of cheap reads.
const Duration h2hLeagueTick = Duration(minutes: 5);

/// How long after boot the first run starts, so it never competes with the
/// startup probe or the first requests.
const Duration h2hLeagueFirstRunDelay = Duration(minutes: 3);

/// Runs the monthly head-to-head league (migration 0100), three jobs in
/// order on each tick:
///
/// 1. `RunH2hRounds`: approves a regular day 24 hours before its first
///    kickoff when no admin did, and locks each round once its first match
///    has started.
/// 2. `CloseH2hMonth`: judges a month once it has ended and its results are
///    in (a pilot month closes without a single event).
/// 3. `DrawH2hMonth`: draws the month once it opened, after the previous
///    month was judged.
///
/// Closing comes before drawing so a new month is drawn on the tick its
/// predecessor was judged. Each job is unit-tested in the application
/// package and is idempotent: a failed job is logged, reported, and simply
/// run again on the next tick, and it does not stop the jobs after it.
/// The scheduler never throws and never awaits, so it cannot take the
/// server down.
Timer startH2hLeagueScheduler(CompositionRoot root) {
  Timer(h2hLeagueFirstRunDelay, () {
    unawaited(_tick(root));
  });
  return Timer.periodic(h2hLeagueTick, (_) {
    unawaited(_tick(root));
  });
}

/// One run at a time: a tick that fires while the previous run is still
/// going is skipped, not stacked (see single_flight.dart).
final Future<void> Function(CompositionRoot) _tick = singleFlight(_runOnce);

Future<void> _runOnce(CompositionRoot root) async {
  final now = DateTime.now().toUtc();
  await _job(root, 'h2h-rounds', () async {
    final result = await root.runH2hRounds(now: now);
    return switch (result) {
      Ok<H2hRoundsRun>(:final value) => Result<String?>.ok(
        value.approved + value.locked == 0
            ? null
            : 'approved ${value.approved}, locked ${value.locked}',
      ),
      Err<H2hRoundsRun>(:final error) => Result<String?>.err(error),
    };
  });
  await _job(root, 'h2h-close', () async {
    final result = await root.closeH2hMonth(now: now);
    return switch (result) {
      Ok<int>(:final value) => Result<String?>.ok(
        value == 0 ? null : 'closed $value month(s)',
      ),
      Err<int>(:final error) => Result<String?>.err(error),
    };
  });
  await _job(root, 'h2h-draw', () async {
    final result = await root.drawH2hMonth(now: now);
    return switch (result) {
      Ok<int>(:final value) => Result<String?>.ok(
        value == 0 ? null : 'seated $value',
      ),
      Err<int>(:final error) => Result<String?>.err(error),
    };
  });
}

/// Runs one job: prints its summary when it did something, and logs and
/// reports a failure or a throw without stopping the next job.
Future<void> _job(
  CompositionRoot root,
  String job,
  Future<Result<String?>> Function() run,
) async {
  try {
    final result = await run();
    switch (result) {
      case Ok<String?>(:final value):
        if (value != null) {
          // ignore: avoid_print
          print('$job: $value');
        }
      case Err<String?>(:final error):
        // ignore: avoid_print
        print('$job failed: ${error.code} ${error.message}');
        await reportJobFailure(root, job: job, error: error);
    }
  } on Object catch (error, stackTrace) {
    // ignore: avoid_print
    print('$job threw: $error');
    await reportJobFailure(
      root,
      job: job,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
