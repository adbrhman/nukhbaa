/// The admin's "app version" card (batch 147, migration 0113) through the
/// real `AppApi` and `AdminApi` over a faked socket: it shows the newest
/// release and the minimum, raises the minimum to the newest release only
/// after a confirmation, and clears it.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/widgets/app_release_card.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/admin_harness.dart';

/// The server: release 214, and the minimum the admin stores.
final class _Server {
  int? minimum;
  final List<Map<String, Object?>> puts = <Map<String, Object?>>[];

  Future<http.Response> handle(http.Request request) async {
    if (request.url.path == '/app/latest-build') {
      return okJsonObject(<String, Object?>{
        'schema_version': 2,
        'published_at': '2026-10-15T03:00:00Z',
        'apk_url': 'https://example.com/nukhbaa-arm64-v8a-bbbbbbb.apk',
        'build_number': 214,
        'min_supported_build': ?minimum,
      });
    }
    if (request.url.path == '/admin/app/min-build') {
      final Map<String, Object?> body =
          jsonDecode(request.body) as Map<String, Object?>;
      puts.add(body);
      minimum = body['to_latest'] == true ? 214 : null;
      return okJsonObject(<String, Object?>{
        'schema_version': 1,
        'latest_build': 214,
        'min_supported_build': minimum,
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

void main() {
  testWidgets('the minimum is raised only after the confirmation', (
    tester,
  ) async {
    final _Server server = _Server();
    await _open(tester, server);

    expect(_text(tester, 'admin.appRelease.latest'), 'أحدث إصدار: رقم 214');
    expect(
      _text(tester, 'admin.appRelease.minimum'),
      'لا حد أدنى: لا يُطلب من أحد أن يحدّث',
    );

    await tester.tap(find.byKey(const Key('admin.appRelease.raise')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin.appRelease.confirm')), findsOneWidget);
    await tester.tap(find.byKey(const Key('admin.appRelease.cancel')));
    await tester.pumpAndSettle();
    expect(server.puts, isEmpty);

    await tester.tap(find.byKey(const Key('admin.appRelease.raise')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.appRelease.confirmRaise')));
    await tester.pumpAndSettle();

    expect(server.puts, <Map<String, Object?>>[
      <String, Object?>{'to_latest': true},
    ]);
    expect(_text(tester, 'admin.appRelease.minimum'), 'الحد الأدنى: رقم 214');
  });

  testWidgets('and cleared', (tester) async {
    final _Server server = _Server()..minimum = 214;
    await _open(tester, server);

    await tester.tap(find.byKey(const Key('admin.appRelease.clear')));
    await tester.pumpAndSettle();

    expect(server.puts, <Map<String, Object?>>[
      <String, Object?>{'to_latest': false},
    ]);
    expect(
      _text(tester, 'admin.appRelease.minimum'),
      'لا حد أدنى: لا يُطلب من أحد أن يحدّث',
    );
    expect(find.byKey(const Key('admin.appRelease.clear')), findsNothing);
  });
}
