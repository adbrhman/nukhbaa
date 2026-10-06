/// The Android update check on a return to the app, through the real
/// [UpdateGate], the real `AppApi`, `GET /app/latest-build` and the real
/// account tab, with only the socket faked: a release published while the
/// app sat in the background shows its row once the player comes back,
/// without a new launch.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/auth/session_gate.dart';
import 'package:mobile/features/update/update_gate.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

/// Serves [newest] as the latest release and counts the checks.
final class _Releases {
  String newest = 'aaaaaaa';
  int checks = 0;

  Future<http.Response> handle(http.Request request) async {
    if (request.url.path == '/app/latest-build') {
      checks++;
      return http.Response(
        jsonEncode(<String, Object?>{
          'schema_version': 1,
          'published_at': '2026-10-07T03:00:00Z',
          'apk_url':
              'https://github.com/adbrhman/nukhbaa/releases/download/'
              'build-$newest/nukhbaa-arm64-v8a-$newest.apk',
        }),
        200,
        headers: const {'content-type': 'application/json'},
      );
    }
    return okMe(sampleUser);
  }
}

void main() {
  testWidgets('a release published in the background shows on return', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final _Releases releases = _Releases();
    final harness = buildAuthHarness(releases.handle, seedToken: 'saved-jwt');
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        retry: (retryCount, error) => null,
        child: MaterialApp(
          home: UpdateGate(
            isWeb: false,
            buildSha: 'aaaaaaa',
            child: const SessionGate(),
          ),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav.item.account')));
    await tester.pumpAndSettle();
    expect(releases.checks, 1);
    expect(find.byKey(const Key('account.update')), findsNothing);

    // A newer build is published while the app is in the background.
    releases.newest = 'bbbbbbb';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(releases.checks, 2);
    expect(find.byKey(const Key('account.update')), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
