/// النتائج والاحتساب asks before a command that changes players' points,
/// by the match's name, and says what was recorded by that name, never by
/// the match's id (audit L-11).
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/admin/admin_providers.dart';
import 'package:mobile/features/admin/screens/sections/results_scoring_section.dart';
import 'package:mobile/l10n/app_localizations.dart';

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

final SeasonFixtureCardDto _waiting = SeasonFixtureCardDto(
  seasonId: 's-10',
  fixtureId: 'f-wait',
  homeTeam: 'Arsenal',
  awayTeam: 'Chelsea',
  kickoffAt: DateTime.now()
      .toUtc()
      .subtract(const Duration(hours: 5))
      .toIso8601String(),
);

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a result is recorded only after a confirmation that names '
      'the match, and the success line names it too', (tester) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final List<http.Request> recorded = <http.Request>[];
    final AdminHarness harness = buildAdminHarness((request) async {
      switch (request.url.path) {
        case '/competitions':
          return _json(<Object?>[_competition.toJson()]);
        case '/competitions/c-1/seasons':
          return _json(<Object?>[_october.toJson()]);
        case '/seasons/s-10/fixtures':
          return _json(<Object?>[_waiting.toJson()]);
        case '/fixtures/f-wait/result':
          recorded.add(request);
          return _json(const <String, Object?>{
            'schema_version': 1,
            'fixture_id': 'f-wait',
            'home_goals': 2,
            'away_goals': 1,
          });
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
                CurrentMonthFixtureItemDto(
                  competitionId: 'c-1',
                  competitionName: 'Premier League',
                  seasonLabel: '10/2026',
                  fixture: _waiting,
                ),
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

    await _tap(tester, 'admin.results.awaiting.f-wait');
    await tester.enterText(
      find.byKey(const Key('admin.results.homeGoals')),
      '2',
    );
    await tester.enterText(
      find.byKey(const Key('admin.results.awayGoals')),
      '1',
    );
    await tester.pumpAndSettle();

    await _tap(tester, 'admin.results.record');
    expect(find.byKey(const Key('admin.results.confirm')), findsOneWidget);
    expect(find.textContaining('Arsenal × Chelsea: 2-1'), findsOneWidget);
    await _tap(tester, 'admin.results.confirm.cancel');
    expect(recorded, isEmpty);

    await _tap(tester, 'admin.results.record');
    await _tap(tester, 'admin.results.confirm.ok');

    expect(recorded, hasLength(1));
    expect(jsonDecode(recorded.single.body), containsPair('home_goals', 2));
    expect(find.text('سُجّلت النتيجة: Arsenal × Chelsea 2-1'), findsOneWidget);
    expect(find.textContaining('f-wait'), findsNothing);
  });
}
