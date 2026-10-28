/// The account tab's way to the developer (2026-10-27), through the real
/// [AccountScreen] over the real [ApiTransport]: a support group after the
/// app's settings whose row opens the private chat with Nukhbaa support
/// (script 166) -- no WhatsApp, no e-mail, no phone number -- with the
/// count of support's unread answers.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/auth/account_screen.dart';
import 'package:mobile/features/support/support_chat_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

const AuthenticatedUserDto _player = AuthenticatedUserDto(
  userId: 'u-1',
  role: 'user',
  status: 'active',
  email: 'a@example.com',
  displayName: 'سامي',
);

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

Future<List<String>> _pump(
  WidgetTester tester, {
  int unread = 0,
  double textScale = 1,
  Size size = const Size(1080, 4000),
}) async {
  final List<String> calls = <String>[];
  int count = unread;
  final AuthHarness harness = buildAuthHarness((http.Request request) async {
    calls.add('${request.method} ${request.url.path}');
    return switch (request.url.path) {
      '/me/support/unread' => _json({'count': count}),
      '/me/support/read' => () {
        final int marked = count;
        count = 0;
        return _json({'count': marked});
      }(),
      '/me/support/messages' => _json({
        'status': 'open',
        'unread': count,
        'has_more': false,
        'messages': [
          if (unread > 0)
            {
              'id': 1,
              'sender': 'support',
              'body': 'تم الإصلاح',
              'created_at': '2026-10-28T10:00:00.000Z',
            },
        ],
      }),
      _ => http.Response('not found', 404),
    };
  }, seedToken: 'jwt');
  addTearDown(harness.dispose);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const AccountScreen(user: _player),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return calls;
}

const Key _row = Key('account.contactDeveloper');
const Key _badge = Key('account.contactDeveloper.badge');

void main() {
  testWidgets('the support row sits after the app settings, in the app', (
    tester,
  ) async {
    await _pump(tester);

    expect(
      find.descendant(
        of: find.byKey(const Key('account.group.support')),
        matching: find.byKey(_row),
      ),
      findsOneWidget,
    );
    expect(find.text('الدعم'), findsOneWidget);
    expect(find.text('تواصل مع المطوّر'), findsOneWidget);
    expect(
      find.text('للإبلاغ عن مشكلة أو تقديم شكوى داخل التطبيق'),
      findsOneWidget,
    );
    // No WhatsApp, no e-mail, no phone number on the account tab.
    expect(find.textContaining('واتساب'), findsNothing);
    expect(find.textContaining('@gmail.com'), findsNothing);
    expect(find.byKey(_badge), findsNothing);
    final double app = tester
        .getTopLeft(find.byKey(const Key('account.group.app')))
        .dy;
    final double support = tester
        .getTopLeft(find.byKey(const Key('account.group.support')))
        .dy;
    final double signOut = tester
        .getTopLeft(find.byKey(const Key('account.signOut')))
        .dy;
    expect(app, lessThan(support));
    expect(support, lessThan(signOut));
  });

  testWidgets('support answers unread show on the row; opening the chat '
      'reads them and clears the count', (tester) async {
    final List<String> calls = await _pump(tester, unread: 2);

    expect(
      find.descendant(of: find.byKey(_badge), matching: find.text('2')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(_row));
    await tester.pumpAndSettle();

    expect(find.byType(SupportChatScreen), findsOneWidget);
    expect(find.text('تم الإصلاح'), findsOneWidget);
    expect(calls, contains('POST /me/support/read'));

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byKey(_badge), findsNothing);
  });

  testWidgets('the row holds at text x2 on a 360px phone', (tester) async {
    await _pump(tester, unread: 12, textScale: 2, size: const Size(360, 4000));

    expect(find.byKey(_row), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(_badge), matching: find.text('9+')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
