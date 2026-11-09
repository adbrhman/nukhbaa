/// Script 224: nobody creates an account, or chooses a public name, without
/// ticking the rules / privacy / 18+ consent, and the privacy policy opens.
/// Through the real [SessionGate] over the auth harness's fake server.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/auth/consent_box.dart';
import 'package:mobile/features/auth/rules_screen.dart';
import 'package:mobile/features/auth/session_gate.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

Future<void> _pump(
  WidgetTester tester,
  AuthHarness harness, {
  List<Uri>? opened,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...harness.overrides,
        if (opened != null)
          legalLinkOpenerProvider.overrideWithValue((Uri uri) async {
            opened.add(uri);
          }),
      ],
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const SessionGate(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AuthenticatedUserDto _automaticName() => AuthenticatedUserDto(
  userId: 'u-1',
  role: 'user',
  status: 'active',
  email: 'n72914939@gmail.com',
  displayName: 'n72914939',
);

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> _fillRegister(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('signIn.nameField')), 'Khaled');
  await tester.enterText(
    find.byKey(const Key('signIn.familyNameField')),
    'Saleh',
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
}

void main() {
  testWidgets('registering without the consent sends nothing and says why', (
    tester,
  ) async {
    int registers = 0;
    final AuthHarness harness = buildAuthHarness((http.Request request) async {
      if (request.url.path == '/auth/register') registers++;
      return okMe(sampleUser);
    });
    addTearDown(harness.dispose);
    await _pump(tester, harness);
    await tester.tap(find.byKey(const Key('signIn.tabRegister')));
    await tester.pumpAndSettle();
    await _fillRegister(tester);

    await _tap(tester, 'signIn.submit');

    expect(registers, 0);
    expect(find.byKey(const Key('consent.error')), findsOneWidget);
    expect(find.text(consentRequiredMessage), findsOneWidget);
  });

  testWidgets('ticking the consent lets the registration through', (
    tester,
  ) async {
    final List<Map<String, Object?>> registers = <Map<String, Object?>>[];
    final AuthHarness harness = buildAuthHarness((http.Request request) async {
      if (request.url.path == '/auth/register') {
        registers.add(jsonDecode(request.body) as Map<String, Object?>);
        return errorEnvelope(400, 'auth.confirmation_required', 'x');
      }
      return okMe(sampleUser);
    });
    addTearDown(harness.dispose);
    await _pump(tester, harness);
    await tester.tap(find.byKey(const Key('signIn.tabRegister')));
    await tester.pumpAndSettle();
    await _fillRegister(tester);
    await _tap(tester, 'consent.box');
    expect(find.byKey(const Key('consent.error')), findsNothing);

    await _tap(tester, 'signIn.submit');

    expect(registers, hasLength(1));
  });

  testWidgets('the sign-in tab has no consent box', (tester) async {
    final AuthHarness harness = buildAuthHarness(
      (http.Request request) async => okMe(sampleUser),
    );
    addTearDown(harness.dispose);
    await _pump(tester, harness);

    expect(find.byKey(const Key('consent.box')), findsNothing);
  });

  testWidgets(
    'the consent is asked again when the tab is left and re-entered',
    (tester) async {
      final AuthHarness harness = buildAuthHarness(
        (http.Request request) async => okMe(sampleUser),
      );
      addTearDown(harness.dispose);
      await _pump(tester, harness);
      await tester.tap(find.byKey(const Key('signIn.tabRegister')));
      await tester.pumpAndSettle();
      await _tap(tester, 'consent.box');
      await _tap(tester, 'signIn.tabLogin');
      await _tap(tester, 'signIn.tabRegister');
      await _fillRegister(tester);

      await _tap(tester, 'signIn.submit');

      expect(find.byKey(const Key('consent.error')), findsOneWidget);
    },
  );

  testWidgets(
    'the privacy link opens the policy page, the rules link the rules',
    (tester) async {
      final List<Uri> opened = <Uri>[];
      final AuthHarness harness = buildAuthHarness(
        (http.Request request) async => okMe(sampleUser),
      );
      addTearDown(harness.dispose);
      await _pump(tester, harness, opened: opened);
      await tester.tap(find.byKey(const Key('signIn.tabRegister')));
      await tester.pumpAndSettle();

      await _tap(tester, 'consent.privacy');
      expect(opened, <Uri>[Uri.parse(privacyPolicyUrl)]);
      expect(privacyPolicyUrl, 'https://nukhbaa.app/privacy/');

      await _tap(tester, 'consent.rules');
      expect(find.byType(RulesScreen), findsOneWidget);
    },
  );

  testWidgets('a Google account without a name cannot save it unticked', (
    tester,
  ) async {
    final List<String> puts = <String>[];
    final AuthHarness harness = buildAuthHarness((http.Request request) async {
      if (request.url.path == '/me/display-name' && request.method == 'PUT') {
        puts.add(request.body);
      }
      return okMe(_automaticName());
    }, seedToken: 'saved-jwt');
    addTearDown(harness.dispose);
    await _pump(tester, harness);
    await tester.enterText(find.byKey(const Key('nameSetup.field')), 'Ali');
    await tester.enterText(
      find.byKey(const Key('nameSetup.familyField')),
      'Hassan',
    );

    await _tap(tester, 'nameSetup.save');

    expect(puts, isEmpty);
    expect(find.byKey(const Key('consent.error')), findsOneWidget);
    expect(find.byKey(const Key('nameSetup.screen')), findsOneWidget);
  });
}
