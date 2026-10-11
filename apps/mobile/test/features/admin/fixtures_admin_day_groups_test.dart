/// The admin's matches page groups the month's fixtures by Riyadh day
/// (requested 2026-10-11): one header per day, newest day first, each over
/// its own matches with their count -- through the real section, its real
/// providers and `CompetitionApi`, over the auth harness's fake server. A
/// kickoff at 00:30 Riyadh belongs to the next day, as on the matches tab.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/admin/screens/sections/fixtures_admin_section.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

const String _early = '11111111-1111-4111-8111-111111111111';
const String _evening = '22222222-2222-4222-8222-222222222222';
const String _pastMidnight = '33333333-3333-4333-8333-333333333333';
const String _dayBefore = '44444444-4444-4444-8444-444444444444';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

Map<String, Object?> _fixture(String id, String kickoffUtc) =>
    <String, Object?>{
      'schema_version': 1,
      'season_id': 'm-10',
      'fixture_id': id,
      'home_team': 'Home $id',
      'away_team': 'Away $id',
      'kickoff_at': kickoffUtc,
    };

Future<http.Response> _handle(http.Request request) async {
  final String path = request.url.path;
  if (path == '/months') {
    return _json(<Object?>[
      <String, Object?>{
        'id': 'm-10',
        'competition_id': 'c-1',
        'label': '10/2026',
        'start_at': '2026-09-30T21:00:00Z',
        'end_at': '2026-10-31T21:00:00Z',
      },
    ]);
  }
  if (path == '/seasons/m-10/fixtures') {
    return _json(<Object?>[
      // 16:45 and 19:00 Riyadh on the 12th.
      _fixture(_early, '2026-10-12T13:45:00Z'),
      _fixture(_evening, '2026-10-12T16:00:00Z'),
      // 00:30 Riyadh on the 13th, though still the 12th in UTC.
      _fixture(_pastMidnight, '2026-10-12T21:30:00Z'),
      _fixture(_dayBefore, '2026-10-11T18:00:00Z'),
    ]);
  }
  return okMe(sampleUser);
}

Future<void> _open(WidgetTester tester) async {
  // Tall enough that every row and header is built at once.
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final harness = buildAuthHarness(_handle, seedToken: 'admin-jwt');
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        home: const Scaffold(body: FixturesAdminSection()),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _row(String id) => find.byKey(Key('admin.matches.row.$id'));

Finder _day(String key) => find.byKey(Key('admin.matches.day.$key'));

double _top(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

void main() {
  testWidgets('one header per Riyadh day, newest first, over its own '
      'matches', (tester) async {
    await _open(tester);

    // The last row is built before anything is checked as missing.
    expect(_row(_dayBefore), findsOneWidget);
    expect(_day('2026-10-13'), findsOneWidget);
    expect(_day('2026-10-12'), findsOneWidget);
    expect(_day('2026-10-11'), findsOneWidget);
    expect(_day('none'), findsNothing);

    final double day13 = _top(tester, _day('2026-10-13'));
    final double day12 = _top(tester, _day('2026-10-12'));
    final double day11 = _top(tester, _day('2026-10-11'));
    expect(day13, lessThan(_top(tester, _row(_pastMidnight))));
    expect(_top(tester, _row(_pastMidnight)), lessThan(day12));
    expect(day12, lessThan(_top(tester, _row(_evening))));
    expect(day12, lessThan(_top(tester, _row(_early))));
    expect(_top(tester, _row(_early)), lessThan(day11));
    expect(_top(tester, _row(_evening)), lessThan(day11));
    expect(day11, lessThan(_top(tester, _row(_dayBefore))));

    expect(
      find.descendant(of: _day('2026-10-12'), matching: find.text('2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _day('2026-10-13'), matching: find.text('1')),
      findsOneWidget,
    );
  });

  test('the day of a fixture is its Riyadh day', () {
    expect(adminFixtureDayKey(null), 'none');
    expect(
      adminFixtureDayKey(adminFixtureDayOf(_card('2026-10-12T21:30:00Z'))),
      '2026-10-13',
    );
    expect(
      adminFixtureDayKey(adminFixtureDayOf(_card('2026-10-12T20:59:00Z'))),
      '2026-10-12',
    );
    expect(adminFixtureDayOf(_card(null)), isNull);
  });
}

SeasonFixtureCardDto _card(String? kickoffUtc) => SeasonFixtureCardDto(
  seasonId: 'm-10',
  fixtureId: _early,
  homeTeam: 'Home',
  awayTeam: 'Away',
  kickoffAt: kickoffUtc,
);
