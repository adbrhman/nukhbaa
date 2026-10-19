/// The match details page (script 118) on Paris FC 4-3 Rennes FC as
/// Highlightly told it on 2026-10-19: the real page over the real
/// `api_client`, with only the HTTP answer faked ([buildAdminHarness]).
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/competition/team_identity.dart';
import 'package:mobile/features/fixture_prediction/widgets/match_details_page.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/admin_harness.dart';

MatchEventDto _e(
  String minute,
  String kind,
  bool home,
  String player, {
  String? assist,
}) => MatchEventDto(
  minute: minute,
  kind: kind,
  home: home,
  player: player,
  assist: assist,
);

final MatchDetailsDto _story = MatchDetailsDto(
  fixtureId: 'f-paris',
  available: true,
  halfTimeHome: 2,
  halfTimeAway: 1,
  venue: 'Stade Jean Bouin',
  round: 'Regular Season - 8',
  events: <MatchEventDto>[
    _e('14', 'goal', true, 'Maxime López', assist: 'Lassine Sinayoko'),
    _e('23', 'yellow_card', false, 'Przemysław Frankowski'),
    _e('29', 'penalty_goal', false, 'Esteban Lepaul'),
    _e('32', 'yellow_card', false, 'Djaoui Cissé'),
    _e('36', 'yellow_card', false, 'Adrien Thomasson'),
    _e('36', 'yellow_card', false, 'Anthony Rouault'),
    _e('42', 'yellow_card', true, 'Samir Chergui'),
    _e('45+4', 'goal', true, 'Maxime López', assist: 'Lassine Sinayoko'),
    _e('45', 'substitution', false, 'Adrien Thomasson'),
    _e('45', 'substitution', false, 'Ludovic Blas'),
    _e('45', 'substitution', false, 'Przemysław Frankowski'),
    _e('51', 'var_goal_cancelled', false, 'Sebastian Szymański'),
    _e('62', 'substitution', false, 'Djaoui Cissé'),
    _e('67', 'yellow_card', true, 'Ilan Kebbal'),
    _e('70', 'substitution', true, 'Pablo Pagis'),
    _e('74', 'penalty_goal', false, 'Esteban Lepaul'),
    _e('76', 'goal', true, 'Lassine Sinayoko'),
    _e('79', 'substitution', true, 'Hamari Traore'),
    _e('79', 'substitution', false, 'Issa Soumaré'),
    _e('79', 'substitution', true, 'Ilan Kebbal'),
    _e('86', 'substitution', true, 'Luca Koleosho'),
    _e('86', 'substitution', true, 'Samir Chergui'),
    _e('88', 'penalty_goal', false, 'Esteban Lepaul'),
    _e('90+3', 'other', true, 'Lassine Sinayoko'),
    _e('90+5', 'yellow_card', true, 'Hamari Traore'),
    _e('90+7', 'penalty_goal', true, 'Lassine Sinayoko'),
  ],
);

const CurrentMonthFixtureItemDto _item = CurrentMonthFixtureItemDto(
  competitionId: 'c-1',
  competitionName: 'شهر 10',
  seasonLabel: '10/2026',
  fixture: SeasonFixtureCardDto(
    seasonId: 's-10',
    fixtureId: 'f-paris',
    homeTeam: 'باريس إف سي',
    awayTeam: 'رين',
    kickoffAt: '2026-10-18T15:15:00.000Z',
    leagueName: 'الدوري الفرنسي',
  ),
  resultHomeGoals: 4,
  resultAwayGoals: 3,
);

Future<AdminHarness> _pump(
  WidgetTester tester,
  http.Response answer, {
  Size size = const Size(900, 3000),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final AdminHarness harness = buildAdminHarness((request) async {
    if (request.url.path == '/fixtures/f-paris/details') return answer;
    return errorEnvelope(404, 'test.unrouted', request.url.path);
  });
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const MatchDetailsPage(
          item: _item,
          home: ResolvedTeamIdentity(displayName: 'باريس إف سي'),
          away: ResolvedTeamIdentity(displayName: 'رين'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  testWidgets('the goals and cards show with their minutes, the ruled-out '
      'goal struck through, substitutions left out', (tester) async {
    await _pump(tester, _json(_story.toJson()));

    // The score sits home side first in the reader's direction.
    expect(find.text('3 - 4'), findsOneWidget);
    expect(find.text('الشوط الأول: 1 - 2'), findsOneWidget);
    expect(find.text('الدوري الفرنسي · الجولة 8'), findsOneWidget);
    expect(find.text('Stade Jean Bouin'), findsOneWidget);

    // 7 goals, 7 yellow cards and the VAR's cancelled goal: 15 rows.
    expect(find.byKey(const Key('matchDetails.event.14')), findsOneWidget);
    expect(find.byKey(const Key('matchDetails.event.15')), findsNothing);
    expect(find.text("90+7'"), findsOneWidget);
    expect(find.text("45+4'"), findsOneWidget);
    expect(find.text('Pablo Pagis'), findsNothing);
    expect(find.text('صناعة: Lassine Sinayoko'), findsNWidgets(2));
    expect(find.text('ركلة جزاء'), findsNWidgets(4));
    expect(find.text('هدف ألغاه حكم الفيديو (VAR)'), findsOneWidget);
    final Text cancelled = tester.widget<Text>(
      find.text('Sebastian Szymański'),
    );
    expect(cancelled.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('a story not read yet says so', (tester) async {
    await _pump(
      tester,
      _json(
        const MatchDetailsDto(fixtureId: 'f-paris', available: false).toJson(),
      ),
    );

    expect(find.byKey(const Key('matchDetails.notYet')), findsOneWidget);
    expect(find.text('3 - 4'), findsOneWidget);
  });

  testWidgets('a failure says so with a retry', (tester) async {
    await _pump(tester, errorEnvelope(503, 'db.query_timeout', 'timed out'));

    expect(find.byKey(const Key('matchDetails.error')), findsOneWidget);
    expect(find.byKey(const Key('matchDetails.retry')), findsOneWidget);
  });

  testWidgets('it fits a 360px phone at text x2', (tester) async {
    await _pump(
      tester,
      _json(_story.toJson()),
      size: const Size(360, 3000),
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('matchDetails.event.0')), findsOneWidget);
  });
}
