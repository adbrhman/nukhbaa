import 'dart:async';

import 'package:server/composition/composition_root.dart';
import 'package:server/scheduler/job_failure.dart';
import 'package:server/scheduler/phased_timer.dart';
import 'package:server/scheduler/single_flight.dart';
import 'package:shared/shared.dart';

/// How often the invitation sweep runs (migration 0073). An invitee
/// qualifies once a prediction is graded. Every half hour the sweep was
/// 8.5% of the database's time (2026-10-17, about half a second a call);
/// every three hours an invitation is paid within three hours of its grade
/// (script 111). The payment is dated by the sweep, so one graded in the
/// last three hours of a month may count in the next month's tie-break.
/// With the `referrals` flag off the sweep returns at its first line.
const Duration referralQualificationTick = Duration(hours: 3);

/// The first sweep after boot, clear of the startup work.
const Duration referralQualificationFirstRunDelay = Duration(minutes: 4);

/// Starts the in-process invitation sweep. Every run is safe to repeat: a
/// payment is one event with a unique dedupe key, so a second pass (or a
/// second server) writes nothing.
Timer startReferralQualificationScheduler(CompositionRoot root) {
  Timer(referralQualificationFirstRunDelay, () {
    unawaited(_sweep(root));
  });
  return phasedPeriodic(referralQualificationPhase, referralQualificationTick, (
    _,
  ) {
    unawaited(_sweep(root));
  });
}

/// One run at a time: a tick that fires while the previous run is still
/// going is skipped, not stacked (see single_flight.dart).
final Future<void> Function(CompositionRoot) _sweep = singleFlight(_sweepOnce);

Future<void> _sweepOnce(CompositionRoot root) async {
  try {
    final result = await root.qualifyReferrals(now: DateTime.now().toUtc());
    switch (result) {
      case Ok<int>(:final value):
        if (value > 0) {
          // ignore: avoid_print
          print('referrals: $value invitation event(s) written');
        }
      case Err<int>(:final error):
        // ignore: avoid_print
        print('referral sweep failed: ${error.code} ${error.message}');
        await reportJobFailure(
          root,
          job: 'referral-qualification',
          error: error,
        );
    }
  } on Object catch (error, stackTrace) {
    // ignore: avoid_print
    print('referral sweep threw: $error');
    await reportJobFailure(
      root,
      job: 'referral-qualification',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
