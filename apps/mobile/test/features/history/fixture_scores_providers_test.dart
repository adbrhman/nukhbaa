import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/history/fixture_scores_providers.dart';

import '../../support/current_month_fixtures_harness.dart';

void main() {
  testWidgets(
    'retries fixture scores while the stored grade is still pending',
    (tester) async {
      var scoreReads = 0;

      final harness = buildCurrentMonthFixturesHarness((request) async {
        if (request.url.path != '/seasons/s-1/fixtures/f-1/scores') {
          throw StateError(
            'Unexpected request: ${request.method} ${request.url.path}',
          );
        }

        scoreReads++;

        final graded = scoreReads >= 2;
        return okJsonObject({
          'schema_version': 1,
          'fixture_id': 'f-1',
          'scores': [
            {
              'schema_version': 1,
              'fixture_id': 'f-1',
              'participant_id': 'p-1',
              'ruleset_version': 1,
              'display_name': '',
              'grade': graded ? 'exact_scoreline' : 'pending',
              'points': graded ? 3 : 0,
            },
          ],
        });
      });

      addTearDown(harness.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.overrides,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                final scores = ref.watch(fixtureScoresProvider('s-1', 'f-1'));
                return Text(scores.value?.scores.first.grade ?? 'loading');
              },
            ),
          ),
        ),
      );

      await tester.pump();
      expect(scoreReads, 1);
      expect(find.text('pending'), findsOneWidget);

      await tester.pump(const Duration(minutes: 2));
      await tester.pump();

      expect(scoreReads, 2);
      expect(find.text('exact_scoreline'), findsOneWidget);
    },
  );
}
