/// Script 206 (2026-11-03): the register form asks for the real first name
/// and the real family name in two fields, says the name must be the one
/// people know the player by, and sends them joined as one name. Through
/// the real [SessionGate] and `AuthApi` over the auth harness's fake server.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/auth/session_gate.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

Future<List<Map<String, Object?>>> _openRegister(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final List<Map<String, Object?>> registers = <Map<String, Object?>>[];
  final harness = buildAuthHarness((http.Request request) async {
    if (request.url.path == '/auth/register') {
      registers.add(jsonDecode(request.body) as Map<String, Object?>);
      return errorEnvelope(
        400,
        'auth.confirmation_required',
        'أرسلنا رابط تأكيد إلى بريدك. افتحه، ثم ارجع وسجّل الدخول.',
      );
    }
    return okMe(sampleUser);
  });
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const SessionGate(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('signIn.tabRegister')));
  await tester.pumpAndSettle();
  return registers;
}

Future<void> _fill(
  WidgetTester tester, {
  required String first,
  required String family,
}) async {
  await tester.enterText(find.byKey(const Key('signIn.nameField')), first);
  await tester.enterText(
    find.byKey(const Key('signIn.familyNameField')),
    family,
  );
  await tester.enterText(
    find.byKey(const Key('signIn.emailField')),
    'k@example.com',
  );
  await tester.enterText(
    find.byKey(const Key('signIn.passwordField')),
    'secret-123',
  );
  await tester.enterText(
    find.byKey(const Key('signIn.confirmPasswordField')),
    'secret-123',
  );
  await tester.ensureVisible(find.byKey(const Key('consent.box')));
  await tester.tap(find.byKey(const Key('consent.box')));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('signIn.submit')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('signIn.submit')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the form asks for the real first and family names', (
    tester,
  ) async {
    await _openRegister(tester);

    expect(find.text('إنشاء حساب في نُخبة'), findsOneWidget);
    expect(find.text('الاسم الأول الحقيقي'), findsOneWidget);
    expect(find.text('اسم العائلة الحقيقي'), findsOneWidget);
    expect(
      find.text('يجب إدخال الاسم الذي يعرفك به الآخرون في حياتك.'),
      findsOneWidget,
    );
  });

  testWidgets('the two names are sent joined as one', (tester) async {
    final registers = await _openRegister(tester);

    await _fill(tester, first: ' محمد ', family: ' العماري ');

    expect(registers, hasLength(1));
    expect(registers.single['display_name'], 'محمد العماري');
  });

  testWidgets('an empty family name is refused before any request', (
    tester,
  ) async {
    final registers = await _openRegister(tester);

    await _fill(tester, first: 'محمد', family: '');

    expect(registers, isEmpty);
    expect(find.text('اكتب اسم عائلتك أو اسم أبيك.'), findsOneWidget);
  });
}
