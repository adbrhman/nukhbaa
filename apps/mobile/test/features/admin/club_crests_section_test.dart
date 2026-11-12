/// The owner admin's crests (script 266, over script 265's routes) through
/// the real provider and the real `AdminApi`, over the auth harness's fake
/// server: every crest with its status and the log; a crest hidden for a
/// complaint, shown again, deleted only once its name is typed; every club
/// crest switched off with a reason. Also drawn at 360px with text x2.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/screens/sections/club_crests_section.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

final class _Server {
  final List<http.Request> requests = <http.Request>[];
  bool enabled = true;
  final Map<String, String> status = <String, String>{
    'arsenal': 'active',
    'chelsea': 'active',
    'milan': 'hidden',
  };

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final String path = request.url.path;
    if (path == '/admin/crests' && request.method == 'GET') {
      return _json({
        'schema_version': 1,
        'clubs_enabled': enabled,
        'crests': [
          for (final MapEntry<String, String> e in status.entries)
            {
              'slug': e.key,
              'status': e.value,
              if (e.value == 'hidden') 'reason': 'شكوى النادي',
              if (e.value == 'hidden') 'complainant': 'legal@milan.example',
            },
        ],
        'events': [
          {
            'action': 'hidden',
            'slug': 'milan',
            'reason': 'شكوى النادي',
            'complainant': 'legal@milan.example',
            'at': '2026-11-12T10:00:00Z',
          },
        ],
      });
    }
    if (path == '/admin/crests' && request.method == 'PUT') {
      final Map<String, Object?> body = (jsonDecode(request.body) as Map)
          .cast<String, Object?>();
      enabled = body['clubs_enabled'] == true;
      return _json({'clubs_enabled': enabled});
    }
    if (path.startsWith('/admin/crests/')) {
      final String slug = path.substring('/admin/crests/'.length);
      final Map<String, Object?> body = (jsonDecode(request.body) as Map)
          .cast<String, Object?>();
      final String next = switch (body['action']) {
        'hide' => 'hidden',
        'show' => 'active',
        _ => 'deleted',
      };
      status[slug] = next;
      return _json({'status': next});
    }
    return okMe(sampleUser);
  }

  List<Map<String, Object?>> posts(String slug) => [
    for (final r in requests)
      if (r.url.path == '/admin/crests/$slug')
        (jsonDecode(r.body) as Map).cast<String, Object?>(),
  ];
}

Future<void> _open(
  WidgetTester tester,
  _Server server, {
  double height = 6000,
  double textScale = 1.0,
}) async {
  final Size size = Size(1080, height);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 3.0;
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
            size: size / 3.0,
            textScaler: TextScaler.linear(textScale),
          ),
          child: const Scaffold(body: ClubCrestsSection()),
        ),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists every crest with its status, and the log', (tester) async {
    await _open(tester, _Server());

    expect(find.text('ظاهر 2 · مخفي 1 · محذوف 0'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('admin.crests.status.milan')))
          .data,
      'مخفي',
    );
    expect(
      find.text('السبب: شكوى النادي · الشاكي: legal@milan.example'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('admin.crests.show.milan')), findsOneWidget);
    expect(find.byKey(const Key('admin.crests.hide.arsenal')), findsOneWidget);
    expect(find.textContaining('أُخفي «milan»'), findsOneWidget);
  });

  testWidgets('hides a crest for a complaint, with its complainant', (
    tester,
  ) async {
    final server = _Server();
    await _open(tester, server);

    await _tap(tester, const Key('admin.crests.hide.arsenal'));
    await tester.enterText(
      find.byKey(const Key('admin.crests.hide.reason')),
      'طلب النادي',
    );
    await tester.enterText(
      find.byKey(const Key('admin.crests.hide.complainant')),
      'legal@arsenal.example',
    );
    await tester.pumpAndSettle();
    await _tap(tester, const Key('admin.crests.hide.ok'));

    expect(server.posts('arsenal').single, {
      'action': 'hide',
      'reason': 'طلب النادي',
      'complainant': 'legal@arsenal.example',
    });
    expect(find.text('أُخفي «arsenal»'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('admin.crests.status.arsenal')))
          .data,
      'مخفي',
    );
  });

  testWidgets('a hide without a reason sends nothing', (tester) async {
    final server = _Server();
    await _open(tester, server);

    await _tap(tester, const Key('admin.crests.hide.arsenal'));
    await _tap(tester, const Key('admin.crests.hide.ok'));
    await _tap(tester, const Key('admin.crests.hide.cancel'));

    expect(server.posts('arsenal'), isEmpty);
  });

  testWidgets('shows a hidden crest again', (tester) async {
    final server = _Server();
    await _open(tester, server);

    await _tap(tester, const Key('admin.crests.show.milan'));

    expect(server.posts('milan').single['action'], 'show');
    expect(
      tester
          .widget<Text>(find.byKey(const Key('admin.crests.status.milan')))
          .data,
      'ظاهر',
    );
  });

  testWidgets('a delete needs the name typed as it is', (tester) async {
    final server = _Server();
    await _open(tester, server);

    await _tap(tester, const Key('admin.crests.delete.chelsea'));
    await tester.enterText(
      find.byKey(const Key('admin.crests.delete.reason')),
      'طلب الحذف',
    );
    await tester.enterText(
      find.byKey(const Key('admin.crests.delete.confirm')),
      'chelse',
    );
    await tester.pumpAndSettle();
    await _tap(tester, const Key('admin.crests.delete.ok'));
    expect(server.posts('chelsea'), isEmpty);

    await tester.enterText(
      find.byKey(const Key('admin.crests.delete.confirm')),
      'chelsea',
    );
    await tester.pumpAndSettle();
    await _tap(tester, const Key('admin.crests.delete.ok'));

    expect(server.posts('chelsea').single, {
      'action': 'delete',
      'reason': 'طلب الحذف',
      'confirm': 'chelsea',
    });
    expect(find.byKey(const Key('admin.crests.delete.chelsea')), findsNothing);
  });

  testWidgets('switches every club crest off, with a reason', (tester) async {
    final server = _Server();
    await _open(tester, server);

    await _tap(tester, const Key('admin.crests.switch'));
    await tester.enterText(
      find.byKey(const Key('admin.crests.switch.reason')),
      'مراجعة',
    );
    await tester.pumpAndSettle();
    await _tap(tester, const Key('admin.crests.switch.ok'));

    final http.Request put = server.requests.singleWhere(
      (r) => r.method == 'PUT',
    );
    expect(jsonDecode(put.body), {'clubs_enabled': false, 'reason': 'مراجعة'});
    expect(
      find.text('متوقفة: تظهر دوائر بألوان الفرق في كل مكان'),
      findsOneWidget,
    );
  });

  testWidgets('the hidden filter shows the hidden crests alone', (
    tester,
  ) async {
    await _open(tester, _Server());

    await _tap(tester, const Key('admin.crests.filter.hidden'));

    expect(find.byKey(const Key('admin.crests.row.milan')), findsOneWidget);
    expect(find.byKey(const Key('admin.crests.row.arsenal')), findsNothing);
  });

  testWidgets('fits a 360px phone at text x2', (tester) async {
    await _open(tester, _Server(), height: 2340, textScale: 2.0);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('admin.crests.switch')), findsOneWidget);
  });
}
