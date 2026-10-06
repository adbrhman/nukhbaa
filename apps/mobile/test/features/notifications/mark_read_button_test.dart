/// The row's mark-read button through the real inbox screen, the real
/// `NotificationsApi` and a fake server that answers the mark only when
/// told: by the time it answers nothing watches the auto-disposed
/// controller any more, and the mark must still read the inbox and the bell
/// again instead of failing on a closed controller.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/notifications/notifications_providers.dart';
import 'package:mobile/features/notifications/notifications_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

/// One announcement, unread until its mark is answered. Opening the inbox
/// marks all as seen but leaves the row unread here, so its button shows.
final class _Inbox {
  final Completer<void> answer = Completer<void>();
  bool read = false;
  int marks = 0;
  int countCalls = 0;

  Future<http.Response> handle(http.Request request) async {
    final String path = request.url.path;
    if (path == '/notifications/n1/read' && request.method == 'POST') {
      marks++;
      await answer.future;
      read = true;
      return _json(<String, Object?>{'read': true});
    }
    if (path == '/notifications/read_all' && request.method == 'POST') {
      return _json(<String, Object?>{'marked': 0});
    }
    if (path == '/notifications/unread_count') {
      countCalls++;
      return _json(<String, Object?>{'unread_count': read ? 0 : 1});
    }
    if (path == '/notifications') {
      return _json(<String, Object?>{
        'schema_version': 2,
        'recipient_id': 'u-1',
        'unread_count': read ? 0 : 1,
        'notifications': <Object?>[
          <String, Object?>{
            'schema_version': 2,
            'id': 'n1',
            'recipient_id': 'u-1',
            'kind': 'admin_announcement',
            'read': read,
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

void main() {
  testWidgets('the button marks the row read after the server answers', (
    tester,
  ) async {
    final _Inbox inbox = _Inbox();
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
                builder: (BuildContext context, WidgetRef ref, Widget? _) =>
                    Text(
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
    final Finder button = find.byKey(const Key('notifications.markRead.n1'));
    expect(button, findsOneWidget);
    final int countsBefore = inbox.countCalls;

    await tester.tap(button);
    // Frames pass while the server holds the answer: the controller has
    // no listener of its own by now.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(inbox.marks, 1);

    inbox.answer.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(button, findsNothing);
    expect(inbox.countCalls, greaterThan(countsBefore));
    expect(find.text('bell 0'), findsOneWidget);
  });
}
