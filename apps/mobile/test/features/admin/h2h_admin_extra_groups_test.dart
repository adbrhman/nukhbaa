/// Adding groups to the month open now (2026-10-11) from the admin's
/// settings tab, through the real section, its providers and the real
/// `AdminApi` over the auth harness's fake server: the count is chosen,
/// nothing is sent before the confirmation, the answer is read back, and a
/// refusal is read in Arabic.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/screens/sections/h2h_admin_section.dart';
import 'package:mobile/features/admin/screens/sections/h2h_admin_tabs.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:shared/shared.dart';

import '../../support/auth_harness.dart';

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

/// October, drawn as the pilot; the extra groups are added unless
/// [refuse] is set.
final class _Server {
  _Server({this.refuse = false});

  final bool refuse;
  final List<http.Request> requests = <http.Request>[];

  List<http.Request> sent(String method, String path) => <http.Request>[
    for (final http.Request r in requests)
      if (r.method == method && r.url.path == path) r,
  ];

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final String path = request.url.path;
    final String method = request.method;
    if (path == '/admin/h2h/rounds' && method == 'GET') {
      return _json(const {
        'month_start': '2026-10-01',
        'starts_on': '2026-10-01',
        'drawn': true,
        'is_pilot': true,
        'rounds': <Object?>[],
        'candidates': <Object?>[],
      });
    }
    if (path == '/admin/h2h/controls' && method == 'GET') {
      return _json(const {
        'month_start': '2026-10-01',
        'settings': {
          'auto_approve': true,
          'lead_hours': 24,
          'min_active_days': 5,
          'lead_hours_min': 1,
          'lead_hours_max': 24,
          'min_active_days_min': 1,
          'min_active_days_max': 28,
          'updated_by_name': null,
          'updated_at': null,
        },
        'days': <Object?>[],
        'actions': <Object?>[],
      });
    }
    if (path == '/admin/h2h/extra-groups' && method == 'POST') {
      if (refuse) {
        return _json(const {
          'schema_version': 1,
          'code': 'h2h.groups_no_players',
          'message': 'nobody',
        }, status: 409);
      }
      final int groups =
          (jsonDecode(request.body) as Map<String, Object?>)['groups']! as int;
      return _json(<String, Object?>{
        'month_start': '2026-10-01',
        'groups': [
          for (var i = 0; i < groups; i++)
            {
              'league_id': 'g-$i',
              'division': 2 + i,
              'group_index': 0,
              'seats': 20,
            },
        ],
        'seats': groups * 20,
        'waiting': 72 - groups * 20,
      }, status: 201);
    }
    return okMe(sampleUser);
  }
}

Future<void> _openControls(WidgetTester tester, _Server server) async {
  tester.view.physicalSize = const Size(1080, 7200);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final harness = buildAuthHarness(server.handle, seedToken: 'admin-jwt');
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        locale: const Locale('ar'),
        home: const Scaffold(body: H2hAdminSection()),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('admin.h2h.tab.controls')));
  await tester.pumpAndSettle();
}

void main() {
  test('the log and the refusals speak Arabic', () {
    expect(h2hAdminActionLabel('groups_added'), 'إضافة مجموعات');
    expect(
      h2hAdminActionDetail(const {'groups': 3, 'seats': 60}),
      'المجموعات 3 · المقاعد 60',
    );
    expect(
      h2hAdminErrorMessage(
        const AppError.invariant('h2h.groups_no_players', 'nobody'),
      ),
      'لا يوجد لاعبان على الأقل بلا مقعد وبأيام نشاط كافية.',
    );
  });

  testWidgets('three groups are added only after the confirmation', (
    tester,
  ) async {
    final _Server server = _Server();
    await _openControls(tester, server);

    expect(find.byKey(const Key('admin.h2h.extraGroups')), findsOneWidget);
    for (var i = 0; i < 2; i++) {
      await tester.tap(
        find.byKey(const Key('admin.h2h.extraGroups.count.inc')),
      );
      await tester.pump();
    }
    expect(find.text('عدد المجموعات: 3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('admin.h2h.extraGroups.add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.h2h.confirm.cancel')));
    await tester.pumpAndSettle();
    expect(server.sent('POST', '/admin/h2h/extra-groups'), isEmpty);

    await tester.tap(find.byKey(const Key('admin.h2h.extraGroups.add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.h2h.confirm.ok')));
    await tester.pumpAndSettle();

    final List<http.Request> posts = server.sent(
      'POST',
      '/admin/h2h/extra-groups',
    );
    expect(posts, hasLength(1));
    expect(jsonDecode(posts.single.body), {'groups': 3});
    expect(
      find.text('أُضيفت المجموعات: 3 · المقاعد: 60 · بلا مقعد بعد: 12'),
      findsOneWidget,
    );
  });

  testWidgets('a refusal is read in Arabic', (tester) async {
    await _openControls(tester, _Server(refuse: true));

    await tester.tap(find.byKey(const Key('admin.h2h.extraGroups.add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.h2h.confirm.ok')));
    await tester.pumpAndSettle();

    expect(
      find.text('لا يوجد لاعبان على الأقل بلا مقعد وبأيام نشاط كافية.'),
      findsOneWidget,
    );
  });
}
