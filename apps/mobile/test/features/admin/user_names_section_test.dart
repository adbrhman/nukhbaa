/// The admin's names page through its real provider and the real `AdminApi`,
/// over the auth harness's fake server: it lists the duplicate names, renames
/// the account the admin taps with the reason typed, shows the server's
/// refusal of a taken name, and hides an account from the boards.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/screens/sections/user_names_section.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

const String _a = '11111111-1111-4111-8111-111111111111';
const String _b = '22222222-2222-4222-8222-222222222222';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

final class _Server {
  final List<http.Request> requests = <http.Request>[];
  bool nameTaken = false;

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final String path = request.url.path;
    if (path == '/admin/duplicate-names') {
      return _json(const {
        'schema_version': 1,
        'groups': [
          {
            'users': [
              {
                'schema_version': 1,
                'id': _a,
                'email': 'a@t.io',
                'display_name': 'أحمد',
                'status': 'active',
              },
              {
                'schema_version': 1,
                'id': _b,
                'email': 'b@t.io',
                'display_name': 'احمد',
                'status': 'active',
              },
            ],
          },
        ],
      });
    }
    if (path == '/admin/users/$_b/display-name') {
      if (nameTaken) {
        return _json(const {
          'schema_version': 1,
          'code': 'identity.display_name_taken',
          'message': 'هذا الاسم مستخدم، اختر اسمًا آخر',
        }, 400);
      }
      final body = jsonDecode(request.body) as Map<String, Object?>;
      return _json({
        'schema_version': 1,
        'id': _b,
        'email': 'b@t.io',
        'display_name': body['display_name'],
        'status': 'active',
      });
    }
    if (path == '/admin/users/$_b/suspend') {
      return _json(const {
        'schema_version': 1,
        'user_id': _b,
        'status': 'suspended',
      });
    }
    return okMe(sampleUser);
  }

  List<http.Request> to(String path) => [
    for (final r in requests)
      if (r.url.path == path) r,
  ];
}

Future<void> _open(WidgetTester tester, _Server server) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final harness = buildAuthHarness(server.handle, seedToken: 'admin-jwt');
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        home: const Scaffold(body: UserNamesSection()),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pickB(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('admin.names.duplicate.$_b')));
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists each shared name with its accounts', (tester) async {
    await _open(tester, _Server());

    expect(find.text('أسماء مكررة: 1'), findsOneWidget);
    expect(find.byKey(const Key('admin.names.duplicate.$_a')), findsOneWidget);
    expect(find.byKey(const Key('admin.names.duplicate.$_b')), findsOneWidget);
  });

  testWidgets('renames the tapped account with the reason typed', (
    tester,
  ) async {
    final server = _Server();
    await _open(tester, server);
    final int readsBefore = server.to('/admin/duplicate-names').length;
    await _pickB(tester);

    await tester.enterText(
      find.byKey(const Key('admin.names.nameField')),
      'أحمد سالم',
    );
    await tester.enterText(
      find.byKey(const Key('admin.names.reasonField')),
      'اسم مكرر',
    );
    await _tapVisible(tester, const Key('admin.names.save'));

    final sent = server.to('/admin/users/$_b/display-name').single;
    expect(sent.method, 'POST');
    expect(jsonDecode(sent.body), {
      'schema_version': 1,
      'display_name': 'أحمد سالم',
      'reason': 'اسم مكرر',
    });
    expect(find.text('تم تعديل الاسم إلى «أحمد سالم»'), findsOneWidget);
    // The list is read again after the change.
    expect(
      server.to('/admin/duplicate-names').length,
      greaterThan(readsBefore),
    );
  });

  testWidgets('shows the refusal of a name another player holds', (
    tester,
  ) async {
    final server = _Server()..nameTaken = true;
    await _open(tester, server);
    await _pickB(tester);

    await tester.enterText(
      find.byKey(const Key('admin.names.nameField')),
      'أحمد',
    );
    await tester.enterText(
      find.byKey(const Key('admin.names.reasonField')),
      'اسم مكرر',
    );
    await _tapVisible(tester, const Key('admin.names.save'));

    expect(find.text('هذا الاسم مستخدم، اختر اسمًا آخر'), findsOneWidget);
  });

  testWidgets('no request leaves without a reason', (tester) async {
    final server = _Server();
    await _open(tester, server);
    await _pickB(tester);

    await _tapVisible(tester, const Key('admin.names.save'));

    expect(find.text('اكتب السبب أولاً'), findsOneWidget);
    expect(server.to('/admin/users/$_b/display-name'), isEmpty);
  });

  testWidgets('hides the account from every board', (tester) async {
    final server = _Server();
    await _open(tester, server);
    await _pickB(tester);

    await tester.enterText(
      find.byKey(const Key('admin.names.reasonField')),
      'حساب مكرر',
    );
    await _tapVisible(tester, const Key('admin.names.hide'));

    final sent = server.to('/admin/users/$_b/suspend').single;
    expect(jsonDecode(sent.body), containsPair('reason', 'حساب مكرر'));
    expect(find.text('أُخفي الحساب ونقاطه من كل اللوحات'), findsOneWidget);
    expect(find.byKey(const Key('admin.names.show')), findsOneWidget);
  });
}
