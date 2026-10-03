/// The admin's error log through its real providers and the real `AdminApi`,
/// over the auth harness's fake server: the lists with their counts, an
/// error's page changing its status, the search by problem code, and the
/// report copied for the developer.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/screens/sections/error_log_section.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

const String _admin = '11111111-1111-4111-8111-111111111111';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

Map<String, Object?> _error({String status = 'new'}) => {
  'id': 7,
  'problem_code': 'K7Q2',
  'source': 'server',
  'error_type': 'AppError',
  'error_code': 'db.timeout',
  'message': 'Statement timed out',
  'location_file': 'routes/seasons/index.dart',
  'location_line': 40,
  'location_symbol': 'onRequest',
  'severity': 'critical',
  'status': status,
  'assignee_id': null,
  'assignee_name': null,
  'admin_notes': null,
  'first_build': 'abc1234',
  'last_build': 'abc1235',
  'first_seen_at': '2026-10-03T09:00:00.000Z',
  'last_seen_at': '2026-10-03T10:00:00.000Z',
  'occurrences': 100,
  'users_affected': 4,
  'reopened_count': 0,
};

final class _Server {
  final List<http.Request> requests = <http.Request>[];
  String status = 'new';

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final String path = request.url.path;
    if (path == '/admin/errors') {
      return _json({
        'schema_version': 1,
        'counts': {'all': 5, 'new': 2, 'recurring': 1, 'critical': 1},
        'errors': [_error(status: status)],
        'admins': [
          {'id': _admin, 'display_name': 'مشرف'},
        ],
      });
    }
    if (path == '/admin/error-releases') {
      return _json(const {
        'schema_version': 1,
        'releases': [
          {
            'build': 'abc1235',
            'errors': 3,
            'critical': 1,
            'occurrences': 120,
            'first_seen_at': '2026-10-03T09:00:00.000Z',
            'last_seen_at': '2026-10-03T10:00:00.000Z',
          },
        ],
        'files': [
          {
            'file': 'routes/seasons/index.dart',
            'errors': 1,
            'occurrences': 100,
          },
        ],
      });
    }
    if (path == '/admin/errors/7') {
      if (request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        status = (body['status'] as String?) ?? status;
      }
      return _json({
        'schema_version': 1,
        'error': _error(status: status),
        'samples': [
          {
            'occurred_at': '2026-10-03T10:00:00.000Z',
            'build': 'abc1235',
            'message': 'Statement timed out',
            'request_id': '0123456789abcdef0123456789abcdef',
            'route': 'GET /seasons/:id',
            'stack': '#0      onRequest (routes/seasons/index.dart:40:3)',
          },
        ],
        'builds': [
          {
            'build': 'abc1235',
            'occurrences': 100,
            'first_seen_at': '2026-10-03T09:00:00.000Z',
            'last_seen_at': '2026-10-03T10:00:00.000Z',
          },
        ],
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
        home: const Scaffold(body: ErrorLogSection()),
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
  testWidgets('shows each list with its count and the new errors', (
    tester,
  ) async {
    final server = _Server();
    await _open(tester, server);

    expect(find.text('جديد (2)'), findsOneWidget);
    expect(find.text('متكرر (1)'), findsOneWidget);
    expect(find.text('حرج (1)'), findsOneWidget);
    expect(find.text('الكل (5)'), findsOneWidget);
    expect(find.byKey(const Key('admin.errors.row.7')), findsOneWidget);
    expect(find.textContaining('K7Q2'), findsOneWidget);
    expect(server.to('/admin/errors').first.url.queryParameters['list'], 'new');
  });

  testWidgets('marks an error fixed, sending only what changed', (
    tester,
  ) async {
    final server = _Server();
    await _open(tester, server);

    await _tapVisible(tester, const Key('admin.errors.row.7'));
    expect(find.byKey(const Key('admin.errors.detail.7')), findsOneWidget);
    await _tapVisible(tester, const Key('admin.errors.status.fixed'));
    await _tapVisible(tester, const Key('admin.errors.save'));

    final http.Request sent = server
        .to('/admin/errors/7')
        .firstWhere((r) => r.method == 'POST');
    expect(jsonDecode(sent.body), {'status': 'fixed'});
    expect(find.text('تم الحفظ'), findsOneWidget);
  });

  testWidgets('finds an error by the code a player sent', (tester) async {
    final server = _Server();
    await _open(tester, server);

    await tester.enterText(
      find.byKey(const Key('admin.errors.codeField')),
      'k7q2',
    );
    await _tapVisible(tester, const Key('admin.errors.search'));

    expect(server.to('/admin/errors').last.url.queryParameters['code'], 'K7Q2');
    expect(find.text('نتائج الرمز K7Q2'), findsOneWidget);
    expect(find.byKey(const Key('admin.errors.row.7')), findsOneWidget);
  });

  testWidgets('summarises the errors of each release and file', (tester) async {
    await _open(tester, _Server());

    await tester.scrollUntilVisible(
      find.byKey(const Key('admin.errors.releases')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('ملخّص الإصدارات'), findsOneWidget);
    expect(
      find.byKey(const Key('admin.errors.release.abc1235')),
      findsOneWidget,
    );
    expect(find.textContaining('(1 حرج)'), findsOneWidget);
    expect(
      find.textContaining('routes/seasons/index.dart · 1 خطأ'),
      findsOneWidget,
    );
  });

  testWidgets('copies a ready report for the developer', (tester) async {
    final List<MethodCall> calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final server = _Server();
    await _open(tester, server);

    await _tapVisible(tester, const Key('admin.errors.row.7'));
    await _tapVisible(tester, const Key('admin.errors.copyReport'));

    final MethodCall copy = calls.firstWhere(
      (MethodCall c) => c.method == 'Clipboard.setData',
    );
    final String text =
        (copy.arguments as Map<Object?, Object?>)['text']! as String;
    expect(text, contains('K7Q2'));
    expect(text, contains('routes/seasons/index.dart:40'));
    expect(text, contains('0123456789abcdef0123456789abcdef'));
    expect(text, contains('#0      onRequest'));
  });
}
