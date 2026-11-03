/// Script 204 (2026-11-03): "تذكرني" at the lower corner of the password
/// field keeps the password on this phone; signing in again on the same
/// phone, a tap on the box shows it. And the server's refusal of a name
/// that is not a real one reaches the register form. Through the real
/// [SessionGate], [SignInScreen] and `AuthApi` over the auth harness's fake
/// server.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/auth/biometric_unlock.dart';
import 'package:mobile/core/auth/remembered_password.dart';
import 'package:mobile/features/auth/nukhbaa_shell.dart';
import 'package:mobile/features/auth/session_gate.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

const AuthenticatedUserDto _player = AuthenticatedUserDto(
  userId: 'u-1',
  role: 'user',
  status: 'active',
  email: 'k@example.com',
  displayName: 'Khaled Saleh',
);

/// The phone's fingerprint: [available] or not, and whether it [passes].
final class _Sensor implements BiometricAuthenticator {
  _Sensor({this.available = true, this.passes = true});

  final bool available;
  final bool passes;
  int prompts = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate({required String reason}) async {
    prompts++;
    return passes;
  }
}

/// A server that signs in and registers anyone, recording each body.
final class _Server {
  final List<Map<String, Object?>> logins = <Map<String, Object?>>[];
  final List<Map<String, Object?>> registers = <Map<String, Object?>>[];

  Future<http.Response> handle(http.Request request) async {
    if (request.url.path == '/auth/login') {
      logins.add(jsonDecode(request.body) as Map<String, Object?>);
      return okLoginResponse('jwt');
    }
    if (request.url.path == '/auth/register') {
      registers.add(jsonDecode(request.body) as Map<String, Object?>);
      return okLoginResponse('jwt');
    }
    return okMe(_player);
  }
}

/// The auth harness, on a phone without a fingerprint unless [sensor].
AuthHarness _harness(
  Future<http.Response> Function(http.Request request) handler, {
  RememberedPasswordStore? rememberedPasswords,
  BiometricAuthenticator? sensor,
}) => buildAuthHarness(
  handler,
  biometricAuthenticator: sensor ?? _Sensor(available: false),
  rememberedPasswords: rememberedPasswords,
);

Future<void> _open(WidgetTester tester, AuthHarness harness) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
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

Future<void> _submit(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('signIn.submit')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('signIn.submit')));
  await tester.pumpAndSettle();
}

Future<void> _typeEmail(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('signIn.emailField')),
    'K@example.com ',
  );
  await tester.pumpAndSettle();
}

Future<void> _tapRemember(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('signIn.remember')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('signIn.remember')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a password kept on this phone is shown by a tap on the box, '
      'fills the field and signs in', (tester) async {
    final server = _Server();
    final store = InMemoryRememberedPasswordStore(<String, String>{
      'k@example.com': 'secret-123',
    });
    final harness = _harness(server.handle, rememberedPasswords: store);
    addTearDown(harness.dispose);
    await _open(tester, harness);

    await _typeEmail(tester);
    expect(find.byKey(const Key('signIn.rememberHint')), findsOneWidget);
    expect(find.byKey(const Key('signIn.savedPassword')), findsNothing);

    await _tapRemember(tester);
    expect(find.text('كلمة المرور المحفوظة: secret-123'), findsOneWidget);

    await _submit(tester);
    expect(server.logins.single['password'], 'secret-123');
    expect(store.passwords, <String, String>{'k@example.com': 'secret-123'});
    expect(find.byType(NukhbaaShell), findsOneWidget);
  });

  testWidgets('with a fingerprint on the phone, the password shows only '
      'after it passes', (tester) async {
    final sensor = _Sensor(passes: false);
    final harness = _harness(
      _Server().handle,
      sensor: sensor,
      rememberedPasswords: InMemoryRememberedPasswordStore(<String, String>{
        'k@example.com': 'secret-123',
      }),
    );
    addTearDown(harness.dispose);
    await _open(tester, harness);

    await _typeEmail(tester);
    await _tapRemember(tester);

    expect(sensor.prompts, 1);
    expect(find.byKey(const Key('signIn.savedPassword')), findsNothing);
  });

  testWidgets('a fingerprint that passes shows the password', (tester) async {
    final sensor = _Sensor();
    final harness = _harness(
      _Server().handle,
      sensor: sensor,
      rememberedPasswords: InMemoryRememberedPasswordStore(<String, String>{
        'k@example.com': 'secret-123',
      }),
    );
    addTearDown(harness.dispose);
    await _open(tester, harness);

    await _typeEmail(tester);
    await _tapRemember(tester);

    expect(sensor.prompts, 1);
    expect(find.text('كلمة المرور المحفوظة: secret-123'), findsOneWidget);
  });

  testWidgets('another e-mail on the same phone shows nothing kept', (
    tester,
  ) async {
    final harness = _harness(
      _Server().handle,
      rememberedPasswords: InMemoryRememberedPasswordStore(<String, String>{
        'other@example.com': 'secret-123',
      }),
    );
    addTearDown(harness.dispose);
    await _open(tester, harness);

    await _typeEmail(tester);
    expect(find.byKey(const Key('signIn.rememberHint')), findsNothing);
    await _tapRemember(tester);
    expect(find.byKey(const Key('signIn.savedPassword')), findsNothing);
    expect(find.textContaining('secret-123'), findsNothing);
  });

  testWidgets('signing in with the box unticked forgets the kept password', (
    tester,
  ) async {
    final store = InMemoryRememberedPasswordStore(<String, String>{
      'k@example.com': 'old-password',
    });
    final harness = _harness(_Server().handle, rememberedPasswords: store);
    addTearDown(harness.dispose);
    await _open(tester, harness);

    await _typeEmail(tester);
    await tester.enterText(
      find.byKey(const Key('signIn.passwordField')),
      'new-password',
    );
    // The first tap shows the kept one; the second unticks the box.
    await _tapRemember(tester);
    await tester.enterText(
      find.byKey(const Key('signIn.passwordField')),
      'new-password',
    );
    await _tapRemember(tester);
    await _submit(tester);

    expect(store.passwords, isEmpty);
  });

  testWidgets('registering with the box ticked keeps the password', (
    tester,
  ) async {
    final server = _Server();
    final store = InMemoryRememberedPasswordStore();
    final harness = _harness(server.handle, rememberedPasswords: store);
    addTearDown(harness.dispose);
    await _open(tester, harness);
    await tester.tap(find.byKey(const Key('signIn.tabRegister')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('signIn.nameField')), 'Khaled');
    await tester.enterText(
      find.byKey(const Key('signIn.familyNameField')),
      'Saleh',
    );
    await _typeEmail(tester);
    await tester.enterText(
      find.byKey(const Key('signIn.passwordField')),
      'secret-123',
    );
    await tester.enterText(
      find.byKey(const Key('signIn.confirmPasswordField')),
      'secret-123',
    );
    await _tapRemember(tester);
    await _submit(tester);

    expect(server.registers, hasLength(1));
    expect(store.passwords, <String, String>{'k@example.com': 'secret-123'});
    expect(find.byType(NukhbaaShell), findsOneWidget);
  });

  testWidgets('the server refusal of an alias reaches the register form', (
    tester,
  ) async {
    final List<http.Request> registers = <http.Request>[];
    final harness = _harness((request) async {
      if (request.url.path == '/auth/register') {
        registers.add(request);
        return errorEnvelope(
          400,
          'identity.display_name_alias',
          'اكتب اسمك الحقيقي لا اسماً مستعاراً، مثل: محمد العماري',
        );
      }
      return okMe(_player);
    });
    addTearDown(harness.dispose);
    await _open(tester, harness);
    await tester.tap(find.byKey(const Key('signIn.tabRegister')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('signIn.nameField')), 'ملك');
    await tester.enterText(
      find.byKey(const Key('signIn.familyNameField')),
      'الجمال',
    );
    await _typeEmail(tester);
    await tester.enterText(
      find.byKey(const Key('signIn.passwordField')),
      'secret-123',
    );
    await tester.enterText(
      find.byKey(const Key('signIn.confirmPasswordField')),
      'secret-123',
    );
    await _submit(tester);

    expect(registers, hasLength(1));
    expect(find.byKey(const Key('signIn.errorBanner')), findsOneWidget);
    expect(find.textContaining('لا اسماً مستعاراً'), findsOneWidget);
    expect(find.byType(NukhbaaShell), findsNothing);
  });
}
