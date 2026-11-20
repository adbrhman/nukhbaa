/// Script 293: the build floor of each channel on the owners' switches
/// tab, through the real providers and `AdminApi` over the auth harness's
/// fake server: in an emergency the owner clears the APK floor from there,
/// and the blocked players come back with no release.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/screens/sections/owner_switches_section.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart' show buildAuthHarness, okMe;

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

// NK293_02
void main() {
  testWidgets('the owner clears the APK floor from the switches tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    int? floor = 850;
    final List<http.Request> puts = <http.Request>[];
    final harness = buildAuthHarness((request) async {
      final String path = request.url.path;
      if (path == '/owner/switches') {
        return _json({'schema_version': 1, 'switches': <Object?>[]});
      }
      if (path == '/owner/mode') {
        return _json({
          'schema_version': 1,
          'mode': 'normal',
          'reason': null,
          'changed_by': null,
          'changed_at': '2026-11-20T00:00:00.000Z',
        });
      }
      if (path == '/app/latest-build') {
        return _json({
          'schema_version': 2,
          'published_at': '2026-11-19T00:00:00.000Z',
          'apk_url': 'https://example.com/app.apk',
          'build_number': 851,
          'min_supported_build': floor,
          'min_supported_play_build': null,
        });
      }
      if (path == '/admin/app/min-build') {
        puts.add(request);
        floor = null;
        return _json({'latest_build': 851, 'min_supported_build': null});
      }
      return okMe(
        const AuthenticatedUserDto(
          userId: 'u-owner-id',
          role: 'admin',
          status: 'active',
          isOwner: true,
        ),
      );
    }, seedToken: 'admin-jwt');
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp(
          locale: const Locale('ar'),
          home: const Scaffold(body: OwnerSwitchesSection()),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('admin.appRelease.clear')),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('admin.switches.list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('الحد الأدنى: رقم 850'), findsOneWidget);
    await tester.tap(find.byKey(const Key('admin.appRelease.clear')));
    await tester.pumpAndSettle();

    expect(jsonDecode(puts.single.body), {'to_latest': false});
    expect(find.text('لا حد أدنى: لا يُطلب من أحد أن يحدّث'), findsOneWidget);
  });
}
