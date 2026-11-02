import 'dart:async';

import 'package:server/composition/composition_root.dart';
import 'package:server/scheduler/phased_timer.dart';
import 'package:server/scheduler/single_flight.dart';
import 'package:shared/shared.dart';

/// How often the cache epoch is read (migration 0194): one row a minute.
const Duration cacheEpochTick = Duration(minutes: 1);

/// Reads the cache epoch every [cacheEpochTick] and drops the read caches
/// when a write made outside this server moved it (script 196). Nothing to
/// do in a root without a watcher (tests).
Timer? startCacheEpochScheduler(CompositionRoot root) {
  if (root.cacheEpochWatcher == null) {
    return null;
  }
  return phasedPeriodic(cacheEpochPhase, cacheEpochTick, (_) {
    unawaited(_check(root));
  });
}

final Future<void> Function(CompositionRoot) _check = singleFlight(_checkOnce);

Future<void> _checkOnce(CompositionRoot root) async {
  final watcher = root.cacheEpochWatcher;
  if (watcher == null) {
    return;
  }
  try {
    final result = await watcher.check();
    switch (result) {
      case Ok<String?>(:final value):
        if (value != null) {
          // ignore: avoid_print
          print('cache $value -- read caches dropped');
        }
      case Err<String?>(:final error):
        // A missed reading drops nothing; the next one catches up.
        // ignore: avoid_print
        print('cache epoch read failed: ${error.code} ${error.message}');
    }
  } on Object catch (error) {
    // ignore: avoid_print
    print('cache epoch read threw: $error');
  }
}
