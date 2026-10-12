/// The in-app password reset by e-mailed code (batch 110): e-mail, code,
/// new password, without leaving the app.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/auth/password_reset_screen.dart';
import 'package:mobile/features/auth/password_reset_texts.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

http.Response _json(Map<String, Object?> body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

Future<http.Response> _server(http.Request request) async {
  switch (request.url.path) {
    case '/auth/password-reset/request':
      return _json({'success': true});
    case '/auth/password-reset/verify':
      final Map<String, dynamic> body =
          jsonDecode(request.body) as Map<String, dynamic>;
      if (body['code'] == '123456') {
        return _json({'recovery_token': 'recovery-token'});
      }
      return errorEnvelope(
        400,
        'auth.recovery_code_invalid',
        'الرمز غير صحيح أو انتهت صلاحيته. اطلب رمزًا جديدًا.',
      );
    case '/auth/password-reset/update':
      return _json({'success': true});
  }
  return http.Response('not found', 404);
}

List<http.Request> _calls(AuthHarness harness, String path) => harness.captured
    .map((captured) => captured.request)
    .where((request) => request.url.path == path)
    .toList();

Future<AuthHarness> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final harness = buildAuthHarness(_server);
  addTearDown(harness.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        home: const PasswordResetScreen(),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

Future<void> _askForCode(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('passwordReset.emailField')),
    ' player@example.com ',
  );
  await tester.tap(find.byKey(const Key('passwordReset.submit')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the e-mailed code leads to a new password inside the app', (
    tester,
  ) async {
    final harness = await _open(tester);
    expect(find.text(resetCodeSendLabel), findsOneWidget);

    await _askForCode(tester);

    expect(_calls(harness, '/auth/password-reset/request'), hasLength(1));
    expect(find.byKey(const Key('passwordReset.codeField')), findsOneWidget);
    expect(
      find.text(resetCodeSentMessage('player@example.com')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('passwordReset.codeField')),
      '12 34-56',
    );
    await tester.tap(find.byKey(const Key('passwordReset.verify')));
    await tester.pumpAndSettle();

    final verify = _calls(harness, '/auth/password-reset/verify');
    expect(verify, hasLength(1));
    expect(jsonDecode(verify.single.body), {
      'email': 'player@example.com',
      'code': '123456',
    });

    await tester.enterText(
      find.byKey(const Key('passwordReset.passwordField')),
      'new-password-1',
    );
    await tester.enterText(
      find.byKey(const Key('passwordReset.confirmField')),
      'new-password-1',
    );
    await tester.tap(find.byKey(const Key('passwordReset.submit')));
    await tester.pumpAndSettle();

    final update = _calls(harness, '/auth/password-reset/update');
    expect(update, hasLength(1));
    expect(update.single.headers['authorization'], 'Bearer recovery-token');
    expect(jsonDecode(update.single.body), {'password': 'new-password-1'});
  });

  testWidgets('a wrong code says so and keeps the code step', (tester) async {
    final harness = await _open(tester);
    await _askForCode(tester);

    await tester.enterText(
      find.byKey(const Key('passwordReset.codeField')),
      '654321',
    );
    await tester.tap(find.byKey(const Key('passwordReset.verify')));
    await tester.pumpAndSettle();

    expect(_calls(harness, '/auth/password-reset/verify'), hasLength(1));
    expect(find.textContaining('الرمز غير صحيح'), findsOneWidget);
    expect(find.byKey(const Key('passwordReset.codeField')), findsOneWidget);
    expect(find.byKey(const Key('passwordReset.passwordField')), findsNothing);
  });

  testWidgets('a short code is refused before asking the server', (
    tester,
  ) async {
    final harness = await _open(tester);
    await _askForCode(tester);

    await tester.enterText(
      find.byKey(const Key('passwordReset.codeField')),
      '123',
    );
    await tester.tap(find.byKey(const Key('passwordReset.verify')));
    await tester.pumpAndSettle();

    expect(find.text(resetCodeFormatError), findsOneWidget);
    expect(_calls(harness, '/auth/password-reset/verify'), isEmpty);
  });

  testWidgets('a new code can be asked for after a minute', (tester) async {
    final harness = await _open(tester);
    await _askForCode(tester);

    expect(find.text(resetCodeResendWaitLabel), findsOneWidget);
    await tester.tap(find.byKey(const Key('passwordReset.resend')));
    await tester.pumpAndSettle();
    expect(_calls(harness, '/auth/password-reset/request'), hasLength(1));

    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();
    expect(find.text(resetCodeResendLabel), findsOneWidget);

    await tester.tap(find.byKey(const Key('passwordReset.resend')));
    await tester.pumpAndSettle();

    expect(_calls(harness, '/auth/password-reset/request'), hasLength(2));
    expect(find.text(resetCodeResentMessage), findsOneWidget);
    expect(find.text(resetCodeResendWaitLabel), findsOneWidget);
  });

  testWidgets('the e-mail can be changed from the code step', (tester) async {
    await _open(tester);
    await _askForCode(tester);

    await tester.tap(find.byKey(const Key('passwordReset.changeEmail')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('passwordReset.codeField')), findsNothing);
    expect(find.byKey(const Key('passwordReset.emailField')), findsOneWidget);
    expect(find.text(resetCodeRequestSubtitle), findsOneWidget);
  });
}
