/// The in-app install's progress dialog (audit L-15): the plugin's own
/// English words wait behind "details", and a download that goes quiet is
/// cancelled, not left running, before the browser fallback is offered.
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/update/in_app_updater.dart';
import 'package:mobile/features/update/update_gate.dart';

/// Emits one downloading event with a raw message, then nothing.
final class _QuietUpdater implements InAppUpdater {
  final StreamController<UpdateProgress> _events =
      StreamController<UpdateProgress>();
  int cancels = 0;

  @override
  Stream<UpdateProgress>? start(LatestBuildDto build) {
    _events.add(
      const UpdateProgress(
        UpdatePhase.downloading,
        percent: 10,
        message: 'OTA_UPDATE: socket reset',
      ),
    );
    return _events.stream;
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }
}

const LatestBuildDto _build = LatestBuildDto(
  publishedAt: '2026-10-15T03:00:00Z',
  apkUrl: 'https://example.com/nukhbaa-arm64-v8a-bbbbbbb.apk',
);

Future<_QuietUpdater> _start(WidgetTester tester) async {
  final _QuietUpdater updater = _QuietUpdater();
  addTearDown(updater._events.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [inAppUpdaterProvider.overrideWithValue(updater)],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => TextButton(
            key: const Key('install'),
            onPressed: () => unawaited(installUpdate(context, ref, _build)),
            child: const Text('install'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('install')));
  await tester.pump();
  await tester.pump();
  return updater;
}

void main() {
  testWidgets("the plugin's words wait behind details", (tester) async {
    await _start(tester);

    expect(find.text('OTA_UPDATE: socket reset'), findsNothing);
    await tester.tap(find.byKey(const Key('update.progress.details')));
    await tester.pump();

    expect(find.text('OTA_UPDATE: socket reset'), findsOneWidget);

    // Let the silence bound run out, so no timer outlives the test.
    await tester.pump(const Duration(seconds: 91));
    await tester.pumpAndSettle();
  });

  testWidgets('a download that goes quiet is cancelled before the '
      'fallback', (tester) async {
    final _QuietUpdater updater = await _start(tester);

    await tester.pump(const Duration(seconds: 91));
    await tester.pumpAndSettle();

    expect(updater.cancels, 1);
    expect(find.text('تعذّر التحديث داخل التطبيق'), findsOneWidget);
  });
}
