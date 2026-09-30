import 'dart:async';

import 'package:server/scheduler/single_flight.dart';
import 'package:test/test.dart';

void main() {
  group('singleFlight', () {
    test('a call made while the previous one runs is skipped', () async {
      var runs = 0;
      final gate = Completer<void>();
      final run = singleFlight<int>((_) async {
        runs++;
        await gate.future;
      });

      final first = run(1);
      await run(2);
      expect(runs, 1, reason: 'the overlapping call must not start');

      gate.complete();
      await first;
      await run(3);
      expect(runs, 2, reason: 'a call after the first finished runs again');
    });

    test('a run that throws does not block the next one', () async {
      var runs = 0;
      final run = singleFlight<int>((_) async {
        runs++;
        throw StateError('boom');
      });

      await expectLater(run(1), throwsStateError);
      await expectLater(run(2), throwsStateError);
      expect(runs, 2);
    });
  });
}
