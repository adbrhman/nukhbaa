/// Matches waiting for a result (2026-10-08): the list atop النتائج
/// والاحتساب fills the real form -- the real pickers over the real providers,
/// with only the HTTP answers faked ([buildAdminHarness]) -- and a test
/// fixture, never scored by design, is never counted as waiting. Also the
/// clear refusals for deleting a predicted or scored match.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/error/error_presenter.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/admin/admin_providers.dart';
import 'package:mobile/features/admin/screens/sections/admin_home_section.dart';
import 'package:mobile/features/admin/screens/sections/results_scoring_section.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:shared/shared.dart';

import '../../support/admin_harness.dart';

const CompetitionDto _competition = CompetitionDto(
  id: 'c-1',
  name: 'Premier League',
  format: 'football_scoreline',
  visibility: 'public',
);

final SeasonDto _october = SeasonDto(
  id: 's-10',
  competitionId: 'c-1',
  label: '10/2026',
  startAt: DateTime.utc(2026, 9, 30, 21),
  endAt: DateTime.utc(2026, 10, 31, 21),
);

// Over five hours ago: past any live window at whatever hour the suite runs.
final String _overKickoff = DateTime.now()
    .toUtc()
    .subtract(const Duration(hours: 5))
    .toIso8601String();

SeasonFixtureCardDto _card(String id, String home, {bool isTest = false}) =>
    SeasonFixtureCardDto(
      seasonId: 's-10',
      fixtureId: id,
      homeTeam: home,
      awayTeam: 'Chelsea',
      kickoffAt: _overKickoff,
      isTest: isTest,
    );

CurrentMonthFixtureItemDto _item(
  SeasonFixtureCardDto card, {
  int? resultHome,
  int? resultAway,
}) => CurrentMonthFixtureItemDto(
  competitionId: 'c-1',
  competitionName: 'Premier League',
  seasonLabel: '10/2026',
  fixture: card,
  resultHomeGoals: resultHome,
  resultAwayGoals: resultAway,
);

final SeasonFixtureCardDto _waiting = _card('f-wait', 'Arsenal');
final SeasonFixtureCardDto _scored = _card('f-done', 'Liverpool');
final SeasonFixtureCardDto _test = _card('f-test', 'أبها', isTest: true);

http.Response _list(List<Object?> elements) => http.Response(
  jsonEncode(elements),
  200,
  headers: const {'content-type': 'application/json'},
);

void main() {
  test('a test fixture is never waiting for a result: it is never scored', () {
    final DateTime now = DateTime.now();
    final List<CurrentMonthFixtureItemDto> waiting = fixturesAwaitingResult(
      <CurrentMonthFixtureItemDto>[
        _item(_waiting),
        _item(_scored, resultHome: 2, resultAway: 0),
        _item(_test),
      ],
      now,
    );
    expect(
      waiting.map((CurrentMonthFixtureItemDto i) => i.fixture.fixtureId),
      <String>['f-wait'],
    );
  });

  test('deleting a predicted or scored match is refused in plain words', () {
    final String predicted = ErrorPresenter.message(
      const AppError.invariant(
        'competition.fixture_has_predictions',
        'Users have already predicted this fixture',
      ),
    );
    expect(predicted, contains('أخفِها'));
    expect(predicted, isNot(contains('competition.')));
    final String scored = ErrorPresenter.message(
      const AppError.invariant(
        'competition.fixture_result_already_recorded',
        'A result is recorded',
      ),
    );
    expect(scored, contains('أخفِها'));
    expect(scored, isNot(contains('competition.')));
  });

  testWidgets('tapping a waiting match fills league, month and match', (
    tester,
  ) async {
    // Tall: the whole screen is built at once.
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AdminHarness harness = buildAdminHarness((request) async {
      switch (request.url.path) {
        case '/competitions':
          return _list(<Object?>[_competition.toJson()]);
        case '/competitions/c-1/seasons':
          return _list(<Object?>[_october.toJson()]);
        case '/seasons/s-10/fixtures':
          return _list(<Object?>[
            _waiting.toJson(),
            _scored.toJson(),
            _test.toJson(),
          ]);
      }
      return errorEnvelope(404, 'test.unrouted', request.url.path);
    });
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...harness.overrides,
          adminDashboardProvider.overrideWith(
            (ref) async => AdminDashboardSnapshot(
              stats: const UserStatsDto(total: 0, active: 0, suspended: 0),
              auditLog: const AuditLogDto(entries: <AuditEntryDto>[]),
              competitions: const <CompetitionDto>[],
              currentMonthFixtures: <CurrentMonthFixtureItemDto>[
                _item(_waiting),
                _item(_scored, resultHome: 2, resultAway: 0),
                _item(_test),
              ],
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const Scaffold(body: ResultsScoringSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Only the real, unscored match waits.
    expect(find.text('بانتظار النتيجة (1)'), findsOneWidget);
    expect(
      find.byKey(const Key('admin.results.awaiting.f-wait')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('admin.results.awaiting.f-test')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('admin.results.awaiting.f-done')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('admin.results.awaiting.f-wait')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('admin.results.competitionField.field')),
        matching: find.text('Premier League'),
      ),
      findsOneWidget,
    );
    // The month reads as the app names it everywhere, not as stored.
    expect(
      find.descendant(
        of: find.byKey(const Key('admin.fixtures.seasonField.c-1')),
        matching: find.text('شهر 10'),
      ),
      findsOneWidget,
    );
    expect(find.text('10/2026'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('admin.results.record.fixtureField')),
        matching: find.textContaining('Arsenal'),
      ),
      findsOneWidget,
    );
  });
}
