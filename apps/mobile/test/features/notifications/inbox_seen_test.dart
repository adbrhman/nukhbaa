/// The bell's count through the real inbox screen, the real
/// `NotificationsApi` and the real shell, with only the socket faked: opening
/// the inbox marks everything read once and the bell drops to zero, while
/// the open list keeps showing which rows were new; an inbox with nothing
/// unread marks nothing; and the app coming back to the foreground reads the
/// count again, so a notification that arrived meanwhile shows at once.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/session/session_scope.dart';
import 'package:mobile/features/auth/session_gate.dart';
import 'package:mobile/features/notifications/notifications_providers.dart';
import 'package:mobile/features/notifications/notifications_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

/// An inbox of one announcement, unread or not, that counts the requests
/// reaching it.
final class _Inbox {
  _Inbox({required this.unread});

  bool unread;
  int markAllCalls = 0;
  int countCalls = 0;

  Future<http.Response> handle(http.Request request) async {
    final String path = request.url.path;
    if (path == '/notifications/read_all' && request.method == 'POST') {
      markAllCalls++;
      final int marked = unread ? 1 : 0;
      unread = false;
      return _json(<String, Object?>{'marked': marked});
    }
    if (path == '/notifications/unread_count') {
      countCalls++;
      return _json(<String, Object?>{'unread_count': unread ? 1 : 0});
    }
    if (path == '/notifications') {
      return _json(<String, Object?>{
        'schema_version': 2,
        'recipient_id': 'u-1',
        'unread_count': unread ? 1 : 0,
        'notifications': <Object?>[
          <String, Object?>{
            'schema_version': 2,
            'id': 'n1',
            'recipient_id': 'u-1',
            'kind': 'admin_announcement',
            'read': !unread,
            'created_at': '2026-10-06T12:00:00Z',
            'announcement_id': 'a1',
            'title': 'Alert',
            'body': 'Body',
          },
        ],
      });
    }
    return okMe(sampleUser);
  }
}

/// The inbox under a bell that shows the count the app holds.
Future<void> _pumpInbox(WidgetTester tester, _Inbox inbox) async {
  final harness = buildAuthHarness(inbox.handle, seedToken: 'jwt');
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
        home: Column(
          children: <Widget>[
            Consumer(
              builder: (BuildContext context, WidgetRef ref, Widget? _) => Text(
                'bell ${ref.watch(unreadCountProvider).value}',
                textDirection: TextDirection.ltr,
              ),
            ),
            const Expanded(child: NotificationsScreen()),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opening the inbox clears the bell and keeps the new row bold', (
    tester,
  ) async {
    final _Inbox inbox = _Inbox(unread: true);

    await _pumpInbox(tester, inbox);

    expect(inbox.markAllCalls, 1);
    expect(find.text('bell 0'), findsOneWidget);
    // The list was not read again: the row still says it is new.
    expect(find.byKey(const Key('notifications.markRead.n1')), findsOneWidget);
  });

  testWidgets('an inbox with nothing unread marks nothing', (tester) async {
    final _Inbox inbox = _Inbox(unread: false);

    await _pumpInbox(tester, inbox);

    expect(inbox.markAllCalls, 0);
    expect(find.text('bell 0'), findsOneWidget);
  });

  testWidgets('coming back to the app reads the bell count again', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final _Inbox inbox = _Inbox(unread: false);
    final harness = buildAuthHarness(inbox.handle, seedToken: 'saved-jwt');
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      SessionScope(
        overrides: harness.overrides,
        child: MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const SessionGate(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final int before = inbox.countCalls;
    expect(before, greaterThan(0));

    inbox.unread = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(inbox.countCalls, before + 1);
  });
}
