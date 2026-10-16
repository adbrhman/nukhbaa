/// The inbox row that tells a player their double is free again (script 89,
/// migration 0172), through the real [NotificationsScreen] over the real
/// API with only the socket faked: the row reads in words, never as the raw
/// `double_released` token or the generic inbox title.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/notifications/notifications_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

http.Response _inbox() => http.Response(
  jsonEncode(<String, Object?>{
    'schema_version': 2,
    'recipient_id': 'u1',
    'unread_count': 1,
    'notifications': <Object?>[
      <String, Object?>{
        'schema_version': 2,
        'id': 'n1',
        'recipient_id': 'u1',
        'kind': 'double_released',
        'read': false,
        'created_at': '2026-10-15T18:10:00Z',
        'fixture_id': '66666666-6666-4666-8666-666666666666',
      },
    ],
  }),
  200,
  headers: const {'content-type': 'application/json'},
);

void main() {
  testWidgets('a released double reads in words, with the bolt', (
    tester,
  ) async {
    final harness = buildAuthHarness((request) async {
      if (request.url.path == '/notifications') return _inbox();
      return http.Response('not found', 404);
    }, seedToken: 'jwt');
    addTearDown(harness.dispose);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        retry: (retryCount, error) => null,
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const NotificationsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Text label = tester.widget<Text>(
      find.byKey(const Key('notifications.label.n1')),
    );
    expect(label.data, contains('فتحرّرت مضاعفة يومها'));
    expect(find.textContaining('double_released'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('notifications.item.n1')),
        matching: find.byIcon(Icons.bolt_rounded),
      ),
      findsOneWidget,
    );
  });
}
