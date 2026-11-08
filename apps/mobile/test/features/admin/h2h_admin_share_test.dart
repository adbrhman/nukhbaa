/// The admin's head-to-head pictures through the real section, its real
/// providers and the real `AdminApi`, over the auth harness's fake server
/// (2026-11-08): a round's real results in one picture, the round's player
/// matches of the four elite groups in one picture (never the extra
/// groups, never while the opponents are secret), and the standings of one
/// group or of the four.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/screens/sections/h2h_admin_section.dart';
import 'package:mobile/features/h2h/h2h_texts.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

Map<String, Object?> _standing(int rank, String id, String name, int points) =>
    <String, Object?>{
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
      'is_me': false,
    };

Map<String, Object?> _group(String id, int division, int index) =>
    <String, Object?>{
      'league_id': id,
      'division': division,
      'group_index': index,
      'capacity': 20,
      'promotion_zone': division == 1 ? 3 : 1,
      'relegation_zone': 0,
      'free_slots': const <int>[],
      'standings': <Object?>[
        _standing(1, '$id-a', 'سامي $id', 3),
        _standing(2, '$id-b', 'نورة $id', 0),
      ],
    };

/// November, drawn: round 1 of 8 November, the groups 1 and 2 of the elite
/// draw and the extra group 5.
final class _Server {
  _Server({this.secret = false});

  /// Group 2's round is still secret.
  final bool secret;
  final List<String> paths = <String>[];

  Future<http.Response> handle(http.Request request) async {
    final String path = request.url.path;
    paths.add(path);
    if (path == '/admin/h2h/rounds') {
      return _json(const {
        'month_start': '2026-11-01',
        'starts_on': '2026-11-01',
        'drawn': true,
        'is_pilot': false,
        'rounds': [
          {
            'id': 'r-1',
            'round': 1,
            'day': '2026-11-08',
            'fixture_count': 8,
            'automatic': true,
            'locked': true,
          },
        ],
        'candidates': <Object?>[],
      });
    }
    if (path == '/admin/h2h/groups') {
      return _json(<String, Object?>{
        'month_start': '2026-11-01',
        'drawn': true,
        'is_pilot': false,
        'seated_count': 6,
        'rounds': const [
          {
            'id': 'r-1',
            'round': 1,
            'day': '2026-11-08',
            'fixture_count': 8,
            'automatic': true,
            'locked': true,
          },
        ],
        'groups': [
          _group('g-1', 1, 0),
          _group('g-2', 1, 1),
          _group('g-5', 2, 0),
        ],
      });
    }
    final RegExpMatch? round = RegExp(
      r'^/admin/h2h/groups/(g-\d)/rounds/1$',
    ).firstMatch(path);
    if (round != null) {
      final String id = round.group(1)!;
      final bool hidden = secret && id == 'g-2';
      return _json(<String, Object?>{
        'round': 1,
        'day': '2026-11-08',
        'status': hidden ? 'live' : 'settled',
        'matches_hidden': hidden,
        'matches': hidden
            ? const <Object?>[]
            : <Object?>[
                <String, Object?>{
                  'home_user_id': '$id-a',
                  'home_name': 'سامي $id',
                  'home_points': 9,
                  'away_user_id': '$id-b',
                  'away_name': 'نورة $id',
                  'away_points': 4,
                  'winner': 'home',
                },
              ],
      });
    }
    if (path == '/feed/current-month-fixtures') {
      return _json(<Object?>[
        <String, Object?>{
          'schema_version': 3,
          'competition_id': 'c-1',
          'competition_name': 'الدوري الإنجليزي',
          'season_label': '11/2026',
          'fixture': <String, Object?>{
            'season_id': 's-1',
            'fixture_id': 'f-1',
            'home_team': 'Liverpool',
            'away_team': 'Brighton',
            'kickoff_at': '2026-11-08T12:00:00.000Z',
          },
          'result_home_goals': 2,
          'result_away_goals': 1,
        },
      ]);
    }
    if (path == '/teams') return _json(const <Object?>[]);
    return okMe(sampleUser);
  }
}

Future<_Server> _open(WidgetTester tester, {bool secret = false}) async {
  final _Server server = _Server(secret: secret);
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
  return server;
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a round: the real results in one picture', (tester) async {
    await _open(tester);

    await _tap(tester, 'admin.h2h.round.1.shareResults');

    expect(find.byKey(const Key('h2h.share.fixtures.card')), findsOneWidget);
    expect(find.text('نتائج مباريات الجولة 1'), findsOneWidget);
    expect(find.textContaining('انتهت 1 من 1'), findsOneWidget);
    expect(find.text('الدوري الإنجليزي'), findsOneWidget);

    await _tap(tester, 'h2h.share.fixtures.close');
    expect(find.byKey(const Key('h2h.share.fixtures.card')), findsNothing);
  });

  testWidgets('a round: the matches of the four elite groups, not the extra', (
    tester,
  ) async {
    final _Server server = await _open(tester);

    await _tap(tester, 'admin.h2h.round.1.shareMatchups');

    expect(find.byKey(const Key('h2h.share.matches.card')), findsOneWidget);
    expect(find.text('مواجهات الجولة 1'), findsOneWidget);
    expect(find.text('المجموعة 1'), findsOneWidget);
    expect(find.text('المجموعة 2'), findsOneWidget);
    expect(find.text('المجموعة 5'), findsNothing);
    expect(server.paths, contains('/admin/h2h/groups/g-1/rounds/1'));
    expect(server.paths, contains('/admin/h2h/groups/g-2/rounds/1'));
    expect(server.paths, isNot(contains('/admin/h2h/groups/g-5/rounds/1')));
  });

  testWidgets('a round whose opponents are secret draws no matches', (
    tester,
  ) async {
    await _open(tester, secret: true);

    await _tap(tester, 'admin.h2h.round.1.shareMatchups');

    expect(find.byKey(const Key('h2h.share.matches.card')), findsNothing);
    expect(find.text(h2hSecretPairs), findsOneWidget);
  });

  testWidgets('the groups: one group, or the four, as a standings picture', (
    tester,
  ) async {
    await _open(tester);
    await tester.tap(find.byKey(const Key('admin.h2h.tab.groups')));
    await tester.pumpAndSettle();

    await _tap(tester, 'admin.h2h.group.g-1.shareStandings');
    expect(find.byKey(const Key('h2h.share.standings.card')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('h2h.share.standings.card')),
        matching: find.text('المجموعة 1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('h2h.share.standings.card')),
        matching: find.text('المجموعة 2'),
      ),
      findsNothing,
    );
    await _tap(tester, 'h2h.share.standings.close');

    await _tap(tester, 'admin.h2h.groups.shareElite');
    for (final String title in <String>['المجموعة 1', 'المجموعة 2']) {
      expect(
        find.descendant(
          of: find.byKey(const Key('h2h.share.standings.card')),
          matching: find.text(title),
        ),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(
        of: find.byKey(const Key('h2h.share.standings.card')),
        matching: find.text('المجموعة 5'),
      ),
      findsNothing,
    );
  });

  testWidgets('the groups: the matches of one group as a picture', (
    tester,
  ) async {
    await _open(tester);
    await tester.tap(find.byKey(const Key('admin.h2h.tab.groups')));
    await tester.pumpAndSettle();
    await _tap(tester, 'admin.h2h.group.g-1.matches');

    await _tap(tester, 'admin.h2h.group.g-1.shareMatches.1');

    expect(find.byKey(const Key('h2h.share.matches.card')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('h2h.share.matches.card')),
        matching: find.text('سامي g-1'),
      ),
      findsOneWidget,
    );
  });
}
