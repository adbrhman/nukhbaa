/// The admin's users tab through its real providers and `AdminApi`, over
/// the auth harness's fake server: an account is found by its name, shown
/// by its name (never its id), renamed with the reason typed, and suspended.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/screens/sections/user_sanction_section.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

const String _id = '22222222-2222-4222-8222-222222222222';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

Map<String, Object?> _user(String name, String status) => {
  'schema_version': 1,
  'id': _id,
  'email': 'semo@t.io',
  'display_name': name,
  'status': status,
};

final class _Server {
  final List<http.Request> requests = <http.Request>[];

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final String path = request.url.path;
    if (path == '/admin/users') {
      return _json({
        'schema_version': 1,
        'users': [_user('Semo', 'active')],
      });
    }
    if (path == '/admin/users/$_id/fixture-predictions') {
      return _json({
        'schema_version': 1,
        'user': _user('Semo', 'active'),
        'prediction_count': 0,
        'exact_count': 0,
        'correct_double_count': 0,
        'total_points': 0,
        'predictions': <Object?>[],
      });
    }
    if (path == '/admin/users/$_id/display-name') {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      return _json(_user(body['display_name']! as String, 'active'));
    }
    if (path == '/admin/users/$_id/suspend') {
      return _json(const {
        'schema_version': 1,
        'user_id': _id,
        'status': 'suspended',
      });
    }
    if (path == '/admin/audit') {
      return _json(const {'schema_version': 1, 'entries': <Object?>[]});
    }
    return okMe(sampleUser);
  }

  List<http.Request> to(String path) => [
    for (final r in requests)
      if (r.url.path == path) r,
  ];
}

Future<void> _openAndPick(WidgetTester tester, _Server server) async {
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
        home: const Scaffold(body: UserSanctionSection()),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('admin.users.predictionSearch.field')),
    'semo',
  );
  await tester.tap(
    find.byKey(const Key('admin.users.predictionSearch.button')),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const Key('admin.users.predictionSearch.result.$_id')),
  );
  await tester.pumpAndSettle();
}

String? _heading(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('admin.users.selectedName'))).data;

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the picked account is shown by its name, never its id', (
    tester,
  ) async {
    await _openAndPick(tester, _Server());

    // The name field holds the name too, so the heading is read by its key.
    expect(_heading(tester), 'Semo');
    expect(find.textContaining(_id), findsNothing);
  });

  testWidgets('renames the account with the reason typed', (tester) async {
    final server = _Server();
    await _openAndPick(tester, server);

    await tester.enterText(
      find.byKey(const Key('admin.users.nameField')),
      'Semo Ali',
    );
    await tester.enterText(
      find.byKey(const Key('admin.users.reasonField')),
      'اسم أوضح',
    );
    await _tap(tester, const Key('admin.users.rename'));

    final sent = server.to('/admin/users/$_id/display-name').single;
    expect(jsonDecode(sent.body), {
      'schema_version': 1,
      'display_name': 'Semo Ali',
      'reason': 'اسم أوضح',
    });
    expect(find.text('تم تعديل الاسم إلى «Semo Ali»'), findsOneWidget);
    expect(_heading(tester), 'Semo Ali');
  });

  testWidgets('no request leaves without a reason', (tester) async {
    final server = _Server();
    await _openAndPick(tester, server);

    await _tap(tester, const Key('admin.users.rename'));
    await _tap(tester, const Key('admin.users.suspend'));

    expect(find.text('اكتب السبب أولاً'), findsOneWidget);
    expect(server.to('/admin/users/$_id/display-name'), isEmpty);
    expect(server.to('/admin/users/$_id/suspend'), isEmpty);
  });

  testWidgets('suspends the account by its name', (tester) async {
    final server = _Server();
    await _openAndPick(tester, server);

    await tester.enterText(
      find.byKey(const Key('admin.users.reasonField')),
      'حساب مكرر',
    );
    await _tap(tester, const Key('admin.users.suspend'));

    final sent = server.to('/admin/users/$_id/suspend').single;
    expect(jsonDecode(sent.body), containsPair('reason', 'حساب مكرر'));
    expect(find.text('تم تعليق «Semo» وإخفاؤه من اللوحات'), findsOneWidget);
    expect(find.text('معلَّق: مخفي هو ونقاطه من كل اللوحات'), findsOneWidget);
  });
}
