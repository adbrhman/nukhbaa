/// A burst of saves through the real matches screen, the real cards and a
/// fake server (script 256): three cards saved within two seconds read the
/// caller's history twice -- at once for the first save, once more for the
/// other two -- and not once per save. Before, every save read it again and
/// built every card of the day again with it.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

Map<String, Object?> _item(String id) => CurrentMonthFixtureItemDto(
  competitionId: 'c-1',
  competitionName: 'League',
  seasonLabel: '10/2026',
  fixture: SeasonFixtureCardDto(
    seasonId: 's-1',
    fixtureId: id,
    homeTeam: 'Arsenal',
    awayTeam: 'Chelsea',
    kickoffAt: futureIso(),
  ),
).toJson();

void main() {
  testWidgets('three saves in one burst read the history twice, not three '
      'times', (tester) async {
    // Tall enough that the three cards of the day are built.
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    int historyReads = 0;
    final List<String> saved = <String>[];
    final harness = buildCurrentMonthFixturesHarness((request) async {
      final String path = request.url.path;
      if (path == '/feed/current-month-fixtures') {
        return okJsonList(<Map<String, Object?>>[
          _item('f-1'),
          _item('f-2'),
          _item('f-3'),
        ]);
      }
      if (path == '/me/fixture-predictions') {
        historyReads++;
        return okJsonList(const <Object?>[]);
      }
      if (path == '/teams') {
        return okJsonList(const <Object?>[]);
      }
      if (request.method == 'POST' && path.endsWith('/prediction')) {
        final String fixtureId = path.split('/')[4];
        saved.add(fixtureId);
        final Map<String, Object?> body =
            jsonDecode(request.body) as Map<String, Object?>;
        return okJsonObject(<String, Object?>{
          'schema_version': 1,
          'id': 'fp-$fixtureId',
          'participant_id': 'part-1',
          'fixture_id': fixtureId,
          'submitted_at': '2026-11-11T10:00:00.000Z',
          'home_goals': body['home_goals'],
          'away_goals': body['away_goals'],
          'is_double': body['is_double'],
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
    final int readsBefore = historyReads;
    expect(readsBefore, greaterThanOrEqualTo(1));

    Future<void> save(String id) async {
      await tester.tap(
        find.byKey(Key('currentMonthFixtures.home.increment.$id')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(Key('currentMonthFixtures.away.increment.$id')),
      );
      await tester.pump();
      // The 250 ms pause ends and the save goes out and comes back.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));
    }

    await save('f-1');
    await save('f-2');
    await save('f-3');
    expect(saved, <String>['f-1', 'f-2', 'f-3']);
    expect(
      historyReads - readsBefore,
      1,
      reason: 'the first save reads the history at once, the other two wait',
    );

    // The window closes: the two waiting saves cost one more read.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 100));
    expect(historyReads - readsBefore, 2);

    // And nothing more is read afterwards.
    await tester.pump(const Duration(seconds: 3));
    expect(historyReads - readsBefore, 2);
  });
}
