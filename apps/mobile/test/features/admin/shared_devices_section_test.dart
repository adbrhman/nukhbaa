/// The admin's shared-phones page (script 200) through its real provider and
/// the real `AdminApi`, over the auth harness's fake server: it lists every
/// phone with the number of its accounts, suspends the account the admin
/// taps with the reason typed, reinstates a suspended one, and refuses to
/// send without a reason. Also drawn at 360px with text x2.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/screens/sections/shared_devices_section.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

const String _a = '11111111-1111-4111-8111-111111111111';
const String _b = '22222222-2222-4222-8222-222222222222';
const String _c = '33333333-3333-4333-8333-333333333333';
const String _d = '44444444-4444-4444-8444-444444444444';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

Map<String, Object?> _user(String id, String name, String status) => {
  'schema_version': 1,
  'id': id,
  'email': 'p${id.substring(0, 4)}@t.io',
  'display_name': name,
  'status': status,
};

final class _Server {
  final List<http.Request> requests = <http.Request>[];
  bool empty = false;
  bool fail = false;

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final String path = request.url.path;
    if (path == '/admin/shared-devices') {
      if (fail) {
        return _json(const {
          'schema_version': 1,
          'code': 'db.unavailable',
          'message': 'down',
        }, 503);
      }
      return _json({
        'schema_version': 1,
        'devices': empty
            ? <Object?>[]
            : [
                {
                  'users': [
                    _user(_a, 'أحمد', 'active'),
                    _user(_b, 'أبو أحمد', 'active'),
                    _user(_c, 'أحمد ثلاثة', 'suspended'),
                  ],
                  'last_seen': '2026-11-02T09:00:00.000Z',
                },
                {
                  'users': [
                    _user(_a, 'أحمد', 'active'),
                    _user(_d, 'خالد', 'active'),
                  ],
                  'last_seen': '2026-10-20T09:00:00.000Z',
                },
              ],
      });
    }
    if (path == '/admin/users/$_b/suspend') {
      return _json(const {
        'schema_version': 1,
        'user_id': _b,
        'status': 'suspended',
      });
    }
    if (path == '/admin/users/$_c/reinstate') {
      return _json(const {
        'schema_version': 1,
        'user_id': _c,
        'status': 'active',
      });
    }
    return okMe(sampleUser);
  }

  List<http.Request> to(String path) => [
    for (final r in requests)
      if (r.url.path == path) r,
  ];
}

Future<void> _open(
  WidgetTester tester,
  _Server server, {
  Size size = const Size(1080, 2340),
  double ratio = 3.0,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final harness = buildAuthHarness(server.handle, seedToken: 'admin-jwt');
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        locale: const Locale('ar'),
        home: MediaQuery(
          data: MediaQueryData(
            size: size / ratio,
            textScaler: TextScaler.linear(textScale),
          ),
          child: const Scaffold(body: SharedDevicesSection()),
        ),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  test('the count of accounts reads as Arabic counts', () {
    expect(sharedDeviceAccounts(2), 'حسابان');
    expect(sharedDeviceAccounts(3), '3 حسابات');
    expect(sharedDeviceAccounts(10), '10 حسابات');
    expect(sharedDeviceAccounts(11), '11 حساباً');
  });

  testWidgets('lists each phone with the number of its accounts', (
    tester,
  ) async {
    await _open(tester, _Server());

    expect(
      find.text('هواتف بأكثر من حساب: 2 · حسابات فيها: 5'),
      findsOneWidget,
    );
    expect(find.text('هاتف 1 · 3 حسابات'), findsOneWidget);
    expect(find.text('هاتف 2 · حسابان'), findsOneWidget);
    expect(
      find.byKey(const Key('admin.devices.account.0.$_c')),
      findsOneWidget,
    );
    expect(find.textContaining('موقوف'), findsOneWidget);
    expect(find.text('آخر ظهور: 2026/11/02'), findsOneWidget);
  });

  testWidgets('suspends the tapped account with the reason typed', (
    tester,
  ) async {
    final server = _Server();
    await _open(tester, server);
    final int readsBefore = server.to('/admin/shared-devices').length;
    await _tapVisible(tester, const Key('admin.devices.account.0.$_b'));

    await tester.enterText(
      find.byKey(const Key('admin.devices.reasonField')),
      'حسابان على هاتف واحد',
    );
    await _tapVisible(tester, const Key('admin.devices.suspend'));

    final sent = server.to('/admin/users/$_b/suspend').single;
    expect(sent.method, 'POST');
    expect(
      jsonDecode(sent.body),
      containsPair('reason', 'حسابان على هاتف واحد'),
    );
    expect(
      find.text('أُوقف الحساب: لا يظهر في اللوحات ولا يكسب نقاطاً'),
      findsOneWidget,
    );
    expect(server.to('/admin/shared-devices').length, greaterThan(readsBefore));
  });

  testWidgets('reinstates a suspended account', (tester) async {
    final server = _Server();
    await _open(tester, server);
    await _tapVisible(tester, const Key('admin.devices.account.0.$_c'));

    expect(find.byKey(const Key('admin.devices.suspend')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('admin.devices.reasonField')),
      'خطأ',
    );
    await _tapVisible(tester, const Key('admin.devices.reinstate'));

    expect(server.to('/admin/users/$_c/reinstate'), hasLength(1));
    expect(find.text('أُعيد الحساب ونقاطه إلى اللوحات'), findsOneWidget);
  });

  testWidgets('no request leaves without a reason', (tester) async {
    final server = _Server();
    await _open(tester, server);
    await _tapVisible(tester, const Key('admin.devices.account.1.$_d'));

    await _tapVisible(tester, const Key('admin.devices.suspend'));

    expect(find.text('اكتب السبب أولاً'), findsOneWidget);
    expect(server.to('/admin/users/$_d/suspend'), isEmpty);
  });

  testWidgets('no shared phone says so', (tester) async {
    await _open(tester, _Server()..empty = true);

    expect(find.text('لا يوجد هاتف عليه أكثر من حساب'), findsOneWidget);
  });

  testWidgets('a failed read offers a retry', (tester) async {
    final server = _Server()..fail = true;
    await _open(tester, server);

    expect(find.byKey(const Key('admin.devices.loadError')), findsOneWidget);
    server.fail = false;
    await _tapVisible(tester, const Key('admin.devices.retry'));

    expect(find.text('هاتف 1 · 3 حسابات'), findsOneWidget);
  });

  testWidgets('fits a 360px phone at text x2', (tester) async {
    await _open(
      tester,
      _Server(),
      size: const Size(1080, 2340),
      textScale: 2.0,
    );
    // The list builds what is on screen: scroll the last phone's account in.
    await tester.scrollUntilVisible(
      find.byKey(const Key('admin.devices.account.1.$_d')),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('admin.devices.list')),
        matching: find.byType(Scrollable),
      ),
    );
    await _tapVisible(tester, const Key('admin.devices.account.1.$_d'));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('admin.devices.suspend')), findsOneWidget);
  });
}
