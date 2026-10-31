/// The admin's tab "الصعود والهبوط" (batch 184) through the real section, its
/// real provider and the real `AdminApi`, over the auth harness's fake
/// server: the month's state, the absent players, the rounds and the
/// substitutes; a manual relegation and an excused round reach the server
/// with their reason, and a refusal is read in Arabic.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/screens/sections/h2h_admin_absence_tab.dart';
import 'package:mobile/features/admin/screens/sections/h2h_admin_section.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

const Map<String, Object?> _facts = <String, Object?>{
  'missed': 2,
  'points': 40,
  'exact': 3,
  'active_days': 19,
};

/// November, drawn: round 1 and 2 counted, round 3 not started; Salem is
/// absent from both and was warned; one substitute waits; one swap was made.
final class _Server {
  _Server({this.refuseRelegation = false});

  final bool refuseRelegation;
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
        'month_start': '2026-11-01',
        'starts_on': '2026-11-01',
        'drawn': true,
        'is_pilot': false,
        'rounds': <Object?>[],
        'candidates': <Object?>[],
      });
    }
    if (path == '/admin/h2h/absence' && method == 'GET') {
      return _json(const {
        'month_start': '2026-11-01',
        'active': true,
        'next_round': 3,
        'relegates_at': '2026-11-05T14:00:00.000Z',
        'rounds': <Object?>[
          {
            'round_id': 'r-1',
            'round': 1,
            'day': '2026-11-01',
            'locked': true,
            'counted': true,
            'absent': 1,
          },
          {
            'round_id': 'r-2',
            'round': 2,
            'day': '2026-11-02',
            'locked': true,
            'counted': false,
            'absent': 0,
            'excused_reason': 'تعطل النظام',
          },
          {
            'round_id': 'r-3',
            'round': 3,
            'day': '2026-11-05',
            'locked': false,
            'counted': false,
            'absent': 0,
          },
        ],
        'watch': <Object?>[
          {
            'player': {'user_id': 'u-1', 'display_name': 'سالم'},
            'group': 2,
            'absent_rounds': <int>[1, 4],
            'warned': true,
          },
        ],
        'candidates': <Object?>[
          {
            'player': {'user_id': 'u-5', 'display_name': 'صالح'},
            'group': 5,
            'facts': _facts,
          },
        ],
        'moves': <Object?>[
          {
            'id': 'm-1',
            'kind': 'admin',
            'from_round': 4,
            'out': {'user_id': 'u-2', 'display_name': 'ناصر'},
            'in': {'user_id': 'u-6', 'display_name': 'فهد'},
            'elite_group': 3,
            'extra_group': 6,
            'absent_rounds': <int>[],
            'created_at': '2026-11-04T14:00:00.000Z',
            'reason': 'تلاعب',
            'decided_by': {'user_id': 'a-1', 'display_name': 'المشرف'},
          },
        ],
      });
    }
    if (path == '/admin/h2h/relegations' && method == 'POST') {
      if (refuseRelegation) {
        return _json(const {
          'schema_version': 1,
          'code': 'h2h.no_substitute',
          'message': 'none',
        }, status: 409);
      }
      return _json(const {
        'moved': true,
        'from_round': 3,
        'in_user_id': 'u-5',
      }, status: 201);
    }
    if (path == '/admin/h2h/excusals' && method == 'POST') {
      return _json(const {'changed': true}, status: 201);
    }
    return _json(const {
      'schema_version': 1,
      'code': 'not_found',
      'message': 'no',
    }, status: 404);
  }
}

Future<void> _open(WidgetTester tester, _Server server) async {
  // Tall enough that the whole page is built at once.
  tester.view.physicalSize = const Size(1080, 9000);
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
  await tester.tap(find.byKey(const Key('admin.h2h.tab.absence')));
  await tester.pumpAndSettle();
}

void main() {
  test('the words of the tab', () {
    expect(h2hSeatMoveKindLabel('admin'), 'هبوط يدوي من المشرف');
    expect(h2hSeatMoveKindLabel('absence'), 'هبوط بالغياب');
    expect(h2hAbsentRoundsLabel(const <int>[]), '');
    expect(h2hAbsentRoundsLabel(const <int>[3]), 'الجولة 3');
    expect(h2hAbsentRoundsLabel(const <int>[2, 3, 4]), 'الجولات 2 و3 و4');
  });

  testWidgets('the month, the absent, the rounds, the substitutes and '
      'the swaps', (tester) async {
    final _Server server = _Server();
    await _open(tester, server);

    expect(server.sent('GET', '/admin/h2h/absence'), hasLength(1));
    expect(find.byKey(const Key('admin.h2h.absence.status')), findsOneWidget);
    expect(
      find.textContaining('يعمل في مجموعات النخبة 1 إلى 4'),
      findsOneWidget,
    );
    expect(find.text('الجولة التالية: 3'), findsOneWidget);
    expect(find.byKey(const Key('admin.h2h.absence.at')), findsOneWidget);

    expect(
      find.byKey(const Key('admin.h2h.absence.watch.u-1')),
      findsOneWidget,
    );
    expect(find.text('سالم'), findsOneWidget);
    expect(
      find.textContaining('المجموعة 2 · غاب عن الجولات 1 و4 · أُرسل له تنبيه'),
      findsOneWidget,
    );

    expect(find.text('محتسبة · غائبون: 1'), findsOneWidget);
    expect(find.text('معفاة: تعطل النظام'), findsOneWidget);
    expect(find.text('لم تبدأ بعد'), findsOneWidget);
    // Only a started round that is not excused can be excused.
    expect(
      find.byKey(const Key('admin.h2h.absence.round.r-1.excuse')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('admin.h2h.absence.round.r-2.excuse')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('admin.h2h.absence.round.r-3.excuse')),
      findsNothing,
    );

    expect(find.text('1. صالح'), findsOneWidget);
    expect(
      find.textContaining('فاته 2 · 40 نقطة · 3 دقيقة · 19 يوم نشاط'),
      findsOneWidget,
    );

    expect(find.text('ناصر ← فهد'), findsOneWidget);
    expect(
      find.textContaining('هبوط يدوي من المشرف · من الجولة 4'),
      findsOneWidget,
    );
    expect(find.text('السبب: تلاعب'), findsOneWidget);
  });

  testWidgets('a manual relegation needs a reason and sends it', (
    tester,
  ) async {
    final _Server server = _Server();
    await _open(tester, server);

    await tester.tap(
      find.byKey(const Key('admin.h2h.absence.watch.u-1.relegate')),
    );
    await tester.pumpAndSettle();

    // The action waits for a reason.
    FilledButton ok() => tester.widget<FilledButton>(
      find.byKey(const Key('admin.h2h.absence.reason.ok')),
    );
    expect(ok().onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('admin.h2h.absence.reason')),
      'تلاعب',
    );
    await tester.pumpAndSettle();
    expect(ok().onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('admin.h2h.absence.reason.ok')));
    await tester.pumpAndSettle();

    final List<http.Request> posts = server.sent(
      'POST',
      '/admin/h2h/relegations',
    );
    expect(posts, hasLength(1));
    expect(jsonDecode(posts.single.body), <String, Object?>{
      'user_id': 'u-1',
      'reason': 'تلاعب',
    });
    expect(find.text('هبط سالم، والتبديل من الجولة 3'), findsOneWidget);
    // The page reads the state again.
    expect(server.sent('GET', '/admin/h2h/absence'), hasLength(2));
  });

  testWidgets('cancelling the reason sends nothing', (tester) async {
    final _Server server = _Server();
    await _open(tester, server);

    await tester.tap(
      find.byKey(const Key('admin.h2h.absence.watch.u-1.relegate')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.h2h.absence.reason.cancel')));
    await tester.pumpAndSettle();

    expect(server.sent('POST', '/admin/h2h/relegations'), isEmpty);
  });

  testWidgets('a refused relegation is read in Arabic', (tester) async {
    await _open(tester, _Server(refuseRelegation: true));

    await tester.tap(
      find.byKey(const Key('admin.h2h.absence.watch.u-1.relegate')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin.h2h.absence.reason')),
      'تلاعب',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.h2h.absence.reason.ok')));
    await tester.pumpAndSettle();

    expect(find.textContaining('لا بديل مستوفٍ للشروط الآن'), findsOneWidget);
  });

  testWidgets('an excused round is sent with its reason', (tester) async {
    final _Server server = _Server();
    await _open(tester, server);

    await tester.tap(
      find.byKey(const Key('admin.h2h.absence.round.r-1.excuse')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin.h2h.absence.reason')),
      'تعطل النظام',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.h2h.absence.reason.ok')));
    await tester.pumpAndSettle();

    final List<http.Request> posts = server.sent('POST', '/admin/h2h/excusals');
    expect(posts, hasLength(1));
    expect(jsonDecode(posts.single.body), <String, Object?>{
      'round_id': 'r-1',
      'reason': 'تعطل النظام',
    });
    expect(find.text('أُعفيت الجولة 1 من حساب الغياب'), findsOneWidget);
  });
}
