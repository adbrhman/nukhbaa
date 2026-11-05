/// النتائج والاحتساب: one «اعتماد النتيجة» button runs the four steps that
/// were four buttons (record the result, score the match, post it to the
/// ledger, load the players' report) behind one confirmation, in that order,
/// and when a step fails after the result is saved, the same tap finishes the
/// rest (script 214).
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

const FixtureScoresDto _scores = FixtureScoresDto(
  fixtureId: 'f-wait',
  scores: <ParticipantFixtureScoreDto>[
    ParticipantFixtureScoreDto(
      fixtureId: 'f-wait',
      participantId: 'part-1',
      rulesetVersion: 1,
      grade: 'exact_scoreline',
      points: 6,
    ),
  ],
);

const PostFixtureToLedgerResponseDto _ledger = PostFixtureToLedgerResponseDto(
  fixtureId: 'f-wait',
  appendedEntries: <FixturePointEntryDto>[
    FixturePointEntryDto(
      id: 'entry-1',
      participantId: 'part-1',
      fixtureId: 'f-wait',
      kind: 'fixture_score',
      amount: 6,
      sourceRef: 'fixture-f-wait',
      occurredAt: '2026-11-05T10:00:00.000Z',
    ),
  ],
);

const FixturePredictionDto _prediction = FixturePredictionDto(
  id: 'pred-1',
  participantId: 'part-1',
  fixtureId: 'f-wait',
  submittedAt: '2026-11-05T09:00:00Z',
  homeGoals: 2,
  awayGoals: 1,
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

/// Pumps the section over a harness whose handler is [handler]; the picked
/// match, 2-1, is typed in and ready for the button.
Future<void> _pumpReady(WidgetTester tester, AdminHarness harness) async {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

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
  await tester.enterText(find.byKey(const Key('admin.results.homeGoals')), '2');
  await tester.enterText(find.byKey(const Key('admin.results.awayGoals')), '1');
  await tester.pumpAndSettle();
}

http.Response? _route(http.Request request, {http.Response? ledger}) {
  switch ('${request.method} ${request.url.path}') {
    case 'GET /competitions':
      return _json(<Object?>[_competition.toJson()]);
    case 'GET /competitions/c-1/seasons':
      return _json(<Object?>[_october.toJson()]);
    case 'GET /seasons/s-10/fixtures':
      return _json(<Object?>[_waiting.toJson()]);
    case 'PUT /fixtures/f-wait/result':
      return _json(const <String, Object?>{
        'schema_version': 1,
        'fixture_id': 'f-wait',
        'home_goals': 2,
        'away_goals': 1,
      });
    case 'POST /fixtures/f-wait/score':
      return okJsonObject(_scores.toJson());
    case 'POST /fixtures/f-wait/ledger':
      return ledger ?? okJsonObject(_ledger.toJson());
    case 'GET /admin/fixtures/f-wait/scores':
      return okJsonObject(_scores.toJson());
    case 'GET /admin/fixtures/f-wait/predictions':
      return _json(<Object?>[_prediction.toJson()]);
  }
  return null;
}

void main() {
  testWidgets('one button records, scores, posts and shows the report, '
      'after one confirmation', (tester) async {
    final List<String> calls = <String>[];
    final AdminHarness harness = buildAdminHarness((request) async {
      calls.add('${request.method} ${request.url.path}');
      return _route(request) ??
          errorEnvelope(404, 'test.unrouted', request.url.path);
    });
    addTearDown(harness.dispose);
    await _pumpReady(tester, harness);

    // The four old buttons are one.
    expect(find.byKey(const Key('admin.results.score')), findsNothing);
    expect(find.byKey(const Key('admin.results.post')), findsNothing);
    expect(find.text('اعتماد النتيجة'), findsOneWidget);

    await _tap(tester, 'admin.results.record');
    expect(find.byKey(const Key('admin.results.confirm')), findsOneWidget);
    await _tap(tester, 'admin.results.confirm.ok');

    final List<String> writes = calls
        .where((String c) => c.startsWith('PUT') || c.startsWith('POST'))
        .toList();
    expect(writes, <String>[
      'PUT /fixtures/f-wait/result',
      'POST /fixtures/f-wait/score',
      'POST /fixtures/f-wait/ledger',
    ]);
    expect(calls, contains('GET /admin/fixtures/f-wait/scores'));
    expect(calls, contains('GET /admin/fixtures/f-wait/predictions'));

    expect(find.text('سُجّلت النتيجة: Arsenal × Chelsea 2-1'), findsOneWidget);
    expect(find.textContaining('تم الاحتساب'), findsOneWidget);
    expect(find.textContaining('تم الترحيل'), findsOneWidget);
    // The players' report is on screen: the exact scoreline's grade label.
    expect(find.text('نتيجة مطابقة'), findsOneWidget);
    expect(find.byKey(const Key('admin.results.resume')), findsNothing);
  });

  testWidgets('a step that fails after the result is saved is named, and the '
      'same button finishes the rest', (tester) async {
    final List<String> calls = <String>[];
    int ledgerCalls = 0;
    final AdminHarness harness = buildAdminHarness((request) async {
      calls.add('${request.method} ${request.url.path}');
      if (request.method == 'POST' &&
          request.url.path == '/fixtures/f-wait/ledger') {
        ledgerCalls++;
        if (ledgerCalls == 1) {
          return errorEnvelope(
            409,
            'ledger.fixture_not_scored',
            'score it first',
          );
        }
      }
      return _route(request) ??
          errorEnvelope(404, 'test.unrouted', request.url.path);
    });
    addTearDown(harness.dispose);
    await _pumpReady(tester, harness);

    await _tap(tester, 'admin.results.record');
    await _tap(tester, 'admin.results.confirm.ok');

    // Stopped at the ledger: the result is saved and scored, the report is
    // not loaded, and the screen says what is left.
    expect(find.byKey(const Key('admin.results.resume')), findsOneWidget);
    expect(find.textContaining('الترحيل إلى السجل'), findsWidgets);
    expect(calls, isNot(contains('GET /admin/fixtures/f-wait/scores')));
    expect(find.text('نتيجة مطابقة'), findsNothing);

    // The same button, once more: the second ledger call goes through.
    await _tap(tester, 'admin.results.record');
    await _tap(tester, 'admin.results.confirm.ok');

    expect(ledgerCalls, 2);
    expect(find.byKey(const Key('admin.results.resume')), findsNothing);
    expect(find.text('نتيجة مطابقة'), findsOneWidget);
  });
}
