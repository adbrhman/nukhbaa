import 'dart:async';

import 'package:server/composition/composition_root.dart';
import 'package:server/scheduler/phased_timer.dart';
import 'package:server/scheduler/single_flight.dart';
import 'package:shared/shared.dart';

/// How often the support pictures still in the database are moved.
const Duration supportImageTick = Duration(minutes: 10);

/// Moves the support pictures still kept in the database to Storage, 20 a
/// run (script 199). Nothing to do without Storage (no secret key) or in a
/// test root.
Timer? startSupportImageScheduler(CompositionRoot root) {
  if (root.moveSupportImages == null) {
    return null;
  }
  return phasedPeriodic(supportImagePhase, supportImageTick, (_) {
    unawaited(_move(root));
  });
}

final Future<void> Function(CompositionRoot) _move = singleFlight(_moveOnce);

Future<void> _moveOnce(CompositionRoot root) async {
  final move = root.moveSupportImages;
  if (move == null) {
    return;
  }
  try {
    final result = await move();
    switch (result) {
      case Ok<int>(:final value):
        if (value > 0) {
          // ignore: avoid_print
          print('support pictures: moved $value to Storage');
        }
      case Err<int>(:final error):
        // ignore: avoid_print
        print('support pictures: move failed: ${error.code} ${error.message}');
    }
  } on Object catch (error) {
    // ignore: avoid_print
    print('support pictures: move threw: $error');
  }
}
