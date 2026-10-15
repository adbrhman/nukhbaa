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

  // Last in this file: once drained, no sweep starts again in this process.
  group('drainSweeps (M-28)', () {
    test('waits for the running sweep, then starts none', () async {
      var runs = 0;
      final gate = Completer<void>();
      final run = singleFlight<int>((_) async {
        runs++;
        await gate.future;
      });

      final first = run(1);
      var drained = false;
      final drain = drainSweeps().then((_) => drained = true);
      await Future<void>.delayed(Duration.zero);
      expect(drained, isFalse, reason: 'a sweep is still running');

      gate.complete();
      await first;
      await drain;
      expect(drained, isTrue);

      await run(2);
      expect(runs, 1, reason: 'no sweep starts once the server is stopping');
    });
  });
}
