/// Fingerprint unlock through the real [SessionGate]: a restored session
/// behind the lock opens after the fingerprint, the password stays one tap
/// away, and a password sign-in never meets the lock but is offered it once.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/biometric_unlock.dart';
import 'package:mobile/features/auth/nukhbaa_shell.dart';
import 'package:mobile/features/auth/session_gate.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

/// A fingerprint sensor the test answers by hand ([pending]) or at once
/// ([autoPass]).
final class _FakeAuthenticator implements BiometricAuthenticator {
  int prompts = 0;
  bool autoPass = false;
  Completer<bool>? pending;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> authenticate({required String reason}) {
    prompts++;
    if (autoPass) return Future<bool>.value(true);
    pending = Completer<bool>();
    return pending!.future;
  }
}

Widget _appUnder(AuthHarness harness) => ProviderScope(
  overrides: harness.overrides,
  child: MaterialApp(
    home: const SessionGate(),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
  ),
);

void _lockTest(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await body(tester);
  });
}

Future<void> _signInWithPassword(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('signIn.emailField')),
    'a@example.com',
  );
  await tester.enterText(
    find.byKey(const Key('signIn.passwordField')),
    'secret-123',
  );
  await tester.tap(find.byKey(const Key('signIn.submit')));
  await tester.pumpAndSettle();
}

void main() {
  _lockTest('a restored session behind the lock opens after the '
      'fingerprint', (tester) async {
    final fake = _FakeAuthenticator();
    final harness = buildAuthHarness(
      (_) async => okMe(sampleUser),
      seedToken: 'saved-jwt',
      biometricStore: InMemoryBiometricPreferenceStore(
        enabled: true,
        offered: true,
      ),
      biometricAuthenticator: fake,
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(_appUnder(harness));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('appLock.screen')), findsOneWidget);
    expect(fake.prompts, 1, reason: 'the prompt opens by itself');
    expect(find.byType(NukhbaaShell), findsNothing);

    fake.pending!.complete(true);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('appLock.screen')), findsNothing);
    expect(find.byType(NukhbaaShell), findsOneWidget);
  });

  _lockTest('a failed fingerprint keeps the lock, and the password is one '
      'tap away', (tester) async {
    final fake = _FakeAuthenticator();
    final harness = buildAuthHarness(
      (_) async => okMe(sampleUser),
      seedToken: 'saved-jwt',
      biometricStore: InMemoryBiometricPreferenceStore(
        enabled: true,
        offered: true,
      ),
      biometricAuthenticator: fake,
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(_appUnder(harness));
    await tester.pumpAndSettle();
    fake.pending!.complete(false);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('appLock.screen')), findsOneWidget);
    expect(find.byType(NukhbaaShell), findsNothing);

    await tester.tap(find.byKey(const Key('appLock.usePassword')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('signIn.title')), findsOneWidget);
    expect(await harness.store.read(), isNull);
  });

  _lockTest('a password sign-in never meets the lock and is offered '
      'fingerprint unlock once', (tester) async {
    final fake = _FakeAuthenticator()..autoPass = true;
    final store = InMemoryBiometricPreferenceStore();
    final harness = buildAuthHarness(
      (request) async => request.url.path == '/auth/login'
          ? okLoginResponse('fresh-jwt')
          : okMe(sampleUser),
      biometricStore: store,
      biometricAuthenticator: fake,
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(_appUnder(harness));
    await tester.pumpAndSettle();
    await _signInWithPassword(tester);

    expect(find.byKey(const Key('appLock.screen')), findsNothing);
    expect(find.byKey(const Key('appLock.offer')), findsOneWidget);

    await tester.tap(find.byKey(const Key('appLock.offer.enable')));
    await tester.pumpAndSettle();

    expect(await store.isEnabled(), isTrue);
    expect(await store.wasOffered(), isTrue);
    expect(find.byType(NukhbaaShell), findsOneWidget);
    expect(find.byKey(const Key('appLock.screen')), findsNothing);
  });

  _lockTest('with unlock already on, a password sign-in goes straight in', (
    tester,
  ) async {
    final fake = _FakeAuthenticator();
    final harness = buildAuthHarness(
      (request) async => request.url.path == '/auth/login'
          ? okLoginResponse('fresh-jwt')
          : okMe(sampleUser),
      biometricStore: InMemoryBiometricPreferenceStore(
        enabled: true,
        offered: true,
      ),
      biometricAuthenticator: fake,
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(_appUnder(harness));
    await tester.pumpAndSettle();
    await _signInWithPassword(tester);

    expect(fake.prompts, 0);
    expect(find.byKey(const Key('appLock.offer')), findsNothing);
    expect(find.byType(NukhbaaShell), findsOneWidget);
  });
}
