/// ترتيب مجموعات النخبة الأربع للاعب (2026-11-08) عبر الشاشة الحقيقية و
/// `AuthApi` الحقيقي فوق خادم الاختبار: زر التبديل في قسم الترتيب، اختيار
/// المجموعة، الجدول بأعمدته، وصورة المشاركة لمجموعة أو للأربع.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/h2h/h2h_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

H2hStandingDto _line(int rank, String id, String name, {bool me = false}) =>
    H2hStandingDto(
      rank: rank,
      userId: id,
      displayName: name,
      played: 1,
      won: rank == 1 ? 1 : 0,
      drawn: 0,
      lost: rank == 1 ? 0 : 1,
      leaguePoints: rank == 1 ? 3 : 0,
      pointsFor: 10 - rank,
      exactCount: 0,
      form: <String>[rank == 1 ? 'win' : 'loss'],
      isMe: me,
    );

MyH2hLeagueDto _league(String monthStart) => MyH2hLeagueDto(
  state: 'open',
  monthStart: monthStart,
  startsOn: monthStart,
  isPilot: false,
  division: 1,
  groupIndex: 0,
  myRank: 1,
  promotionZone: 3,
  relegationZone: 0,
  standings: <H2hStandingDto>[_line(1, 'u-me', 'سامي', me: true)],
  rounds: const <H2hRoundViewDto>[],
);

/// أربع مجموعات؛ اللاعب (`u-me`) في الثالثة.
H2hAdminGroupsDto _elite({int groups = 4}) => H2hAdminGroupsDto(
  monthStart: '2026-11-01',
  drawn: true,
  isPilot: false,
  seatedCount: 80,
  rounds: const <H2hRoundDto>[],
  groups: <H2hAdminGroupDto>[
    for (var i = 0; i < groups; i++)
      H2hAdminGroupDto(
        leagueId: 'g-$i',
        division: 1,
        groupIndex: i,
        capacity: 20,
        promotionZone: 3,
        relegationZone: 0,
        standings: <H2hStandingDto>[
          _line(
            1,
            i == 2 ? 'u-me' : 'u-a$i',
            i == 2 ? 'سامي' : 'لاعب أ$i',
            me: i == 2,
          ),
          _line(2, 'u-b$i', 'لاعب ب$i'),
        ],
      ),
  ],
);

final class _Server {
  _Server(this.league, this.elite);

  final MyH2hLeagueDto league;
  final H2hAdminGroupsDto elite;
  final List<String> paths = <String>[];

  Future<http.Response> handle(http.Request request) async {
    paths.add(request.url.path);
    if (request.url.path == '/me/h2h-league') return _json(league.toJson());
    if (request.url.path == '/me/h2h-league/elite') {
      return _json(elite.toJson());
    }
    return http.Response('not found', 404);
  }
}

Future<_Server> _open(
  WidgetTester tester, {
  String monthStart = '2026-11-01',
  H2hAdminGroupsDto? elite,
}) async {
  final _Server server = _Server(_league(monthStart), elite ?? _elite());
  final AuthHarness harness = buildAuthHarness(server.handle, seedToken: 'jwt');
  addTearDown(harness.dispose);
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const H2hScreen(initialSection: 1),
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

String? _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data;

void main() {
  testWidgets('my group first; the elite groups are one tap away', (
    tester,
  ) async {
    final _Server server = await _open(tester);

    expect(find.byKey(const Key('h2h.tableView')), findsOneWidget);
    expect(find.byKey(const Key('h2h.table.title')), findsOneWidget);
    expect(find.byKey(const Key('h2h.elite')), findsNothing);
    // Nothing is fetched until the player asks.
    expect(server.paths, isNot(contains('/me/h2h-league/elite')));

    await _tap(tester, 'h2h.tableView.1');

    expect(server.paths, contains('/me/h2h-league/elite'));
    expect(find.byKey(const Key('h2h.elite')), findsOneWidget);
    expect(find.byKey(const Key('h2h.table.title')), findsNothing);
  });

  testWidgets('it opens on my group, and any of the four can be picked', (
    tester,
  ) async {
    await _open(tester);
    await _tap(tester, 'h2h.tableView.1');

    expect(_text(tester, 'h2h.elite.title'), 'المجموعة 3');
    expect(find.byKey(const Key('h2h.elite.mine')), findsOneWidget);
    expect(
      find.byKey(const Key('h2h.elite.table.u-me.points')),
      findsOneWidget,
    );

    await _tap(tester, 'h2h.elite.group.0');

    expect(_text(tester, 'h2h.elite.title'), 'المجموعة 1');
    expect(find.byKey(const Key('h2h.elite.mine')), findsNothing);
    expect(find.text('لاعب أ0'), findsOneWidget);
    expect(find.byKey(const Key('h2h.elite.table.u-me.points')), findsNothing);
  });

  testWidgets('the table names its columns', (tester) async {
    await _open(tester);
    await _tap(tester, 'h2h.tableView.1');

    expect(find.byKey(const Key('h2h.elite.table.compact')), findsOneWidget);
    expect(find.text('فوز'), findsOneWidget);
    expect(find.text('تعادل'), findsOneWidget);
    expect(find.text('خسارة'), findsOneWidget);
    expect(find.byKey(const Key('h2h.elite.table.note')), findsOneWidget);
  });

  testWidgets('one group as a share picture, then the four', (tester) async {
    await _open(tester);
    await _tap(tester, 'h2h.tableView.1');

    await _tap(tester, 'h2h.elite.shareGroup');
    expect(find.byKey(const Key('h2h.share.standings.card')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('h2h.share.standings.card')),
        matching: find.text('المجموعة 3'),
      ),
      findsOneWidget,
    );
    await _tap(tester, 'h2h.share.standings.close');

    await _tap(tester, 'h2h.elite.shareAll');
    for (final String title in <String>[
      'المجموعة 1',
      'المجموعة 2',
      'المجموعة 3',
      'المجموعة 4',
    ]) {
      expect(
        find.descendant(
          of: find.byKey(const Key('h2h.share.standings.card')),
          matching: find.text(title),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('before the draw there is nothing to show', (tester) async {
    await _open(tester, elite: _elite(groups: 0));
    await _tap(tester, 'h2h.tableView.1');

    expect(find.byKey(const Key('h2h.elite.empty')), findsOneWidget);
    expect(find.byKey(const Key('h2h.elite.shareAll')), findsNothing);
  });

  testWidgets('a month before the elite draw has no switch', (tester) async {
    await _open(tester, monthStart: '2026-10-01');

    expect(find.byKey(const Key('h2h.tableView')), findsNothing);
    expect(find.byKey(const Key('h2h.table.title')), findsOneWidget);
  });
}
