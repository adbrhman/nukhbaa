/// Which inbox rows lead somewhere (audit L-04), through the real screen
/// over the real `NotificationsApi` with only the socket faked: a scored
/// match and a new member open a page; an announcement reads in place.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/notifications/notifications_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

Map<String, Object?> _row(String id, String kind, Map<String, Object?> more) =>
    <String, Object?>{
      'schema_version': 2,
      'id': id,
      'recipient_id': 'u1',
      'kind': kind,
      'read': true,
      'created_at': '2026-10-15T12:00:00Z',
      ...more,
    };

http.Response _inbox() => http.Response(
  jsonEncode(<String, Object?>{
    'schema_version': 2,
    'recipient_id': 'u1',
    'unread_count': 0,
    'notifications': <Object?>[
      _row('scored', 'fixture_scored', <String, Object?>{'fixture_id': 'f1'}),
      _row('joined', 'group_member_joined', <String, Object?>{
        'group_id': 'g1',
        'actor_user_id': 'u2',
      }),
      _row('news', 'admin_announcement', <String, Object?>{
        'announcement_id': 'a1',
        'title': 'تنبيه',
        'body': 'نص',
      }),
    ],
  }),
  200,
  headers: const {'content-type': 'application/json'},
);

GestureTapCallback? _onTap(WidgetTester tester, String id) =>
    tester.widget<ListTile>(find.byKey(Key('notifications.item.$id'))).onTap;

void main() {
  testWidgets('a scored match and a new member lead somewhere; an '
      'announcement does not', (tester) async {
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

    expect(_onTap(tester, 'scored'), isNotNull);
    expect(_onTap(tester, 'joined'), isNotNull);
    expect(_onTap(tester, 'news'), isNull);
  });
}
