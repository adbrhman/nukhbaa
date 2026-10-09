/// The admin's head-to-head page through its real provider and the real
/// `AdminApi`, over the auth harness's fake server: it draws the month, the
/// pilot button before the launch, the rounds and the days that may be
/// approved; approving, withdrawing and starting the pilot reach the server
/// with their values, and a refusal is read in Arabic.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/screens/sections/h2h_admin_section.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

/// October before the launch: not drawn, two days ahead (one of five
/// matches). November: drawn, round 1 started, round 2 not yet.
final class _Server {
  _Server({this.refuseApproval = false});

  final bool refuseApproval;
  final List<http.Request> requests = <http.Request>[];

  List<http.Request> sent(String method, String path) => <http.Request>[
    for (final http.Request r in requests)
      if (r.method == method && r.url.path == path) r,
  ];

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final String path = request.url.path;
    if (path == '/admin/h2h/rounds' && request.method == 'GET') {
      if (request.url.queryParameters['day'] == '2026-11-01') {
        return _json(const {
          'month_start': '2026-11-01',
          'starts_on': '2026-11-01',
          'drawn': true,
          'is_pilot': false,
          'rounds': [
            {
              'id': 'r-1',
              'round': 1,
              'day': '2026-11-01',
              'fixture_count': 8,
              'automatic': true,
              'locked': true,
            },
            {
              'id': 'r-2',
              'round': 2,
              'day': '2026-11-04',
              'fixture_count': 6,
              'automatic': false,
              'locked': false,
            },
          ],
          'candidates': <Object?>[],
        });
      }
      return _json(const {
        'month_start': '2026-10-01',
        'starts_on': '2026-11-01',
        'drawn': false,
        'is_pilot': false,
        'rounds': <Object?>[],
        'candidates': [
          {
            'day': '2026-10-24',
            'fixture_count': 9,
            'first_kickoff': '2026-10-24T12:00:00.000Z',
            'kind': 'regular',
          },
          {
            'day': '2026-10-25',
            'fixture_count': 5,
            'first_kickoff': '2026-10-25T15:00:00.000Z',
            'kind': 'fill',
          },
        ],
      });
    }
    if (path == '/admin/h2h/rounds' && request.method == 'POST') {
      if (refuseApproval) {
        return _json(const {
          'schema_version': 1,
          'code': 'h2h.round_day_started',
          'message': 'started',
        }, status: 409);
      }
      final Map<String, Object?> body =
          jsonDecode(request.body) as Map<String, Object?>;
      return _json({
        'id': 'r-new',
        'round': 1,
        'day': body['day'],
        'fixture_count': 5,
        'automatic': false,
        'locked': false,
      });
    }
    if (path.startsWith('/admin/h2h/rounds/') && request.method == 'DELETE') {
      return _json(const {'withdrawn': true});
    }
    if (path == '/admin/h2h/pilot') {
      return _json(const {'seated': 12});
    }
    return okMe(sampleUser);
  }
}

Future<void> _open(WidgetTester tester, _Server server) async {
  // Tall enough that the whole page is built at once.
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
}

void main() {
  test('nextMonthOf turns the year and refuses what is not a month', () {
    expect(nextMonthOf('2026-10-01'), '2026-11-01');
    expect(nextMonthOf('2026-12-01'), '2027-01-01');
    expect(nextMonthOf('2026-10-05'), isNull);
    expect(nextMonthOf(''), isNull);
  });

  testWidgets('before the launch: the month, the pilot and the days', (
    tester,
  ) async {
    await _open(tester, _Server());

    expect(find.text('أكتوبر 2026'), findsOneWidget);
    expect(find.text('القرعة: لم تُجرَ بعد'), findsOneWidget);
    expect(find.byKey(const Key('admin.h2h.pilot.start')), findsOneWidget);
    expect(find.byKey(const Key('admin.h2h.rounds.empty')), findsOneWidget);
    expect(
      find.byKey(const Key('admin.h2h.candidate.2026-10-24')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('admin.h2h.candidate.2026-10-25')),
        matching: find.textContaining('جولة تكميلية'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('approving a day sends that day', (tester) async {
    final _Server server = _Server();
    await _open(tester, server);

    await tester.tap(
      find.byKey(const Key('admin.h2h.candidate.2026-10-25.approve')),
    );
    await tester.pumpAndSettle();

    final List<http.Request> posts = server.sent('POST', '/admin/h2h/rounds');
    expect(posts, hasLength(1));
    expect(jsonDecode(posts.single.body), <String, Object?>{
      'day': '2026-10-25',
    });
    expect(find.text('اعتُمد 25 أكتوبر الجولة 1'), findsOneWidget);
  });

  testWidgets('a refused approval is read in Arabic', (tester) async {
    await _open(tester, _Server(refuseApproval: true));

    await tester.tap(
      find.byKey(const Key('admin.h2h.candidate.2026-10-24.approve')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('بدأت مباريات هذا اليوم، فلا يمكن اعتماده.'),
      findsOneWidget,
    );
  });

  testWidgets('the pilot starts only after the confirmation', (tester) async {
    final _Server server = _Server();
    await _open(tester, server);

    await tester.tap(find.byKey(const Key('admin.h2h.pilot.start')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.h2h.confirm.cancel')));
    await tester.pumpAndSettle();
    expect(server.sent('POST', '/admin/h2h/pilot'), isEmpty);

    await tester.tap(find.byKey(const Key('admin.h2h.pilot.start')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.h2h.confirm.ok')));
    await tester.pumpAndSettle();

    expect(server.sent('POST', '/admin/h2h/pilot'), hasLength(1));
    expect(find.text('بدأت التجربة: 12 لاعباً في القرعة'), findsOneWidget);
  });

  testWidgets('next month: only the last round, not started, is withdrawn', (
    tester,
  ) async {
    final _Server server = _Server();
    await _open(tester, server);

    await tester.tap(find.byKey(const Key('admin.h2h.month.next')));
    await tester.pumpAndSettle();

    expect(server.requests.last.url.queryParameters['day'], '2026-11-01');
    expect(find.text('القرعة: أُجريت'), findsOneWidget);
    expect(find.byKey(const Key('admin.h2h.pilot')), findsNothing);
    expect(find.byKey(const Key('admin.h2h.round.1.withdraw')), findsNothing);
    expect(find.byKey(const Key('admin.h2h.round.2.withdraw')), findsOneWidget);

    await tester.tap(find.byKey(const Key('admin.h2h.round.2.withdraw')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.h2h.confirm.ok')));
    await tester.pumpAndSettle();

    expect(server.sent('DELETE', '/admin/h2h/rounds/r-2'), hasLength(1));
    expect(find.text('سُحبت الجولة 2'), findsOneWidget);
  });
}
