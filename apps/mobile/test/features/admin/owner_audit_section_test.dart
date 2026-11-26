/// Script 347: «سجلي» on the owners' page through the real providers and the
/// real `AdminApi`, over the auth harness's fake server: the tab sits after
/// «سجل المشرفين», lists the lines of both sources (a line is told apart by
/// source and id together), reads a failure as an error with a retry, never as
/// an empty log, and an admin without a seat finds no tab and no request.
/// Also drawn at 360px with text x2.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/admin_shell.dart';
import 'package:mobile/features/admin/screens/sections/owner_audit_section.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

const String _fixtureId = '0b0b0b0b-0b0b-4b0b-8b0b-0b0b0b0b0b0b';

const AuthenticatedUserDto _owner = AuthenticatedUserDto(
  userId: 'u-owner-id',
  role: 'admin',
  status: 'active',
  email: 'owner@example.com',
  isOwner: true,
);

const AuthenticatedUserDto _otherAdmin = AuthenticatedUserDto(
  userId: 'u-admin',
  role: 'admin',
  status: 'active',
  email: 'suleiman@example.com',
);

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

// NK347_02
final class _Server {
  _Server({this.me = _owner, this.failFirst = 0, this.entries});

  final AuthenticatedUserDto me;

  /// How many answers to `/owner/audit` are a 503 before the real one.
  int failFirst;

  /// The lines to answer; the two sources with the same id when null.
  final List<Map<String, Object?>>? entries;

  final List<http.Request> requests = <http.Request>[];

  List<Map<String, Object?>> get _lines =>
      entries ??
      <Map<String, Object?>>[
        {
          'source': 'admin',
          'id': 5,
          'actor_name': 'عبدالرحمن',
          'method': 'PUT',
          'path': '/fixtures/$_fixtureId/result',
          'at': '2026-11-26T18:00:00.000Z',
          'target': 'A × B',
          'result': '2-1',
        },
        {
          'source': 'owner',
          'id': 5,
          'actor_name': 'عبدالرحمن',
          'method': 'PUT',
          'path': '/owner/switches/crowning',
          'at': '2026-11-26T17:00:00.000Z',
          'target': null,
          'result': null,
        },
      ];

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    if (request.url.path == '/owner/audit') {
      if (failFirst > 0) {
        failFirst--;
        return errorEnvelope(503, 'owner.audit_unavailable', 'unavailable');
      }
      return _json({'schema_version': 1, 'entries': _lines});
    }
    return okMe(me);
  }

  List<http.Request> toAudit() => [
    for (final r in requests)
      if (r.url.path == '/owner/audit') r,
  ];
}

Future<void> _open(
  WidgetTester tester,
  _Server server,
  Widget body, {
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
          child: Scaffold(body: body),
        ),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('a line reads in words, by the page or the tool it came from', () {
    OwnerAuditEntryDto line(String source, String method, String path) =>
        OwnerAuditEntryDto(
          source: source,
          id: 1,
          actorName: 'x',
          method: method,
          path: path,
          at: DateTime.utc(2026, 11, 26),
        );

    expect(
      ownerAuditLabel(line('owner', 'PUT', '/owner/switches/crowning')),
      'صفحة المالك: المفاتيح',
    );
    expect(
      ownerAuditLabel(line('admin', 'PUT', '/fixtures/$_fixtureId/result')),
      'تسجيل نتيجة مباراة',
    );
    expect(
      ownerAuditLabel(line('owner', 'POST', '/owner/new-thing')),
      contains('/owner/new-thing'),
    );
    expect(ownerAuditSourceLabel('owner'), 'صفحة المالك');
    expect(ownerAuditSourceLabel('admin'), 'أدوات المشرفين');
  });

  testWidgets('lists the lines of both sources, told apart by source', (
    tester,
  ) async {
    final server = _Server();
    await _open(tester, server, const OwnerAuditSection());

    expect(server.toAudit(), hasLength(1));
    expect(server.toAudit().single.method, 'GET');
    expect(find.byKey(const Key('owner.audit.list')), findsOneWidget);
    // The two lines share the id 5: only the source tells them apart.
    expect(find.byKey(const Key('owner.audit.item.admin.5')), findsOneWidget);
    expect(find.byKey(const Key('owner.audit.item.owner.5')), findsOneWidget);
    expect(find.text('تسجيل نتيجة مباراة'), findsOneWidget);
    expect(find.text('على: A × B · النتيجة الآن 2-1'), findsOneWidget);
    expect(find.text('صفحة المالك: المفاتيح'), findsOneWidget);
    expect(find.text('PUT /owner/switches/crowning'), findsOneWidget);
    expect(find.text('أدوات المشرفين'), findsOneWidget);
    expect(find.text('صفحة المالك'), findsOneWidget);
    expect(find.text('سجلي'), findsOneWidget);
    expect(find.byKey(const Key('owner.audit.empty')), findsNothing);
    expect(find.byKey(const Key('owner.audit.error')), findsNothing);
  });

  testWidgets('an empty log says so', (tester) async {
    await _open(
      tester,
      _Server(entries: <Map<String, Object?>>[]),
      const OwnerAuditSection(),
    );

    expect(find.byKey(const Key('owner.audit.empty')), findsOneWidget);
    expect(find.byKey(const Key('owner.audit.error')), findsNothing);
  });

  testWidgets('a failure is an error with a retry, never an empty log', (
    tester,
  ) async {
    final server = _Server(failFirst: 1);
    await _open(tester, server, const OwnerAuditSection());

    expect(find.byKey(const Key('owner.audit.error')), findsOneWidget);
    expect(find.byKey(const Key('owner.audit.empty')), findsNothing);
    expect(find.byKey(const Key('owner.audit.item.owner.5')), findsNothing);

    await tester.tap(find.byKey(const Key('owner.audit.retry')));
    await tester.pumpAndSettle();

    expect(server.toAudit(), hasLength(2));
    expect(find.byKey(const Key('owner.audit.error')), findsNothing);
    expect(find.byKey(const Key('owner.audit.item.owner.5')), findsOneWidget);
  });

  testWidgets('the owner page has the tab after «سجل المشرفين»', (
    tester,
  ) async {
    final server = _Server();
    await _open(tester, server, const OwnerGeneralSection());

    expect(find.text('سجل المشرفين'), findsOneWidget);
    expect(find.byKey(const Key('admin.owner.tab.3')), findsOneWidget);
    expect(find.byKey(const Key('admin.owner.tab.4')), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('admin.owner.tab.4')),
              matching: find.byType(Text),
            ),
          )
          .data,
      'سجلي',
    );
    expect(server.toAudit(), isEmpty);

    await tester.tap(find.byKey(const Key('admin.owner.tab.4')));
    await tester.pumpAndSettle();

    expect(server.toAudit(), isNotEmpty);
    expect(find.byKey(const Key('owner.audit.item.owner.5')), findsOneWidget);
  });

  testWidgets('an admin without a seat finds no tab and asks nothing', (
    tester,
  ) async {
    final server = _Server(me: _otherAdmin);
    await _open(tester, server, const OwnerGeneralSection());

    expect(find.byKey(const Key('admin.owner.none')), findsOneWidget);
    expect(find.text('سجلي'), findsNothing);
    expect(find.byKey(const Key('owner.audit.list')), findsNothing);
    expect(server.toAudit(), isEmpty);
  });

  testWidgets('fits a 360px phone at text x2', (tester) async {
    await _open(tester, _Server(), const OwnerAuditSection(), textScale: 2.0);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('owner.audit.item.owner.5')), findsOneWidget);
    expect(find.byKey(const Key('owner.audit.item.admin.5')), findsOneWidget);
  });
}
