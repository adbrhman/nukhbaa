/// Correcting a running score the provider has wrong (2026-10-18: Paris FC -
/// Rennes stayed 2-2 in the feed after a goal was ruled out). The real
/// النتائج والاحتساب screen over the real `api_client`, with only the HTTP
/// answers faked ([buildAdminHarness]): a match in play is listed, its
/// score opens prefilled, and saving sends the corrected score to
/// `PUT /fixtures/{id}/live-score`; a refusal is shown in plain words.
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

CurrentMonthFixtureItemDto _live(String id, String home, {int? resultHome}) =>
    CurrentMonthFixtureItemDto(
      competitionId: 'c-1',
      competitionName: 'الدوري الفرنسي',
      seasonLabel: '10/2026',
      fixture: SeasonFixtureCardDto(
        seasonId: 's-10',
        fixtureId: id,
        homeTeam: home,
        awayTeam: 'رين',
        kickoffAt: DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 62))
            .toIso8601String(),
      ),
      liveHomeGoals: 2,
      liveAwayGoals: 2,
      liveMinute: 62,
      liveFinished: false,
      resultHomeGoals: resultHome,
      resultAwayGoals: resultHome,
    );

http.Response _list(List<Object?> elements) => http.Response(
  jsonEncode(elements),
  200,
  headers: const {'content-type': 'application/json'},
);

void main() {
  Future<AdminHarness> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AdminHarness harness = buildAdminHarness((request) async {
      if (request.method == 'PUT' &&
          request.url.path == '/fixtures/f-paris/live-score') {
        return okJsonObject(<String, Object?>{
          'fixture_id': 'f-paris',
          'home_goals': 2,
          'away_goals': 1,
        });
      }
      if (request.method == 'PUT' &&
          request.url.path == '/fixtures/f-gone/live-score') {
        return errorEnvelope(
          409,
          'football_data.not_live',
          'Fixture f-gone has no running score from the provider',
        );
      }
      if (request.url.path == '/competitions') {
        return _list(<Object?>[]);
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
                _live('f-paris', 'باريس إف سي'),
                _live('f-gone', 'لوهافر'),
                // A recorded result is no longer corrected here.
                _live('f-done', 'لوريان', resultHome: 1),
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
    return harness;
  }

  Finder field(String key) => find.descendant(
    of: find.byKey(Key(key)),
    matching: find.byType(TextField),
  );

  testWidgets('a ruled-out goal is corrected from the results screen', (
    tester,
  ) async {
    final AdminHarness harness = await pump(tester);

    expect(find.text('النتائج المباشرة (2)'), findsOneWidget);
    expect(find.byKey(const Key('admin.results.live.f-done')), findsNothing);
    expect(find.text('باريس إف سي 2 - 2 رين'), findsOneWidget);

    await tester.tap(find.byKey(const Key('admin.results.live.f-paris')));
    await tester.pumpAndSettle();
    expect(find.text('تصحيح النتيجة المباشرة'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(field('admin.results.live.home'))
          .controller!
          .text,
      '2',
    );

    await tester.enterText(field('admin.results.live.away'), '1');
    await tester.tap(find.byKey(const Key('admin.results.live.save')));
    await tester.pumpAndSettle();

    final http.Request sent = harness.captured
        .map((CapturedRequest c) => c.request)
        .singleWhere((http.Request r) => r.method == 'PUT');
    expect(sent.url.path, '/fixtures/f-paris/live-score');
    expect(jsonDecode(sent.body), <String, Object?>{
      'home_goals': 2,
      'away_goals': 1,
    });
    expect(find.text('تصحيح النتيجة المباشرة'), findsNothing);
    expect(find.text('صُحّحت النتيجة المباشرة'), findsOneWidget);
  });

  testWidgets('a match the provider no longer reports is refused in plain '
      'words', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('admin.results.live.f-gone')));
    await tester.pumpAndSettle();
    await tester.enterText(field('admin.results.live.away'), '1');
    await tester.tap(find.byKey(const Key('admin.results.live.save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('admin.results.live.error')), findsOneWidget);
    expect(find.textContaining('لم يعد المزوّد'), findsOneWidget);
    expect(find.textContaining('football_data'), findsNothing);
    // The dialog stays open to record the result instead.
    expect(find.text('تصحيح النتيجة المباشرة'), findsOneWidget);
  });
}
