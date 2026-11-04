import 'dart:async';

import 'package:application/application.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/scheduler/job_failure.dart';
import 'package:server/scheduler/phased_timer.dart';
import 'package:server/scheduler/single_flight.dart';
import 'package:shared/shared.dart';

/// How often the sports publisher runs: the live board is refreshed every
/// two minutes, and a minute keeps a post close to its time.
const Duration publisherTick = Duration(minutes: 1);

/// Runs the sports publisher (migration 0200) every [publisherTick], when
/// `NUKHBA_PUBLISHER` is `dry_run` or `on`. Its state is in the database,
/// so a restart picks up where it was: a goal pending stays pending, a post
/// queued stays queued, and a post cut while being sent is marked
/// uncertain, never sent twice.
Timer? startPublisherScheduler(CompositionRoot root) {
  final tick = root.publisherTick;
  if (tick == null) {
    return null;
  }
  // ignore: avoid_print
  print('publisher: started (${root.publisherMode.name})');
  return phasedPeriodic(publisherPhase, publisherTick, (_) {
    unawaited(_run(root));
  });
}

final Future<void> Function(CompositionRoot) _run = singleFlight(_runOnce);

Future<void> _runOnce(CompositionRoot root) async {
  final tick = root.publisherTick;
  if (tick == null) {
    return;
  }
  try {
    final result = await tick(now: DateTime.now().toUtc());
    switch (result) {
      case Ok<PublisherTickReport>(:final value):
        if (!value.isEmpty) {
          // ignore: avoid_print
          print(
            'publisher: seen=${value.seen} withdrawn=${value.withdrawn} '
            'confirmed=${value.confirmed} queued=${value.queued} '
            'sent=${value.sent}',
          );
          for (final note in value.notes) {
            // ignore: avoid_print
            print('publisher:   $note');
          }
        }
        for (final item in value.attention) {
          await reportNeedsAdmin(
            root,
            job: 'publisher',
            subject: item.subject,
            code: item.code,
            message: item.message,
          );
        }
      case Err<PublisherTickReport>(:final error):
        // ignore: avoid_print
        print('publisher failed: ${error.code} ${error.message}');
        await reportJobFailure(root, job: 'publisher', error: error);
    }
  } on Object catch (error, stackTrace) {
    // ignore: avoid_print
    print('publisher threw: $error');
    await reportJobFailure(
      root,
      job: 'publisher',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
