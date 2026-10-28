/// What a screen reader hears on the real matches screen, through the real
/// card and a fake server (Accessibility Scanner, 2026-10-28): every
/// control named once, never its label read twice, and the controls every
/// card repeats (steppers, double, share, details) named with the side or
/// the match they act on.
library;

import 'dart:ui' show Tristate;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/competition/team_registry.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

const String _vs = 'ضد';
const String _increase = 'زيادة';
const String _decrease = 'إنقاص';
const String _double = 'ضاعِف النقاط ×2';
const String _share = 'مشاركة';
const String _live = 'مباشر';
const String _everyone = 'توقعات الجميع';
const String _details = 'تفاصيل المباراة';

String _match(String home, String away) =>
    '${teamDisplayName(home)} $_vs ${teamDisplayName(away)}';

/// A kickoff already past and inside today's Riyadh day (UTC+3), so the
/// screen's default day holds a finished card at any hour.
String _pastToday() {
  final DateTime now = DateTime.now().toUtc();
  final DateTime riyadh = now.add(const Duration(hours: 3));
  final DateTime dayStart = DateTime.utc(
    riyadh.year,
    riyadh.month,
    riyadh.day,
  ).subtract(const Duration(hours: 3));
  final DateTime early = now.subtract(const Duration(hours: 2));
  final DateTime pick = early.isAfter(dayStart)
      ? early
      : dayStart.add(const Duration(seconds: 1));
  return pick.toIso8601String();
}

Map<String, Object?> _item(
  String id,
  String home,
  String away,
  String kickoffAt, {
  int? resultHome,
  int? resultAway,
}) => CurrentMonthFixtureItemDto(
  competitionId: 'c-1',
  competitionName: 'League',
  seasonLabel: '10/2026',
  fixture: SeasonFixtureCardDto(
    seasonId: 's-1',
    fixtureId: id,
    homeTeam: home,
    awayTeam: away,
    kickoffAt: kickoffAt,
  ),
  resultHomeGoals: resultHome,
  resultAwayGoals: resultAway,
  homeOutcomeShare: 60,
  drawOutcomeShare: 22,
  awayOutcomeShare: 18,
  totalPredictions: 100,
).toJson();

Map<String, Object?> _saved(String id) => FixturePredictionDto(
  id: 'pr-$id',
  participantId: 'p-me',
  fixtureId: id,
  submittedAt: '2026-10-18T10:00:00.000Z',
  homeGoals: 1,
  awayGoals: 0,
  isDouble: false,
  seasonId: 's-1',
).toJson();

Future<void> _pump(
  WidgetTester tester, {
  required List<Object?> feed,
  required List<Object?> mine,
}) async {
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final harness = buildCurrentMonthFixturesHarness((request) async {
    final String path = request.url.path;
    if (path == '/feed/current-month-fixtures') return okJsonList(feed);
    if (path == '/me/fixture-predictions') return okJsonList(mine);
    if (path == '/me/fixture-scores') return okJsonList(const []);
    if (path == '/teams') return okJsonList(const []);
    if (path.endsWith('/scores')) {
      return okJsonObject(const {
        'schema_version': 1,
        'fixture_id': 'f-1',
        'scores': <Object?>[],
      });
    }
    return http.Response('not found', 404);
  });
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        locale: const Locale('ar'),
        home: const CurrentMonthFixturesScreen(),
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// The node a key's control is read as: the one its drawn text sits in.
SemanticsNode _node(WidgetTester tester, String key) => tester.getSemantics(
  find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)).first,
);

/// The node of one stepper half: the InkWell inside its zone.
SemanticsNode _zone(WidgetTester tester, String key) => tester.getSemantics(
  find.descendant(of: find.byKey(Key(key)), matching: find.byType(InkWell)),
);

void main() {
  testWidgets('a card before kickoff names each control once, with its side '
      'or match', (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    try {
      await _pump(
        tester,
        feed: <Object?>[
          _item('f-1', 'Arsenal', 'Chelsea', futureIso()),
          _item('f-2', 'Al Hilal', 'Al Nassr', futureIso()),
        ],
        mine: <Object?>[_saved('f-1'), _saved('f-2')],
      );

      final String arsenal = teamDisplayName('Arsenal');
      final String chelsea = teamDisplayName('Chelsea');
      final SemanticsNode homeUp = _zone(
        tester,
        'currentMonthFixtures.home.increment.f-1',
      );
      final SemanticsNode homeDown = _zone(
        tester,
        'currentMonthFixtures.home.decrement.f-1',
      );
      final SemanticsNode awayUp = _zone(
        tester,
        'currentMonthFixtures.away.increment.f-1',
      );
      final SemanticsNode awayDown = _zone(
        tester,
        'currentMonthFixtures.away.decrement.f-1',
      );
      expect(homeUp.tooltip, '$_increase $arsenal');
      expect(homeDown.tooltip, '$_decrease $arsenal');
      expect(awayUp.tooltip, '$_increase $chelsea');
      expect(awayDown.tooltip, '$_decrease $chelsea');
      // Four halves, four nodes, each a button.
      expect(<int>{
        homeUp.id,
        homeDown.id,
        awayUp.id,
        awayDown.id,
      }, hasLength(4));
      for (final SemanticsNode zone in <SemanticsNode>[
        homeUp,
        homeDown,
        awayUp,
        awayDown,
      ]) {
        expect(zone.flagsCollection.isButton, isTrue);
      }
      // The saved 1-0 leaves the away side at 0: its "decrease" is a
      // disabled button of its own, and no longer names the whole card.
      expect(awayDown.flagsCollection.isEnabled, Tristate.isFalse);
      expect(homeDown.flagsCollection.isEnabled, Tristate.isTrue);
      expect(
        tester
            .getSemantics(
              find.byKey(const Key('currentMonthFixtures.fixture.f-1')),
            )
            .tooltip,
        '',
      );

      // The toggle is a node of its own: the card around it is no button.
      final SemanticsNode card = tester.getSemantics(
        find.byKey(const Key('currentMonthFixtures.fixture.f-1')),
      );
      expect(card.flagsCollection.isButton, isFalse);
      expect(
        _node(tester, 'currentMonthFixtures.double.f-1').id,
        isNot(card.id),
      );
      expect(
        _node(tester, 'currentMonthFixtures.double.f-1').label,
        '$_double ${_match('Arsenal', 'Chelsea')}',
      );
      expect(
        _node(tester, 'currentMonthFixtures.double.f-2').label,
        '$_double ${_match('Al Hilal', 'Al Nassr')}',
      );
      expect(
        _node(tester, 'currentMonthFixtures.sharePrediction.f-1').label,
        '$_share ${_match('Arsenal', 'Chelsea')}',
      );
      expect(
        _node(tester, 'currentMonthFixtures.sharePrediction.f-2').label,
        '$_share ${_match('Al Hilal', 'Al Nassr')}',
      );
      expect(_node(tester, 'currentMonthFixtures.live').label, _live);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('a finished card reads its two ways out once each', (
    tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    try {
      await _pump(
        tester,
        feed: <Object?>[
          _item(
            'f-1',
            'Arsenal',
            'Chelsea',
            _pastToday(),
            resultHome: 2,
            resultAway: 1,
          ),
        ],
        mine: <Object?>[_saved('f-1')],
      );

      // One page for the whole day: the same name on every card is right.
      expect(_node(tester, 'currentMonthFixtures.reveal.f-1').label, _everyone);
      expect(
        _node(tester, 'currentMonthFixtures.details.f-1').label,
        '$_details ${_match('Arsenal', 'Chelsea')}',
      );
    } finally {
      handle.dispose();
    }
  });
}
