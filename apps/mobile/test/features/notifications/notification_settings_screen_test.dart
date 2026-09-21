/// Widget tests for [NotificationSettingsScreen] over the real [AuthApi] and
/// the real [ApiTransport], with only the socket faked ([buildAuthHarness]'s
/// `MockClient`). The page reads `GET /me/notification-preferences`, writes
/// `PUT` on a tap, and shows what the server answered -- so a page that
/// stopped asking, wrote the wrong body, or showed a switch the server did
/// not store fails here. The last test enters from the settings page, the
/// way a player reaches it.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/auth/account_settings_screen.dart';
import 'package:mobile/features/notifications/notification_settings_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

const String _path = '/me/notification-preferences';
const Key _switchKey = Key('notifications.settings.predictionReminder');

http.Response _okJson(Map<String, Object?> body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

Map<String, Object?> _prefs(bool reminder) => <String, Object?>{
  'schema_version': 1,
  'prediction_reminder': reminder,
};

Future<void> _pump(
  WidgetTester tester,
  AuthHarness harness,
  Widget home,
) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

bool _switchValue(WidgetTester tester) =>
    tester.widget<Switch>(find.byKey(_switchKey)).value;

void main() {
  final AppLocalizations ar = lookupAppLocalizations(const Locale('ar'));

  testWidgets('a player who never changed anything sees the reminder on', (
    tester,
  ) async {
    final harness = buildAuthHarness((request) async {
      if (request.url.path == _path) return _okJson(_prefs(true));
      return http.Response('not found', 404);
    }, seedToken: 'jwt');
    addTearDown(harness.dispose);

    await _pump(tester, harness, const NotificationSettingsScreen());

    expect(
      harness.captured.map((c) => '${c.request.method} ${c.request.url.path}'),
      contains('GET $_path'),
    );
    expect(find.text(ar.notificationSettingsReminderTitle), findsOneWidget);
    expect(_switchValue(tester), isTrue);
  });

  testWidgets('turning it off writes PUT and shows what was stored', (
    tester,
  ) async {
    final harness = buildAuthHarness((request) async {
      if (request.url.path != _path) return http.Response('not found', 404);
      if (request.method == 'PUT') {
        final Map<String, Object?> sent =
            (jsonDecode(request.body) as Map<Object?, Object?>)
                .cast<String, Object?>();
        return _okJson(_prefs(sent['prediction_reminder'] == true));
      }
      return _okJson(_prefs(true));
    }, seedToken: 'jwt');
    addTearDown(harness.dispose);

    await _pump(tester, harness, const NotificationSettingsScreen());
    await tester.tap(find.byKey(_switchKey));
    await tester.pumpAndSettle();

    final puts = harness.captured
        .where((c) => c.request.method == 'PUT')
        .toList();
    expect(puts, hasLength(1));
    expect(puts.single.request.url.path, _path);
    expect(
      (jsonDecode(puts.single.request.body)
          as Map<Object?, Object?>)['prediction_reminder'],
      false,
    );
    expect(_switchValue(tester), isFalse);
  });

  testWidgets('a stored "off" is read back as off', (tester) async {
    final harness = buildAuthHarness((request) async {
      if (request.url.path == _path) return _okJson(_prefs(false));
      return http.Response('not found', 404);
    }, seedToken: 'jwt');
    addTearDown(harness.dispose);

    await _pump(tester, harness, const NotificationSettingsScreen());

    expect(_switchValue(tester), isFalse);
  });

  testWidgets('a failed write leaves the switch where it was, and says so', (
    tester,
  ) async {
    final harness = buildAuthHarness((request) async {
      if (request.url.path != _path) return http.Response('not found', 404);
      if (request.method == 'PUT') {
        return http.Response(
          jsonEncode(<String, Object?>{'code': 'db.down', 'message': 'down'}),
          503,
          headers: const {'content-type': 'application/json'},
        );
      }
      return _okJson(_prefs(true));
    }, seedToken: 'jwt');
    addTearDown(harness.dispose);

    await _pump(tester, harness, const NotificationSettingsScreen());
    await tester.tap(find.byKey(_switchKey));
    await tester.pumpAndSettle();

    expect(_switchValue(tester), isTrue);
    expect(find.text(ar.notificationSettingsSaveFailed), findsOneWidget);
  });

  testWidgets('the settings page opens it', (tester) async {
    final harness = buildAuthHarness((request) async {
      if (request.url.path == _path) return _okJson(_prefs(true));
      return http.Response('not found', 404);
    }, seedToken: 'jwt');
    addTearDown(harness.dispose);

    await _pump(tester, harness, const AccountSettingsScreen());
    await tester.tap(find.byKey(const Key('account.notifications')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('notifications.settings.title')),
      findsOneWidget,
    );
    expect(find.byKey(_switchKey), findsOneWidget);
  });
}
