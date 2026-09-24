/// A prediction card's reading order and how it reads aloud, through the
/// real [PredictionHistoryScreen]: the verdict (here "not started") sits on
/// the card's first line beside the kickoff, the call itself below it, and
/// when it was made last; the whole card is one spoken node.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/history/prediction_history_screen.dart';
import 'package:mobile/features/history/prediction_lookup_providers.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart' as cm;
import '../../support/prediction_harness.dart' as ph;

void main() {
  testWidgets('verdict first, the call next, when it was made last', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final SemanticsHandle handle = tester.ensureSemantics();
    try {
      final harness = ph.buildPredictionHarness((request) async {
        if (request.url.path == '/me/fixture-predictions') {
          return ph.okJsonList(<Object?>[ph.storedFixturePrediction.toJson()]);
        }
        return ph.okJsonList(const <Object?>[]);
      });
      addTearDown(harness.dispose);
      const String fixtureId = 'f-c';
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...harness.overrides,
            currentMonthFixturesByIdProvider.overrideWithValue(
              AsyncData<Map<String, SeasonFixtureCardDto>>({
                fixtureId: SeasonFixtureCardDto(
                  seasonId: 's-1',
                  fixtureId: fixtureId,
                  homeTeam: 'Al Hilal',
                  awayTeam: 'Al Nassr',
                  kickoffAt: cm.futureIso(),
                ),
              }),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('ar'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const PredictionHistoryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations l10n = await AppLocalizations.delegate.load(
        const Locale('ar'),
      );
      final String id = ph.storedFixturePrediction.id;
      final Finder verdict = find.text(l10n.historyStatusUpcoming);
      final Finder call = find.byKey(Key('history.score.$id.$fixtureId'));
      final Finder madeAt = find.byKey(Key('history.submittedAt.$id'));
      double top(Finder finder) => tester.getTopLeft(finder).dy;

      expect(verdict, findsOneWidget);
      expect(top(verdict), lessThan(top(call)), reason: 'the verdict leads');
      expect(top(call), lessThan(top(madeAt)));
      expect(
        tester.getSemantics(madeAt).id,
        tester.getSemantics(call).id,
        reason: 'the card is one node, read as one sentence',
      );
    } finally {
      handle.dispose();
    }
  });
}
