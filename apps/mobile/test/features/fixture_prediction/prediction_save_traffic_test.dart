/// The save gate and the history refresher (script 256), on their own: how
/// many saves are out at once, and how many history reads a burst costs.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/fixture_prediction/prediction_save_traffic.dart';

void main() {
  group('PredictionSaveGate', () {
    test('the app gate lets three saves out at once', () {
      expect(PredictionSaveGate().limit, maxConcurrentPredictionSaves);
      expect(maxConcurrentPredictionSaves, 3);
    });

    test('runs `limit` jobs at once and starts the others in order', () async {
      final PredictionSaveGate gate = PredictionSaveGate(limit: 2);
      final List<String> started = <String>[];
      final Map<String, Completer<void>> release = <String, Completer<void>>{
        for (final String name in <String>['a', 'b', 'c', 'd'])
          name: Completer<void>(),
      };
      Future<String> job(String name) => gate.run<String>(() async {
        started.add(name);
        await release[name]!.future;
        return name;
      });

      final List<Future<String>> results = <Future<String>>[
        for (final String name in <String>['a', 'b', 'c', 'd']) job(name),
      ];
      await Future<void>.delayed(Duration.zero);
      expect(started, <String>['a', 'b']);
      expect(gate.running, 2);
      expect(gate.waiting, 2);

      release['a']!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(started, <String>['a', 'b', 'c']);
      expect(gate.running, 2);
      expect(gate.waiting, 1);

      release['b']!.complete();
      release['c']!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(started, <String>['a', 'b', 'c', 'd']);

      release['d']!.complete();
      expect(await Future.wait(results), <String>['a', 'b', 'c', 'd']);
      expect(gate.running, 0);
      expect(gate.waiting, 0);
    });

    test('a job that throws still frees its place', () async {
      final PredictionSaveGate gate = PredictionSaveGate(limit: 1);
      final Future<void> failing = gate.run<void>(
        () async => throw StateError('boom'),
      );
      final Future<int> next = gate.run<int>(() async => 7);

      await expectLater(failing, throwsStateError);
      expect(await next, 7);
      expect(gate.running, 0);
      expect(gate.waiting, 0);
    });
  });

  group('PredictionHistoryRefresher', () {
    const Duration window = Duration(milliseconds: 40);
    const Duration pastTwoWindows = Duration(milliseconds: 200);

    test('the first ask of a burst reads at once, the rest share one more '
        'read', () async {
      int reads = 0;
      final PredictionHistoryRefresher refresher = PredictionHistoryRefresher(
        refresh: () => reads++,
        window: window,
      );
      addTearDown(refresher.dispose);

      refresher.request();
      expect(reads, 1, reason: 'the first save reads the history at once');

      refresher.request();
      refresher.request();
      refresher.request();
      expect(reads, 1, reason: 'the others wait for the window to close');

      await Future<void>.delayed(pastTwoWindows);
      expect(reads, 2, reason: 'three more asks cost one read, not three');

      refresher.request();
      expect(reads, 3, reason: 'a new burst reads at once again');
    });

    test('a single ask costs a single read', () async {
      int reads = 0;
      final PredictionHistoryRefresher refresher = PredictionHistoryRefresher(
        refresh: () => reads++,
        window: window,
      );
      addTearDown(refresher.dispose);

      refresher.request();
      await Future<void>.delayed(pastTwoWindows);
      expect(reads, 1);
    });

    test('nothing is read after dispose or once its owner is gone', () async {
      int reads = 0;
      bool alive = true;
      final PredictionHistoryRefresher refresher = PredictionHistoryRefresher(
        refresh: () => reads++,
        alive: () => alive,
        window: window,
      );

      refresher.request();
      refresher.request();
      refresher.dispose();
      await Future<void>.delayed(pastTwoWindows);
      expect(reads, 1, reason: 'the waiting ask died with the refresher');

      alive = false;
      refresher.request();
      expect(reads, 1, reason: 'an owner that is gone reads nothing');
    });
  });
}
