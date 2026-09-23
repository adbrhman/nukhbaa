/// Fingerprint sign-in after a sign-out: with fingerprint unlock on, the
/// refresh token outlives the sign-out in its own slot, and the sign-in
/// screen trades it back for a session after the fingerprint.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/auth/biometric_unlock.dart';
import 'package:mobile/features/auth/nukhbaa_shell.dart';
import 'package:mobile/features/auth/session_controller.dart';
import 'package:mobile/features/auth/session_gate.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

const Map<String, String> _json = {'content-type': 'application/json'};

final class _PassingSensor implements BiometricAuthenticator {
  int prompts = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> authenticate({required String reason}) async {
    prompts++;
    return true;
  }
}

http.Response _session(String access, String refresh) => http.Response(
  jsonEncode(
    AuthResponseDto(
      accessToken: access,
      refreshToken: refresh,
      userId: null,
      email: null,
    ).toJson(),
  ),
  200,
  headers: _json,
);

void _screenTest(
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

Future<void> _open(WidgetTester tester, AuthHarness harness) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        home: const SessionGate(),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('with fingerprint unlock on, signing out keeps the refresh token for '
      'the fingerprint', () async {
    final prefs = InMemoryBiometricPreferenceStore(
      enabled: true,
      offered: true,
    );
    final harness = buildAuthHarness(
      (request) async => request.url.path == '/auth/login'
          ? _session('a1', 'r9')
          : okMe(sampleUser),
      biometricStore: prefs,
    );
    addTearDown(harness.dispose);
    await harness.container.read(sessionControllerProvider.future);
    final controller = harness.container.read(
      sessionControllerProvider.notifier,
    );
    await controller.signInWithCredentials(
      email: 'a@example.com',
      password: 'secret-123',
    );

    await controller.signOut();

    expect(await prefs.readSavedRefreshToken(), 'r9');
    expect(await harness.store.read(), isNull);
    expect(await harness.store.readRefreshToken(), isNull);
  });

  test('with fingerprint unlock off, signing out keeps nothing', () async {
    final prefs = InMemoryBiometricPreferenceStore();
    final harness = buildAuthHarness(
      (request) async => request.url.path == '/auth/login'
          ? _session('a1', 'r9')
          : okMe(sampleUser),
      biometricStore: prefs,
    );
    addTearDown(harness.dispose);
    await harness.container.read(sessionControllerProvider.future);
    final controller = harness.container.read(
      sessionControllerProvider.notifier,
    );
    await controller.signInWithCredentials(
      email: 'a@example.com',
      password: 'secret-123',
    );

    await controller.signOut();

    expect(await prefs.readSavedRefreshToken(), isNull);
  });

  _screenTest('the sign-in screen signs back in with the fingerprint', (
    tester,
  ) async {
    final prefs = InMemoryBiometricPreferenceStore(
      enabled: true,
      offered: true,
    );
    await prefs.saveRefreshToken('r1');
    final sensor = _PassingSensor();
    final refreshBodies = <Object?>[];
    final harness = buildAuthHarness(
      (request) async {
        if (request.url.path == '/auth/refresh') {
          refreshBodies.add(jsonDecode(request.body));
          return _session('a2', 'r2');
        }
        return okMe(sampleUser);
      },
      biometricStore: prefs,
      biometricAuthenticator: sensor,
    );
    addTearDown(harness.dispose);

    await _open(tester, harness);
    await tester.tap(find.byKey(const Key('signIn.fingerprint')));
    await tester.pumpAndSettle();

    expect(sensor.prompts, 1);
    expect(refreshBodies, [
      {'refresh_token': 'r1'},
    ]);
    expect(find.byType(NukhbaaShell), findsOneWidget);
    expect(await harness.store.read(), 'a2');
    expect(await harness.store.readRefreshToken(), 'r2');
    expect(await prefs.readSavedRefreshToken(), isNull);
  });

  _screenTest('an expired fingerprint sign-in says so and hides the button', (
    tester,
  ) async {
    final prefs = InMemoryBiometricPreferenceStore(
      enabled: true,
      offered: true,
    );
    await prefs.saveRefreshToken('spent');
    final harness = buildAuthHarness(
      (request) async => request.url.path == '/auth/refresh'
          ? http.Response(
              jsonEncode({
                'schema_version': 1,
                'code': 'auth.rejected',
                'message': 'Invalid Refresh Token',
              }),
              400,
              headers: _json,
            )
          : okMe(sampleUser),
      biometricStore: prefs,
      biometricAuthenticator: _PassingSensor(),
    );
    addTearDown(harness.dispose);

    await _open(tester, harness);
    await tester.tap(find.byKey(const Key('signIn.fingerprint')));
    await tester.pumpAndSettle();

    expect(find.byType(NukhbaaShell), findsNothing);
    expect(find.byKey(const Key('signIn.fingerprint')), findsNothing);
    expect(await prefs.readSavedRefreshToken(), isNull);
  });

  _screenTest('without a kept token there is no fingerprint button', (
    tester,
  ) async {
    final harness = buildAuthHarness(
      (_) async => okMe(sampleUser),
      biometricStore: InMemoryBiometricPreferenceStore(
        enabled: true,
        offered: true,
      ),
      biometricAuthenticator: _PassingSensor(),
    );
    addTearDown(harness.dispose);

    await _open(tester, harness);

    expect(find.byKey(const Key('signIn.fingerprint')), findsNothing);
    expect(find.byKey(const Key('signIn.submit')), findsOneWidget);
  });
}
