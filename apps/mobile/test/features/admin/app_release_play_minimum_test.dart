/// The Google Play minimum on the admin's "app version" card (script 253,
/// migration 0206) through the real `AppApi` and `AdminApi` over a faked
/// socket: the admin types the versionCode live in Play (Arabic digits
/// too), an empty answer clears it, a number below 1 is refused before
/// anything is sent, and the APK minimum is never touched.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/widgets/app_release_card.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/admin_harness.dart';

/// The server: release 214, the APK minimum 214, and the Play minimum the
/// admin stores.
final class _Server {
  int? playMinimum;
  final List<Map<String, Object?>> playPuts = <Map<String, Object?>>[];
  int apkPuts = 0;

  Future<http.Response> handle(http.Request request) async {
    if (request.url.path == '/app/latest-build') {
      return okJsonObject(<String, Object?>{
        'schema_version': 2,
        'published_at': '2026-11-10T03:00:00Z',
        'apk_url': 'https://example.com/nukhbaa-arm64-v8a-bbbbbbb.apk',
        'build_number': 214,
        'min_supported_build': 214,
        'min_supported_play_build': ?playMinimum,
      });
    }
    if (request.url.path == '/admin/app/min-build') {
      apkPuts++;
      return http.Response('not expected', 500);
    }
    if (request.url.path == '/admin/app/min-play-build') {
      final Map<String, Object?> body =
          jsonDecode(request.body) as Map<String, Object?>;
      playPuts.add(body);
      playMinimum = body['build_number'] as int?;
      return okJsonObject(<String, Object?>{
        'schema_version': 1,
        'min_supported_play_build': playMinimum,
      });
    }
    return http.Response('not found', 404);
  }
}

Future<void> _open(WidgetTester tester, _Server server) async {
  final AdminHarness harness = buildAdminHarness(server.handle);
  addTearDown(harness.dispose);
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        home: const Scaffold(
          body: SingleChildScrollView(child: AppReleaseCard()),
        ),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String? _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data;

Future<void> _type(WidgetTester tester, String typed) async {
  await tester.ensureVisible(find.byKey(const Key('admin.appRelease.playSet')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('admin.appRelease.playSet')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('admin.appRelease.playDialog')), findsOneWidget);
  await tester.enterText(
    find.byKey(const Key('admin.appRelease.playInput')),
    typed,
  );
  await tester.tap(find.byKey(const Key('admin.appRelease.playSave')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the admin types the Play minimum; the APK one is untouched', (
    tester,
  ) async {
    final _Server server = _Server();
    await _open(tester, server);

    expect(
      _text(tester, 'admin.appRelease.playMinimum'),
      'نسخة Google Play: لا حد أدنى',
    );
    expect(_text(tester, 'admin.appRelease.minimum'), 'الحد الأدنى: رقم 214');

    await _type(tester, ' 845 ');

    expect(server.playPuts, <Map<String, Object?>>[
      <String, Object?>{'build_number': 845},
    ]);
    expect(server.apkPuts, 0);
    expect(
      _text(tester, 'admin.appRelease.playMinimum'),
      'نسخة Google Play: الحد الأدنى رقم 845',
    );
    expect(_text(tester, 'admin.appRelease.minimum'), 'الحد الأدنى: رقم 214');
  });

  testWidgets('Arabic digits are read as the number', (tester) async {
    final _Server server = _Server();
    await _open(tester, server);

    await _type(tester, '٨٤٥');

    expect(server.playPuts, <Map<String, Object?>>[
      <String, Object?>{'build_number': 845},
    ]);
  });

  testWidgets('an empty answer clears it', (tester) async {
    final _Server server = _Server()..playMinimum = 845;
    await _open(tester, server);

    await _type(tester, '');

    expect(server.playPuts, <Map<String, Object?>>[
      <String, Object?>{'build_number': null},
    ]);
    expect(
      _text(tester, 'admin.appRelease.playMinimum'),
      'نسخة Google Play: لا حد أدنى',
    );
  });

  testWidgets('zero or text is refused before anything is sent', (
    tester,
  ) async {
    final _Server server = _Server();
    await _open(tester, server);

    await _type(tester, '0');
    expect(find.byKey(const Key('admin.appRelease.error')), findsOneWidget);
    await _type(tester, 'abc');

    expect(server.playPuts, isEmpty);
    expect(find.byKey(const Key('admin.appRelease.error')), findsOneWidget);
  });

  testWidgets('cancelling sends nothing', (tester) async {
    final _Server server = _Server();
    await _open(tester, server);

    await tester.ensureVisible(
      find.byKey(const Key('admin.appRelease.playSet')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.appRelease.playSet')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.appRelease.playCancel')));
    await tester.pumpAndSettle();

    expect(server.playPuts, isEmpty);
  });
}
