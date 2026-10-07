/// The notifications bell through the real shell, the real home header, the
/// real inbox and the real `NotificationsApi`, with only the socket faked:
/// while anything is unread the bell blinks; opening the inbox reads
/// everything and the bell is still; a new notification makes it blink
/// again once the count is read.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/session/session_scope.dart';
import 'package:mobile/core/ui/unread_badge.dart';
import 'package:mobile/features/auth/session_gate.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

/// An inbox of one announcement, unread until the inbox is opened.
final class _Inbox {
  bool unread = true;

  Future<http.Response> handle(http.Request request) async {
    final String path = request.url.path;
    if (path == '/notifications/read_all' && request.method == 'POST') {
      final int marked = unread ? 1 : 0;
      unread = false;
      return _json(<String, Object?>{'marked': marked});
    }
    if (path == '/notifications/unread_count') {
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
            'created_at': '2026-10-07T12:00:00Z',
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

final Finder _bell = find.descendant(
  of: find.byKey(const Key('home.notifications')),
  matching: find.byKey(const Key('unreadBadge.bell')),
);

double _opacity(WidgetTester tester) =>
    tester.widget<AnimatedOpacity>(_bell).opacity;

/// The bell's opacity over two blink periods.
Future<Set<double>> _watch(WidgetTester tester) async {
  final Set<double> seen = <double>{_opacity(tester)};
  for (var i = 0; i < 4; i++) {
    await tester.pump(UnreadBadge.blinkPeriod ~/ 2);
    seen.add(_opacity(tester));
  }
  return seen;
}

void main() {
  testWidgets('the bell blinks until the inbox is opened, then again', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final _Inbox inbox = _Inbox();
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

    expect(await _watch(tester), contains(UnreadBadge.dimOpacity));

    await tester.tap(find.byKey(const Key('home.notifications')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(await _watch(tester), <double>{1});

    // A new notification; the count is read again on the next return.
    inbox.unread = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(await _watch(tester), contains(UnreadBadge.dimOpacity));
  });
}
