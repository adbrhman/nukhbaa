/// The Google Play build (script 112), through the real [UpdateGate], the
/// real `AppApi` and `GET /app/latest-build`, with only the socket, the
/// installer and the store opener faked. Play installs the app's updates,
/// so the in-app installer is never reached: a build older than the
/// minimum shows the update screen, whose button opens the store listing,
/// and a release waiting offers no install row and no home reminder. The
/// same release on the site's build does offer the row.
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

/// Fails the test if the in-app installer is ever started.
final class _ForbiddenUpdater implements InAppUpdater {
  @override
  Stream<UpdateProgress>? start(LatestBuildDto build) {
    fail('the in-app installer was started');
  }

  @override
  Future<void> cancel() async {}
}

/// Serves the newest release `bbbbbbb`, build 214, with [minimum].
final class _Releases {
  _Releases(this.minimum);

  final int? minimum;

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

/// Opens the gate on build 200 (`aaaaaaa`), eight days old; returns the
/// links the store opener was asked to open.
Future<List<Uri>> _open(
  WidgetTester tester,
  _Releases releases, {
  required String channel,
}) async {
  final harness = buildAuthHarness(releases.handle, seedToken: 'jwt');
  addTearDown(harness.dispose);
  final List<Uri> opened = <Uri>[];
  final String old = DateTime.now()
      .toUtc()
      .subtract(const Duration(days: 8))
      .toIso8601String();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...harness.overrides,
        inAppUpdaterProvider.overrideWithValue(_ForbiddenUpdater()),
        storeOpenerProvider.overrideWithValue((Uri uri) async {
          opened.add(uri);
        }),
      ],
      retry: (retryCount, error) => null,
      child: MaterialApp(
        home: UpdateGate(
          isWeb: false,
          buildSha: 'aaaaaaa',
          buildNumber: 200,
          builtAt: old,
          channel: channel,
          child: Consumer(
            builder: (context, ref, _) => Text(
              'child nudge=${ref.watch(updateNudgeProvider)} '
              'row=${ref.watch(pendingUpdateProvider) != null}',
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return opened;
}

void main() {
  testWidgets('Play build older than the minimum: the update screen opens '
      'the store listing', (tester) async {
    final List<Uri> opened = await _open(
      tester,
      _Releases(210),
      channel: playChannel,
    );

    expect(find.byKey(const Key('update.required')), findsOneWidget);
    expect(find.textContaining('child'), findsNothing);

    await tester.tap(find.byKey(const Key('update.required.install')));
    await tester.pumpAndSettle();

    expect(opened, <Uri>[Uri.parse(playStoreListing)]);
  });

  testWidgets('Play build with a release waiting: no install row, no home '
      'reminder', (tester) async {
    await _open(tester, _Releases(null), channel: playChannel);

    expect(find.text('child nudge=false row=false'), findsOneWidget);
  });

  testWidgets('the site build with the same release waiting offers both', (
    tester,
  ) async {
    await _open(tester, _Releases(null), channel: '');

    expect(find.text('child nudge=true row=true'), findsOneWidget);
  });
}
