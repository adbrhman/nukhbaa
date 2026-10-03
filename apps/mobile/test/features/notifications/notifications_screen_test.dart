/// Widget tests for [NotificationsScreen] over the real [NotificationsApi] and
/// the real [ApiTransport], with only the socket faked ([buildAuthHarness]'s
/// `MockClient`). An announcement whose body carries an https address must
/// show it as a link that opens exactly that address when tapped; text with
/// no such address, or with a plain http one, must open nothing -- so a screen
/// that stopped linking, linked the wrong span, or opened an unsafe address
/// fails here.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/notifications/notifications_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

const String _inboxPath = '/notifications';
const String _link = 'https://links.nukhbaa.app/';
const Key _bodyKey = Key('notifications.body.n1');

http.Response _inbox(String body) => http.Response(
  jsonEncode(<String, Object?>{
    'schema_version': 2,
    'recipient_id': 'u1',
    'unread_count': 1,
    'notifications': <Object?>[
      <String, Object?>{
        'schema_version': 2,
        'id': 'n1',
        'recipient_id': 'u1',
        'kind': 'admin_announcement',
        'read': false,
        'created_at': '2026-10-03T19:51:00Z',
        'announcement_id': 'a1',
        'title': 'Alert',
        'body': body,
      },
    ],
  }),
  200,
  headers: const {'content-type': 'application/json'},
);

/// Shows the inbox with one announcement carrying [body]; the returned list
/// collects every address the screen hands to the system.
Future<List<Uri>> _pumpInbox(WidgetTester tester, String body) async {
  final List<Uri> opened = <Uri>[];
  final harness = buildAuthHarness((request) async {
    if (request.url.path == _inboxPath) return _inbox(body);
    return http.Response('not found', 404);
  }, seedToken: 'jwt');
  addTearDown(harness.dispose);
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...harness.overrides,
        notificationLinkOpenerProvider.overrideWithValue((Uri uri) async {
          opened.add(uri);
          return true;
        }),
      ],
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
  return opened;
}

void main() {
  testWidgets('tapping the channel link opens exactly that address', (
    tester,
  ) async {
    final List<Uri> opened = await _pumpInbox(
      tester,
      '\u062a\u0627\u0628\u0639 \u0642\u0646\u0627\u0629 \u0646\u062e\u0628\u0629:\n$_link\n\u0644\u0627 \u062a\u0646\u062a\u0638\u0631.',
    );

    await tester.tapOnText(find.textRange.ofSubstring(_link));

    expect(opened, <Uri>[Uri.parse(_link)]);
  });

  testWidgets('a full stop after the address is not part of the link', (
    tester,
  ) async {
    final List<Uri> opened = await _pumpInbox(
      tester,
      '\u0627\u0644\u0631\u0627\u0628\u0637: $_link.',
    );

    await tester.tapOnText(find.textRange.ofSubstring(_link));

    expect(opened, <Uri>[Uri.parse(_link)]);
  });

  testWidgets('an Arabic comma right after the address ends the link', (
    tester,
  ) async {
    final List<Uri> opened = await _pumpInbox(
      tester,
      '\u0627\u0644\u0631\u0627\u0628\u0637 $_link\u060c \u0634\u0643\u0631\u0627',
    );

    await tester.tapOnText(find.textRange.ofSubstring(_link));

    expect(opened, <Uri>[Uri.parse(_link)]);
  });

  testWidgets('a body with no address opens nothing when tapped', (
    tester,
  ) async {
    final List<Uri> opened = await _pumpInbox(
      tester,
      '\u0645\u0628\u0627\u0631\u0627\u0629 \u0628\u0644\u0627 \u0631\u0627\u0628\u0637',
    );

    await tester.tap(find.byKey(_bodyKey));

    expect(opened, isEmpty);
  });

  testWidgets('a plain http address is shown but never opened', (tester) async {
    final List<Uri> opened = await _pumpInbox(
      tester,
      '\u0627\u0641\u062a\u062d http://example.com/x \u0627\u0644\u0622\u0646',
    );

    await tester.tap(find.byKey(_bodyKey));

    expect(opened, isEmpty);
  });
}
