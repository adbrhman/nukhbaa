/// A player deletes his own account (audit M-05, script 114), through the
/// real SessionGate, account tab, settings page, delete page, session
/// controller, AuthApi and transport; only the socket is faked. The button
/// sleeps until the word is typed; the request is `DELETE /me/account`; on
/// success the token is gone and the sign-in form is back; on a refusal the
/// player stays signed in and is told why.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/auth/delete_account_screen.dart';
import 'package:mobile/features/auth/session_gate.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

Widget _appUnder(AuthHarness harness) => ProviderScope(
  overrides: harness.overrides,
  child: MaterialApp(
    home: const SessionGate(),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
  ),
);

bool _isDelete(http.Request r) =>
    r.method == 'DELETE' && r.url.path == '/me/account';

/// Signs in from the saved token and opens the delete page.
Future<void> _openDeletePage(WidgetTester tester, AuthHarness harness) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_appUnder(harness));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('nav.item.account')));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('account.settings')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('account.settings')));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('account.deleteAccount')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('account.deleteAccount')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('deleteAccount.title')), findsOneWidget);
}

Future<void> _confirm(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('deleteAccount.confirm')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const Key('deleteAccount.confirm')),
    warnIfMissed: false,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the word wakes the button; the account is deleted and the '
      'sign-in form is back', (tester) async {
    final harness = buildAuthHarness((request) async {
      if (_isDelete(request)) {
        return http.Response(
          jsonEncode(<String, Object?>{'deleted': true}),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return okMe(sampleUser);
    }, seedToken: 'saved-jwt');
    addTearDown(harness.dispose);

    await _openDeletePage(tester, harness);

    await _confirm(tester);
    expect(harness.captured.where((c) => _isDelete(c.request)), isEmpty);

    await tester.enterText(
      find.byKey(const Key('deleteAccount.word')),
      deleteAccountWord,
    );
    await tester.pump();
    await _confirm(tester);

    expect(harness.captured.where((c) => _isDelete(c.request)), hasLength(1));
    expect(await harness.store.read(), isNull);
    expect(find.byKey(const Key('deleteAccount.title')), findsNothing);
    expect(find.byKey(const Key('signIn.title')), findsOneWidget);
  });

  testWidgets('a refusal keeps the player signed in and says why', (
    tester,
  ) async {
    final harness = buildAuthHarness((request) async {
      if (_isDelete(request)) {
        return errorEnvelope(
          409,
          'identity.admin_account_kept',
          'An administrator account cannot be deleted from the app',
        );
      }
      return okMe(sampleUser);
    }, seedToken: 'saved-jwt');
    addTearDown(harness.dispose);

    await _openDeletePage(tester, harness);
    await tester.enterText(
      find.byKey(const Key('deleteAccount.word')),
      deleteAccountWord,
    );
    await tester.pump();
    await _confirm(tester);

    expect(harness.captured.where((c) => _isDelete(c.request)), hasLength(1));
    expect(find.byKey(const Key('deleteAccount.failure')), findsOneWidget);
    expect(await harness.store.read(), 'saved-jwt');
  });
}
