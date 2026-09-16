/// Regression: the first score ever entered on a card must survive the
/// arrival of that first save.
///
/// Before the fix, a card with no stored prediction still had its one-shot
/// "prefill from history" armed. The first auto-save (for example 2-0,
/// fired while the finger moved on) refreshed the history, the history came
/// back holding 2-0, and the prefill copied it over the 2-1 the user had
/// tapped in the meantime -- so the card jumped back to 2-0 and a second
/// tap was needed. From then on the prefill was spent, which is why only
/// the first entry misbehaved.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

Widget _host(CurrentMonthFixturesHarness harness, Widget child) =>
    ProviderScope(
      overrides: harness.overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: child,
      ),
    );

const String _submitPath = '/seasons/s-1/fixtures/f-1/prediction';

void main() {
  testWidgets(
    'a tap made while the first save is in flight is not overwritten',
    (tester) async {
      final Completer<void> releaseFirstSave = Completer<void>();
      int submits = 0;
      Map<String, Object?>? stored;

      final harness = buildCurrentMonthFixturesHarness((request) async {
        final path = request.url.path;
        if (path == '/feed/current-month-fixtures') {
          return okJsonList([sampleFeedItem.toJson()]);
        }
        if (path == '/seasons/s-1/fixtures/f-1/prediction-distribution') {
          return okJsonObject(const {
            'schema_version': 1,
            'home_win_percentage': 50,
            'away_win_percentage': 50,
          });
        }
        if (path == '/me/fixture-predictions') {
          final Map<String, Object?>? current = stored;
          return okJsonList([?current]);
        }
        if (path == '/teams') {
          return okJsonList(const []);
        }
        if (path == _submitPath) {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          submits++;
          final Map<String, Object?> saved = {
            'schema_version': 1,
            'id': 'fp-1',
            'participant_id': 'part-1',
            'fixture_id': 'f-1',
            'submitted_at': '2026-09-04T10:00:00.000Z',
            'home_goals': body['home_goals'],
            'away_goals': body['away_goals'],
            'is_double': body['is_double'],
          };
          if (submits == 1) {
            await releaseFirstSave.future;
          }
          stored = saved;
          return okJsonObject(saved);
        }
        throw StateError('Unexpected request: ${request.method} $path');
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(
        _host(harness, const CurrentMonthFixturesScreen()),
      );
      await tester.pumpAndSettle();

      Finder increment(String side) =>
          find.byKey(Key('currentMonthFixtures.$side.increment.f-1'));
      String shown(String side) => tester
          .widget<Text>(find.byKey(Key('currentMonthFixtures.$side.value.f-1')))
          .data!;

      // A first tap turns "?" into 0, so three home taps make 2 and one away
      // tap makes 0.
      // 2-0: both sides now have a value, so the debounce arms.
      await tester.tap(increment('home'));
      await tester.pump();
      await tester.tap(increment('home'));
      await tester.pump();
      await tester.tap(increment('home'));
      await tester.pump();
      await tester.tap(increment('away'));
      await tester.pump();

      // The finger pauses: the 2-0 save starts and is held open.
      await tester.pump(const Duration(milliseconds: 300));
      expect(submits, 1);

      // 2-1 is tapped while 2-0 is still in flight.
      await tester.tap(increment('away'));
      await tester.pump();
      expect(shown('away'), '1');

      // The 2-0 save lands and the history refreshes to 2-0.
      releaseFirstSave.complete();
      for (int i = 0; i < 4; i++) {
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.pumpAndSettle();

      expect(shown('home'), '2');
      expect(
        shown('away'),
        '1',
        reason: 'the refreshed history must not overwrite a newer tap',
      );
      final Map<String, Object?> lastBody =
          jsonDecode(
                harness.captured
                    .lastWhere((c) => c.request.url.path == _submitPath)
                    .request
                    .body,
              )
              as Map<String, Object?>;
      expect(lastBody['home_goals'], 2);
      expect(lastBody['away_goals'], 1);
    },
  );
}
