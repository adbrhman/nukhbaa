/// An invitation refused because it came from the browser or from the
/// inviter's own phone (migration 0086) is told to the player in so many
/// words: through the real `SessionController`, `AuthApi` and session gate
/// over the auth harness's fake server.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/auth/install_id.dart';
import 'package:mobile/features/auth/session_controller.dart';
import 'package:mobile/features/auth/session_gate.dart';
import 'package:mobile/features/gamification/invite_friends_screen.dart';
import 'package:mobile/features/gamification/referral_notice.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

Future<http.Response> Function(http.Request) _serverAnswering(String status) =>
    (http.Request request) async {
      if (request.url.path == '/auth/register') {
        return okLoginResponse('new-jwt');
      }
      if (request.url.path == '/me/referral/claim') {
        return http.Response(
          jsonEncode({'schema_version': 1, 'status': status}),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return okMe(sampleUser);
    };

ProviderContainer _container(String status) {
  final harness = buildAuthHarness(_serverAnswering(status));
  addTearDown(harness.dispose);
  final container = ProviderContainer(
    overrides: [
      ...harness.overrides,
      installIdStoreProvider.overrideWithValue(
        const FixedInstallIdStore('inst-12345678'),
      ),
    ],
    retry: (retryCount, error) => null,
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _register(ProviderContainer container) async {
  await container.read(sessionControllerProvider.future);
  await container
      .read(sessionControllerProvider.notifier)
      .register(
        displayName: 'Khaled',
        email: 'k@example.com',
        password: 'secret-123',
        referralCode: 'ABCDEFGH',
      );
}

void main() {
  test('a code refused on the inviter\'s phone leaves its notice', () async {
    final container = _container('same_device');

    await _register(container);

    expect(container.read(referralNoticeProvider), referralSameDeviceMessage);
  });

  test('a code used from the browser leaves its notice', () async {
    final container = _container('app_required');

    await _register(container);

    expect(container.read(referralNoticeProvider), referralAppRequiredMessage);
  });

  test('an accepted code leaves no notice', () async {
    final container = _container('claimed');

    await _register(container);

    expect(container.read(referralNoticeProvider), isNull);
  });

  test('the invitation page words both refusals', () {
    expect(referralClaimMessage('same_device'), referralSameDeviceMessage);
    expect(referralClaimMessage('app_required'), referralAppRequiredMessage);
  });

  testWidgets('the session gate shows the notice once, then drops it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = buildAuthHarness(_serverAnswering('claimed'));
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: const MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: SessionGate(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(SessionGate)),
    );

    container
        .read(referralNoticeProvider.notifier)
        .show(referralSameDeviceMessage);
    await tester.pumpAndSettle();

    expect(find.text(referralSameDeviceMessage), findsOneWidget);
    expect(container.read(referralNoticeProvider), isNull);
    await tester.tap(find.byKey(const Key('referral.notice.ok')));
    await tester.pumpAndSettle();
    expect(find.text(referralSameDeviceMessage), findsNothing);
  });
}
