/// The "update available" row on the sign-in screen (batch 111): a player
/// who cannot sign in -- a forgotten password, say -- can still install the
/// newest release. Real [UpdateGate], `AppApi` and [SessionGate]; only the
/// socket ([buildAuthHarness]) and the native installer are faked.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/auth/session_gate.dart';
import 'package:mobile/features/update/in_app_updater.dart';
import 'package:mobile/features/update/update_gate.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

final class _FakeUpdater implements InAppUpdater {
  final List<LatestBuildDto> started = <LatestBuildDto>[];

  @override
  Stream<UpdateProgress>? start(LatestBuildDto build) {
    started.add(build);
    return Stream<UpdateProgress>.value(
      const UpdateProgress(UpdatePhase.completed),
    );
  }

  @override
  Future<void> cancel() async {}
}

Future<http.Response> _server(http.Request request) async {
  if (request.url.path == '/app/latest-build') {
    return http.Response(
      jsonEncode(<String, Object?>{
        'schema_version': 1,
        'published_at': '2026-10-12T22:47:00Z',
        'apk_url':
            'https://github.com/adbrhman/nukhbaa/releases/download/'
            'build-bbbbbbb/nukhbaa-arm64-v8a-bbbbbbb.apk',
      }),
      200,
      headers: const {'content-type': 'application/json'},
    );
  }
  return http.Response('', 401);
}

/// Launches the signed-out app under [UpdateGate] as Android build
/// [buildSha].
Future<_FakeUpdater> _openSignIn(
  WidgetTester tester, {
  required String buildSha,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final harness = buildAuthHarness(_server);
  addTearDown(harness.dispose);
  final _FakeUpdater updater = _FakeUpdater();

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
          buildSha: buildSha,
          child: const SessionGate(),
        ),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return updater;
}

void main() {
  testWidgets('a newer release shows the row before sign-in', (tester) async {
    final _FakeUpdater updater = await _openSignIn(tester, buildSha: 'aaaaaaa');

    expect(find.byKey(const Key('signIn.submit')), findsOneWidget);
    expect(find.byKey(const Key('signIn.update')), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(updater.started, isEmpty);
  });

  testWidgets('the newest build shows no row', (tester) async {
    await _openSignIn(tester, buildSha: 'bbbbbbb');

    expect(find.byKey(const Key('signIn.submit')), findsOneWidget);
    expect(find.byKey(const Key('signIn.update')), findsNothing);
  });

  testWidgets('tapping the row installs that release', (tester) async {
    final _FakeUpdater updater = await _openSignIn(tester, buildSha: 'aaaaaaa');

    await tester.ensureVisible(find.byKey(const Key('signIn.update')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('signIn.update')));
    // The progress dialog closes 600 ms after the terminal event.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(updater.started, hasLength(1));
    expect(updater.started.single.apkUrl, contains('/build-bbbbbbb/'));
    expect(find.byType(AlertDialog), findsNothing);
  });
}
