/// "Continue with Google" through the real [SessionController] and
/// [SessionGate], with the device account picker faked.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/auth/google_id_token_source.dart';
import 'package:mobile/features/auth/nukhbaa_shell.dart';
import 'package:mobile/features/auth/session_controller.dart';
import 'package:mobile/features/auth/session_gate.dart';
import 'package:mobile/features/auth/session_state.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:shared/shared.dart';

import '../../support/auth_harness.dart';

final class _FakeGoogle implements GoogleIdTokenSource {
  _FakeGoogle(this._result);

  final Result<String?> _result;
  int picks = 0;

  @override
  bool get isSupported => true;

  @override
  Future<Result<String?>> pickIdToken() async {
    picks++;
    return _result;
  }
}

Future<http.Response> _server(http.Request request) async {
  if (request.url.path == '/auth/google') {
    expect(jsonDecode(request.body), {'id_token': 'google-id-token'});
    return http.Response(
      jsonEncode({
        'schema_version': 1,
        'access_token': 'g-access',
        'refresh_token': 'g-refresh',
      }),
      200,
      headers: const {'content-type': 'application/json'},
    );
  }
  return okMe(sampleUser);
}

bool _calledGoogle(AuthHarness harness) => harness.captured.any(
  (captured) => captured.request.url.path == '/auth/google',
);

void main() {
  test('a picked Google account signs in and keeps both tokens', () async {
    final harness = buildAuthHarness(
      _server,
      googleIdTokenSource: _FakeGoogle(const Result.ok('google-id-token')),
    );
    addTearDown(harness.dispose);
    await harness.container.read(sessionControllerProvider.future);

    await harness.container
        .read(sessionControllerProvider.notifier)
        .signInWithGoogle();

    expect(
      harness.container.read(sessionControllerProvider).value,
      isA<SessionAuthenticated>(),
    );
    expect(await harness.store.read(), 'g-access');
    expect(await harness.store.readRefreshToken(), 'g-refresh');
  });

  test('closing the picker returns to the form without a request', () async {
    final harness = buildAuthHarness(
      _server,
      googleIdTokenSource: _FakeGoogle(const Result.ok(null)),
    );
    addTearDown(harness.dispose);
    await harness.container.read(sessionControllerProvider.future);

    await harness.container
        .read(sessionControllerProvider.notifier)
        .signInWithGoogle();

    expect(
      harness.container.read(sessionControllerProvider).value,
      isA<SessionUnauthenticated>(),
    );
    expect(_calledGoogle(harness), isFalse);
    expect(await harness.store.read(), isNull);
  });

  test('a failed pick is shown, and nothing is stored', () async {
    final harness = buildAuthHarness(
      _server,
      googleIdTokenSource: _FakeGoogle(
        const Result.err(
          AppError.transient(
            'auth.google_failed',
            'تعذّر الدخول بحساب Google.',
          ),
        ),
      ),
    );
    addTearDown(harness.dispose);
    await harness.container.read(sessionControllerProvider.future);

    await harness.container
        .read(sessionControllerProvider.notifier)
        .signInWithGoogle();

    final state = harness.container.read(sessionControllerProvider).value;
    expect((state! as SessionFailed).error.code, 'auth.google_failed');
    expect(_calledGoogle(harness), isFalse);
  });

  testWidgets('the sign-in form offers Google, and it lands in the app', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final google = _FakeGoogle(const Result.ok('google-id-token'));
    final harness = buildAuthHarness(_server, googleIdTokenSource: google);
    addTearDown(harness.dispose);

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

    await tester.tap(find.byKey(const Key('signIn.google')));
    await tester.pumpAndSettle();

    expect(google.picks, 1);
    expect(find.byType(NukhbaaShell), findsOneWidget);
  });
}
