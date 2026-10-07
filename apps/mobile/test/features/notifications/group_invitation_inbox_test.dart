/// An invitation to a friends' league through the real inbox, the real
/// `GroupsApi` and a fake server: the row says who invited to which league;
/// accepting joins (the server is asked, the answer shows), declining says
/// no, and an answered invitation shows its answer without the buttons.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/notifications/notifications_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

/// One `group_invited` notification about league g-1 and its invitation,
/// [status] until answered.
final class _Server {
  _Server(this.status);

  String status;
  final List<String> answers = <String>[];

  Future<http.Response> handle(http.Request request) async {
    final String path = request.url.path;
    if (path == '/notifications') {
      return _json(<String, Object?>{
        'schema_version': 2,
        'recipient_id': 'u-1',
        'unread_count': 0,
        'notifications': <Object?>[
          <String, Object?>{
            'schema_version': 2,
            'id': 'n1',
            'recipient_id': 'u-1',
            'kind': 'group_invited',
            'read': true,
            'created_at': '2026-10-07T12:00:00Z',
            'group_id': 'g-1',
            'actor_user_id': 'u-2',
          },
        ],
      });
    }
    if (path == '/groups/invitations') {
      return _json(<String, Object?>{
        'schema_version': 1,
        'invitations': <Object?>[
          <String, Object?>{
            'id': 'i-1',
            'group_id': 'g-1',
            'group_name': 'Office',
            'inviter_name': 'Sara',
            'status': status,
            'created_at': '2026-10-07T12:00:00.000Z',
          },
        ],
      });
    }
    if (path == '/groups/invitations/i-1/accept' && request.method == 'POST') {
      answers.add('accept');
      status = 'accepted';
      return _json(const <String, Object?>{'status': 'accepted'});
    }
    if (path == '/groups/invitations/i-1/decline' && request.method == 'POST') {
      answers.add('decline');
      status = 'declined';
      return _json(const <String, Object?>{'status': 'declined'});
    }
    return http.Response('not found', 404);
  }
}

Future<void> _pump(WidgetTester tester, _Server server) async {
  final harness = buildAuthHarness(server.handle, seedToken: 'jwt');
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
}

void main() {
  testWidgets('the row names who invited, and accepting joins', (tester) async {
    final _Server server = _Server('pending');
    await _pump(tester, server);

    final String text = tester
        .widget<Text>(find.byKey(const Key('groupInvite.text.i-1')))
        .data!;
    expect(text, contains('Sara'));
    expect(text, contains('Office'));

    await tester.tap(find.byKey(const Key('groupInvite.accept.i-1')));
    await tester.pumpAndSettle();

    expect(server.answers, <String>['accept']);
    expect(find.byKey(const Key('groupInvite.accept.i-1')), findsNothing);
    expect(find.byKey(const Key('groupInvite.answer.i-1')), findsOneWidget);
  });

  testWidgets('declining says no', (tester) async {
    final _Server server = _Server('pending');
    await _pump(tester, server);

    await tester.tap(find.byKey(const Key('groupInvite.decline.i-1')));
    await tester.pumpAndSettle();

    expect(server.answers, <String>['decline']);
    expect(
      tester.widget<Text>(find.byKey(const Key('groupInvite.answer.i-1'))).data,
      'رفضت الدعوة.',
    );
  });

  testWidgets('an answered invitation shows its answer, no buttons', (
    tester,
  ) async {
    await _pump(tester, _Server('accepted'));

    expect(find.byKey(const Key('groupInvite.accept.i-1')), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('groupInvite.answer.i-1'))).data,
      'انضممت إلى الدوري.',
    );
  });
}
