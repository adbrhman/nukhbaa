/// Widget tests for the Auth UI wired through the real [SessionGate] +
/// [SignInScreen] + [AccountScreen], over the [buildAuthHarness] fakes.
///
/// Covers the user-visible outcomes of the four §4 scenarios: a saved session
/// restores straight to the account screen; a signed-out user sees the sign-in
/// form, signs in successfully and lands on the account screen; bad credentials
/// keep them on the form with an error banner; and a lost connection shows the
/// (retryable) transient message.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/session_gate.dart';

import '../../support/auth_harness.dart';

Widget _appUnder(AuthHarness harness) => ProviderScope(
  overrides: harness.overrides,
  child: const MaterialApp(home: SessionGate()),
);

void main() {
  testWidgets('restored valid session lands on the account screen', (
    tester,
  ) async {
    final harness = buildAuthHarness(
      (_) async => okMe(sampleUser),
      seedToken: 'saved-jwt',
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(_appUnder(harness));
    // First frame: boot restore in flight -> splash.
    expect(find.byKey(const Key('session.splash')), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('account.title')), findsOneWidget);
    expect(find.byKey(const Key('account.userId')), findsOneWidget);
    expect(find.text('u-1'), findsOneWidget);
  });

  testWidgets(
    'no token -> sign-in form; successful sign-in -> account screen',
    (tester) async {
      final harness = buildAuthHarness((request) async {
        if (request.url.path == '/auth/login') {
          return okLoginResponse('fresh-jwt');
        }
        return okMe(sampleUser);
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(_appUnder(harness));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('signIn.title')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('signIn.emailField')),
        'a@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('signIn.passwordField')),
        'correct-password',
      );
      await tester.tap(find.byKey(const Key('signIn.submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('account.title')), findsOneWidget);
      expect(find.text('u-1'), findsOneWidget);
      expect(await harness.store.read(), 'fresh-jwt');
      expect(await harness.store.read(), 'fresh-jwt');
    },
  );

  testWidgets('bad credentials keep the form and show the error banner', (
    tester,
  ) async {
    final harness = buildAuthHarness(
      (_) async => errorEnvelope(
        401,
        'auth.invalid_credentials',
        'Incorrect email or password.',
      ),
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(_appUnder(harness));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('signIn.emailField')),
      'a@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('signIn.passwordField')),
      'wrong-password',
    );
    await tester.tap(find.byKey(const Key('signIn.submit')));
    await tester.tap(find.byKey(const Key('signIn.submit')));
    await tester.pumpAndSettle();

    // Still on the form, banner visible, no token persisted.
    expect(find.byKey(const Key('signIn.title')), findsOneWidget);
    expect(find.byKey(const Key('signIn.errorBanner')), findsOneWidget);
    // ErrorPresenter maps an authorization failure to the sign-in-again copy.
    expect(find.textContaining('session has expired'), findsOneWidget);
    expect(await harness.store.read(), isNull);
  });

  testWidgets('lost connection shows the transient (connection) message', (
    tester,
  ) async {
    final harness = buildAuthHarness(
      (_) async => throw Exception('socket reset'),
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(_appUnder(harness));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('signIn.emailField')),
      'a@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('signIn.passwordField')),
      'some-password',
    );
    await tester.tap(find.byKey(const Key('signIn.submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('signIn.errorBanner')), findsOneWidget);
    expect(find.textContaining('check your connection'), findsOneWidget);
  });

  testWidgets('sign-out from the account screen returns to the sign-in form', (
    tester,
  ) async {
    final harness = buildAuthHarness(
      (_) async => okMe(sampleUser),
      seedToken: 'saved-jwt',
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(_appUnder(harness));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('account.title')), findsOneWidget);

    await tester.tap(find.byKey(const Key('account.signOut')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('signIn.title')), findsOneWidget);
    expect(await harness.store.read(), isNull);
  });
}
