/// The admin's head-to-head dashboard (batch 93) through the real section,
/// its real providers and the real `AdminApi`, over the auth harness's fake
/// server: the tabs, the groups with their tables and matches, a late seat,
/// one player's month, the settings, the days kept from automatic approval,
/// a manual run of the jobs, and the report with the admin log. Every
/// choice reaches the server with its values; a refusal is read in Arabic.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/screens/sections/h2h_admin_section.dart';
import 'package:mobile/features/admin/screens/sections/h2h_admin_tabs.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

Map<String, Object?> _standing(
  int rank,
  String id,
  String name,
  int points, {
  bool isMe = false,
}) => <String, Object?>{
  'rank': rank,
  'user_id': id,
  'display_name': name,
  'played': 1,
  'won': points == 3 ? 1 : 0,
  'drawn': 0,
  'lost': points == 3 ? 0 : 1,
  'league_points': points,
  'points_for': 10 - rank,
  'exact_count': 0,
  'form': <String>[if (points == 3) 'win' else 'loss'],
  'is_me': isMe,
};

/// November, drawn: one second-division group of four seats with seat 3
/// empty; round 1 settled.
final class _Server {
  _Server({this.refuseSeat = false});

  final bool refuseSeat;
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
    if (path == '/admin/h2h/groups' && method == 'GET') {
      return _json(<String, Object?>{
        'month_start': '2026-11-01',
        'drawn': true,
        'is_pilot': false,
        'seated_count': 3,
        'rounds': const [
          {
            'id': 'r-1',
            'round': 1,
            'day': '2026-11-01',
            'fixture_count': 8,
            'automatic': true,
            'locked': true,
          },
        ],
        'groups': [
          <String, Object?>{
            'league_id': 'g-1',
            'division': 2,
            'group_index': 0,
            'capacity': 4,
            'promotion_zone': 1,
            'relegation_zone': 1,
            'free_slots': const [3],
            'standings': [
              _standing(1, 'u-1', 'سامي', 3),
              _standing(2, 'u-3', 'خالد', 3),
              _standing(3, 'u-2', 'علي', 0),
            ],
          },
        ],
      });
    }
    if (path == '/admin/h2h/groups/g-1/rounds/1' && method == 'GET') {
      return _json(const {
        'round': 1,
        'day': '2026-11-01',
        'status': 'settled',
        'matches': [
          {
            'home_user_id': 'u-1',
            'home_name': 'سامي',
            'home_points': 9,
            'away_user_id': null,
            'away_name': null,
            'away_points': 6.3,
            'winner': 'home',
          },
          {
            'home_user_id': 'u-2',
            'home_name': 'علي',
            'home_points': 4,
            'away_user_id': 'u-3',
            'away_name': 'خالد',
            'away_points': 6,
            'winner': 'away',
          },
        ],
      });
    }
    if (path == '/admin/users' && method == 'GET') {
      return _json(const {
        'users': [
          {
            'id': 'u-9',
            'status': 'active',
            'email': 'late@example.com',
            'display_name': 'متأخر',
          },
        ],
      });
    }
    if (path == '/admin/h2h/seats' && method == 'POST') {
      if (refuseSeat) {
        return _json(const {
          'schema_version': 1,
          'code': 'h2h.seat_taken',
          'message': 'taken',
        }, status: 409);
      }
      return _json(const {'seated': true}, status: 201);
    }
    if (path == '/admin/h2h/players/u-9' && method == 'GET') {
      return _json(<String, Object?>{
        'state': 'open',
        'month_start': '2026-11-01',
        'starts_on': '2026-11-01',
        'is_pilot': false,
        'division': 2,
        'group_index': 0,
        'days_left': 20,
        'my_rank': 2,
        'promotion_zone': 1,
        'relegation_zone': 1,
        'standings': [
          _standing(1, 'u-1', 'سامي', 3),
          _standing(2, 'u-9', 'متأخر', 0, isMe: true),
        ],
        'rounds': const [
          {
            'round': 1,
            'day': '2026-11-01',
            'status': 'settled',
            'fixture_count': 8,
            'opponent_user_id': 'u-1',
            'opponent_name': 'سامي',
            'my_points': 4,
            'opponent_points': 9.0,
            'result': 'loss',
          },
        ],
      });
    }
    if (path == '/admin/h2h/controls' && method == 'GET') {
      return _json(const {
        'month_start': '2026-11-01',
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
        'days': [
          {
            'day': '2026-11-12',
            'fixture_count': 7,
            'excluded': false,
            'first_kickoff': '2026-11-12T12:00:00.000Z',
            'round': 2,
          },
          {
            'day': '2026-11-14',
            'fixture_count': 6,
            'excluded': false,
            'first_kickoff': '2026-11-14T12:00:00.000Z',
            'round': null,
          },
        ],
        'actions': [
          {
            'id': 'a-1',
            'action': 'seat_added',
            'detail': {'slot': 3, 'day': '2026-11-10'},
            'acted_at': '2026-11-10T10:00:00.000Z',
            'actor_id': 'adm',
            'actor_name': 'المشرف',
          },
        ],
      });
    }
    if (path == '/admin/h2h/settings' && method == 'PUT') {
      final Map<String, Object?> body =
          jsonDecode(request.body) as Map<String, Object?>;
      return _json(<String, Object?>{...body, 'updated_by_name': 'المشرف'});
    }
    if (path == '/admin/h2h/exclusions' && method == 'POST') {
      return _json(const {'changed': true});
    }
    if (path == '/admin/h2h/jobs' && method == 'POST') {
      return _json(const {
        'approved': 1,
        'locked': 0,
        'closed_months': 0,
        'drawn_seats': 0,
      });
    }
    if (path == '/admin/h2h/report' && method == 'GET') {
      return _json(const {
        'month_start': '2026-11-01',
        'drawn': true,
        'is_pilot': false,
        'drawn_seats': 3,
        'seats': 4,
        'groups_by_division': {'2': 1},
        'closed': false,
        'closed_members': 0,
        'outcomes': <String, Object?>{},
        'drawn_at': '2026-10-31T21:05:00.000Z',
        'closed_at': null,
      });
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

Future<void> _tab(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(Key('admin.h2h.tab.$name')));
  await tester.pumpAndSettle();
}

void main() {
  test('the log and the report speak Arabic', () {
    expect(h2hAdminActionLabel('jobs_run'), 'تشغيل مهام الدوري');
    expect(h2hAdminActionLabel('something_new'), 'something_new');
    expect(
      h2hAdminActionDetail(const {'day': '2026-11-12', 'round': 3}),
      '12 نوفمبر · الجولة 3',
    );
    expect(h2hAdminActionDetail(const {'slot': 0}), 'المقعد 1');
    expect(h2hAdminActionDetail(const <String, Object?>{}), '');
    expect(h2hOutcomeLabel('out'), 'خارج القرعة القادمة');
    expect(h2hAdminStateLabel('not_in_draw'), 'ليس في قرعة هذا الشهر');
  });

  testWidgets('five tabs; the rounds open first', (tester) async {
    await _open(tester, _Server());

    for (final String name in <String>[
      'rounds',
      'groups',
      'player',
      'controls',
      'report',
    ]) {
      expect(find.byKey(Key('admin.h2h.tab.$name')), findsOneWidget);
    }
    expect(find.byKey(const Key('admin.h2h.list')), findsOneWidget);
    expect(find.byKey(const Key('admin.h2h.month.next')), findsOneWidget);
  });

  testWidgets('the groups: the table, the empty seats and the matches', (
    tester,
  ) async {
    final _Server server = _Server();
    await _open(tester, server);
    await _tab(tester, 'groups');

    expect(find.byKey(const Key('admin.h2h.group.g-1')), findsOneWidget);
    expect(find.text('الدرجة الثانية · المجموعة 1'), findsOneWidget);
    expect(find.textContaining('1 مقاعد شاغرة'), findsWidgets);
    expect(find.text('1. سامي'), findsOneWidget);
    expect(find.text('3. علي'), findsOneWidget);

    await tester.tap(find.byKey(const Key('admin.h2h.group.g-1.matches')));
    await tester.pumpAndSettle();

    expect(server.sent('GET', '/admin/h2h/groups/g-1/rounds/1'), hasLength(1));
    expect(
      find.text('سامي 9 × 6.3 متوسط المجموعة · يتقدم الأول'),
      findsOneWidget,
    );
    expect(find.text('علي 4 × 6 خالد · يتقدم الثاني'), findsOneWidget);
  });

  testWidgets('a late player is found and seated in the empty seat', (
    tester,
  ) async {
    final _Server server = _Server();
    await _open(tester, server);
    await _tab(tester, 'groups');

    await tester.tap(find.byKey(const Key('admin.h2h.group.g-1.seat')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin.h2h.seat.search')),
      'late',
    );
    await tester.tap(find.byKey(const Key('admin.h2h.seat.find')));
    await tester.pumpAndSettle();
    expect(
      server.sent('GET', '/admin/users').single.url.queryParameters['search'],
      'late',
    );

    await tester.tap(find.byKey(const Key('admin.h2h.seat.user.u-9')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.h2h.seat.add')));
    await tester.pumpAndSettle();

    final List<http.Request> posts = server.sent('POST', '/admin/h2h/seats');
    expect(posts, hasLength(1));
    expect(jsonDecode(posts.single.body), <String, Object?>{
      'league_id': 'g-1',
      'user_id': 'u-9',
      'slot': 3,
    });
    expect(find.text('أُضيف متأخر في المقعد 4'), findsOneWidget);
  });

  testWidgets('a refused seat is read in Arabic and the dialog stays', (
    tester,
  ) async {
    await _open(tester, _Server(refuseSeat: true));
    await _tab(tester, 'groups');

    await tester.tap(find.byKey(const Key('admin.h2h.group.g-1.seat')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin.h2h.seat.search')),
      'late',
    );
    await tester.tap(find.byKey(const Key('admin.h2h.seat.find')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.h2h.seat.user.u-9')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.h2h.seat.add')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('admin.h2h.seat.error')), findsOneWidget);
    expect(find.text('هذا المقعد مشغول. اختر مقعداً آخر.'), findsOneWidget);
  });

  testWidgets("one player's month, found by name", (tester) async {
    final _Server server = _Server();
    await _open(tester, server);
    await _tab(tester, 'player');

    expect(find.byKey(const Key('admin.h2h.month.next')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('admin.h2h.player.search')),
      'late',
    );
    await tester.tap(find.byKey(const Key('admin.h2h.player.find')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.h2h.player.user.u-9')));
    await tester.pumpAndSettle();

    expect(server.sent('GET', '/admin/h2h/players/u-9'), hasLength(1));
    expect(find.text('يلعب هذا الشهر'), findsOneWidget);
    expect(find.text('المركز 2 من 2'), findsOneWidget);
    expect(
      find.text('الجولة 1 · 1 نوفمبر · مكتملة · سامي · 4 - 9 · خسارة'),
      findsOneWidget,
    );
  });

  testWidgets('the settings are sent as the admin set them', (tester) async {
    final _Server server = _Server();
    await _open(tester, server);
    await _tab(tester, 'controls');

    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('admin.h2h.settings.lead.inc')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('admin.h2h.settings.lead.dec')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('admin.h2h.settings.days.dec')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('admin.h2h.settings.auto')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('admin.h2h.settings.save')));
    await tester.pumpAndSettle();

    final List<http.Request> puts = server.sent('PUT', '/admin/h2h/settings');
    expect(puts, hasLength(1));
    expect(jsonDecode(puts.single.body), <String, Object?>{
      'auto_approve': false,
      'lead_hours': 23,
      'min_active_days': 4,
    });
    expect(find.text('حُفظت الإعدادات'), findsOneWidget);
  });

  testWidgets('a day is kept from automatic approval; a round day is not '
      'offered', (tester) async {
    final _Server server = _Server();
    await _open(tester, server);
    await _tab(tester, 'controls');

    expect(
      find.byKey(const Key('admin.h2h.day.2026-11-12.auto')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('admin.h2h.day.2026-11-14.auto')));
    await tester.pumpAndSettle();

    final List<http.Request> posts = server.sent(
      'POST',
      '/admin/h2h/exclusions',
    );
    expect(posts, hasLength(1));
    expect(jsonDecode(posts.single.body), <String, Object?>{
      'day': '2026-11-14',
      'excluded': true,
    });
    expect(find.text('استُبعد 14 نوفمبر من الاعتماد التلقائي'), findsOneWidget);
  });

  testWidgets('the jobs run only after the confirmation', (tester) async {
    final _Server server = _Server();
    await _open(tester, server);
    await _tab(tester, 'controls');

    await tester.tap(find.byKey(const Key('admin.h2h.jobs.run')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.h2h.confirm.cancel')));
    await tester.pumpAndSettle();
    expect(server.sent('POST', '/admin/h2h/jobs'), isEmpty);

    await tester.tap(find.byKey(const Key('admin.h2h.jobs.run')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin.h2h.confirm.ok')));
    await tester.pumpAndSettle();

    expect(server.sent('POST', '/admin/h2h/jobs'), hasLength(1));
    expect(
      find.text('اعتُمدت 1 · جُمّدت 0 · أُغلق 0 شهر · مقاعد القرعة 0'),
      findsOneWidget,
    );
  });

  testWidgets('the report and the admin log', (tester) async {
    await _open(tester, _Server());
    await _tab(tester, 'report');

    expect(find.text('مقاعد القرعة: 3 · المقاعد الآن: 4'), findsOneWidget);
    expect(find.text('المجموعات: الدرجة الثانية: 1'), findsOneWidget);
    expect(find.text('الإغلاق: لم يُغلق الشهر بعد'), findsOneWidget);
    expect(find.text('إضافة لاعب متأخر'), findsOneWidget);
    expect(find.text('10 نوفمبر · المقعد 4'), findsOneWidget);
  });
}
