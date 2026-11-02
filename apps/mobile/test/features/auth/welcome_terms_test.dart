/// Script 203 (2026-11-02): a new account registers with a two-part name
/// and reads the terms and prizes before the app opens. Through the real
/// [SessionGate], [SignInScreen] and `AuthApi` over the auth harness's fake
/// server; a returning player goes straight in.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/auth/nukhbaa_shell.dart';
import 'package:mobile/features/auth/rules_screen.dart';
import 'package:mobile/features/auth/session_gate.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

const AuthenticatedUserDto _newPlayer = AuthenticatedUserDto(
  userId: 'u-new',
  role: 'user',
  status: 'active',
  email: 'k@example.com',
  displayName: 'Khaled Saleh',
);

void _phoneTest(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await body(tester);
  });
}

Future<void> _open(WidgetTester tester, AuthHarness harness) async {
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
}

Future<void> _register(WidgetTester tester, String name) async {
  await tester.enterText(find.byKey(const Key('signIn.nameField')), name);
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
  await tester.ensureVisible(find.byKey(const Key('signIn.submit')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('signIn.submit')));
  await tester.pumpAndSettle();
}

void main() {
  _phoneTest('a one-word name is refused, a two-part name registers and '
      'the terms come before the app', (tester) async {
    final List<http.Request> registers = <http.Request>[];
    final harness = buildAuthHarness((request) async {
      if (request.url.path == '/auth/register') {
        registers.add(request);
        return okLoginResponse('new-jwt');
      }
      return okMe(_newPlayer);
    });
    addTearDown(harness.dispose);

    await _open(tester, harness);
    await tester.tap(find.byKey(const Key('signIn.tabRegister')));
    await tester.pumpAndSettle();

    await _register(tester, 'Khaled');
    expect(registers, isEmpty);
    expect(
      find.textContaining(
        '\u0627\u0633\u0645\u0643 \u0627\u0644\u062b\u0646\u0627\u0626\u064a',
      ),
      findsWidgets,
    );

    await _register(tester, 'Khaled Saleh');
    expect(registers, hasLength(1));
    expect(registers.single.body, contains('Khaled Saleh'));

    expect(find.byType(RulesScreen), findsOneWidget);
    expect(find.byType(NukhbaaShell), findsNothing);
    expect(
      find.text(
        '\u0627\u0644\u0634\u0631\u0648\u0637 \u0648\u0627\u0644\u062c\u0648\u0627\u0626\u0632',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        '\u0644\u0644\u0645\u0646\u0627\u0641\u0633\u0629 \u0639\u0644\u0649 \u0627\u0644\u062c\u0648\u0627\u0626\u0632',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('rules.terms.name')), findsOneWidget);

    await tester.tap(find.byKey(const Key('rules.accept')));
    await tester.pumpAndSettle();

    expect(find.byType(RulesScreen), findsNothing);
    expect(find.byType(NukhbaaShell), findsOneWidget);
  });

  _phoneTest('a returning player goes straight in', (tester) async {
    final harness = buildAuthHarness(
      (_) async => okMe(_newPlayer),
      seedToken: 'saved-jwt',
    );
    addTearDown(harness.dispose);

    await _open(tester, harness);

    expect(find.byType(RulesScreen), findsNothing);
    expect(find.byType(NukhbaaShell), findsOneWidget);
  });

  _phoneTest('signing in to an existing account shows no terms', (
    tester,
  ) async {
    final harness = buildAuthHarness((request) async {
      if (request.url.path == '/auth/login') {
        return okLoginResponse('jwt');
      }
      return okMe(_newPlayer);
    });
    addTearDown(harness.dispose);

    await _open(tester, harness);
    await tester.enterText(
      find.byKey(const Key('signIn.emailField')),
      'k@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('signIn.passwordField')),
      'secret-123',
    );
    await tester.ensureVisible(find.byKey(const Key('signIn.submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('signIn.submit')));
    await tester.pumpAndSettle();

    expect(find.byType(RulesScreen), findsNothing);
    expect(find.byType(NukhbaaShell), findsOneWidget);
  });

  testWidgets('the terms page fits a 360px phone at text x2', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    int accepted = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: RulesScreen(onAccept: () => accepted++),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The last term is built, scrolled to: the list is read to its end.
    await tester.scrollUntilVisible(
      find.byKey(const Key('rules.terms.suspended')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('rules.accept')));
    expect(accepted, 1);
  });
}
