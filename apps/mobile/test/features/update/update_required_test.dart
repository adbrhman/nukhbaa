/// The oldest supported build and the reminder (batch 147, audit L-15),
/// through the real [UpdateGate], the real `AppApi` and
/// `GET /app/latest-build`, with only the socket and the installer faked:
/// a build older than the minimum shows the update screen and nothing else,
/// and its download starts by itself (script 148); cancelled, the screen
/// stays, warns and starts it again from its button; a build at the
/// minimum, a local run and a
/// minimum the admin cleared go on as before; a build a week old with a
/// release waiting raises the home reminder, a fresh one does not.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/update/in_app_updater.dart';
import 'package:mobile/features/update/update_gate.dart';

import '../../support/auth_harness.dart';

final class _FakeUpdater implements InAppUpdater {
  _FakeUpdater([this.ends = UpdatePhase.completed]);

  /// The phase each download ends in.
  final UpdatePhase ends;

  final List<LatestBuildDto> started = <LatestBuildDto>[];

  @override
  Stream<UpdateProgress>? start(LatestBuildDto build) {
    started.add(build);
    return Stream<UpdateProgress>.value(UpdateProgress(ends));
  }

  @override
  Future<void> cancel() async {}
}

/// Serves the newest release `bbbbbbb`, build 214, with [minimum].
final class _Releases {
  _Releases(this.minimum);

  int? minimum;

  Future<http.Response> handle(http.Request request) async {
    if (request.url.path == '/app/latest-build') {
      return http.Response(
        jsonEncode(<String, Object?>{
          'schema_version': 2,
          'published_at': '2026-10-15T03:00:00Z',
          'apk_url':
              'https://github.com/adbrhman/nukhbaa/releases/download/'
              'build-bbbbbbb/nukhbaa-arm64-v8a-bbbbbbb.apk',
          'build_number': 214,
          'min_supported_build': ?minimum,
        }),
        200,
        headers: const {'content-type': 'application/json'},
      );
    }
    return http.Response('not found', 404);
  }
}

Future<_FakeUpdater> _open(
  WidgetTester tester,
  _Releases releases, {
  int buildNumber = 200,
  String builtAt = '',
  UpdatePhase ends = UpdatePhase.completed,
}) async {
  final harness = buildAuthHarness(releases.handle, seedToken: 'jwt');
  addTearDown(harness.dispose);
  final _FakeUpdater updater = _FakeUpdater(ends);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...harness.overrides,
        inAppUpdaterProvider.overrideWithValue(updater),
      ],
      retry: (retryCount, error) => null,
      child: MaterialApp(
        home: UpdateGate(
          isWeb: false,
          buildSha: 'aaaaaaa',
          buildNumber: buildNumber,
          builtAt: builtAt,
          child: Consumer(
            builder: (context, ref, _) =>
                Text('child nudge=${ref.watch(updateNudgeProvider)}'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // A finished download closes its dialog after a short pause.
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  return updater;
}

void main() {
  testWidgets('older than the minimum: the update screen and nothing else, '
      'and the download starts by itself', (tester) async {
    final _FakeUpdater updater = await _open(tester, _Releases(210));

    expect(find.byKey(const Key('update.required')), findsOneWidget);
    expect(find.text('يتوفر تحديث جديد · حدِّثه لتكمل'), findsOneWidget);
    expect(find.textContaining('child'), findsNothing);
    // Nobody tapped anything.
    expect(updater.started.single.apkUrl, contains('/build-bbbbbbb/'));
    expect(find.byKey(const Key('update.required.warning')), findsNothing);
  });

  testWidgets('cancelled: the screen stays, says the app opens only once '
      'updated, and its button starts the download again', (tester) async {
    final _FakeUpdater updater = await _open(
      tester,
      _Releases(210),
      ends: UpdatePhase.cancelled,
    );

    expect(updater.started, hasLength(1));
    expect(find.byKey(const Key('update.required')), findsOneWidget);
    expect(find.textContaining('child'), findsNothing);
    expect(
      find.text('لتدخل إلى نُخبة حدِّث التطبيق أولًا. لن يفتح قبل التحديث.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('update.required.install')));
    await tester.pumpAndSettle();

    expect(updater.started, hasLength(2));
    expect(find.byKey(const Key('update.required')), findsOneWidget);
  });

  testWidgets('a return to the app does not start a second download by '
      'itself', (tester) async {
    final _FakeUpdater updater = await _open(
      tester,
      _Releases(210),
      ends: UpdatePhase.cancelled,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(updater.started, hasLength(1));
    expect(find.byKey(const Key('update.required.warning')), findsOneWidget);
  });

  testWidgets('at the minimum, the app goes on', (tester) async {
    await _open(tester, _Releases(200));

    expect(find.byKey(const Key('update.required')), findsNothing);
    expect(find.textContaining('child'), findsOneWidget);
  });

  testWidgets('a local run (no build number) is never held back', (
    tester,
  ) async {
    await _open(tester, _Releases(210), buildNumber: 0);

    expect(find.byKey(const Key('update.required')), findsNothing);
  });

  testWidgets('a minimum cleared by the admin lets the app go on at the '
      'next check', (tester) async {
    final _Releases releases = _Releases(210);
    await _open(tester, releases);
    expect(find.byKey(const Key('update.required')), findsOneWidget);

    releases.minimum = null;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('update.required')), findsNothing);
    expect(find.textContaining('child'), findsOneWidget);
  });

  testWidgets('a build a week old with a release waiting raises the home '
      'reminder', (tester) async {
    final String old = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: 8))
        .toIso8601String();
    await _open(tester, _Releases(null), builtAt: old);

    expect(find.text('child nudge=true'), findsOneWidget);
  });

  testWidgets('a fresh build does not', (tester) async {
    final String fresh = DateTime.now().toUtc().toIso8601String();
    await _open(tester, _Releases(null), builtAt: fresh);

    expect(find.text('child nudge=false'), findsOneWidget);
  });
}
