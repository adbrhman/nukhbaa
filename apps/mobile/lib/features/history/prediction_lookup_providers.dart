/// Constant-time lookups over two reads the UI already watches.
///
/// Neither provider performs any HTTP of its own: each one only indexes the
/// result of an existing read ([myFixturePredictionsProvider],
/// [currentMonthFixturesProvider]). Before this, every visible match card
/// re-scanned the caller's COMPLETE prediction history, and every history
/// row re-scanned the COMPLETE current-month feed — O(rows x items) work
/// repeated on every rebuild. Indexing once per read makes each lookup O(1).
///
/// Hand-written (plain `Provider`, no `@riverpod`) for the same reason as
/// `current_month_fixtures_providers.dart`: this file needs no build_runner
/// output.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../fixture_prediction/current_month_fixtures_providers.dart';
import 'prediction_history_providers.dart';

/// The caller's own predictions, keyed by `fixtureId`.
final myFixturePredictionsByFixtureProvider =
    Provider<AsyncValue<Map<String, FixturePredictionDto>>>((ref) {
      return ref
          .watch(myFixturePredictionsProvider)
          .whenData(
            (List<FixturePredictionDto> items) =>
                Map<String, FixturePredictionDto>.unmodifiable(
                  <String, FixturePredictionDto>{
                    for (final FixturePredictionDto p in items) p.fixtureId: p,
                  },
                ),
          );
    });

/// The current-month feed's fixture cards, keyed by `fixtureId`.
final currentMonthFixturesByIdProvider =
    Provider<AsyncValue<Map<String, SeasonFixtureCardDto>>>((ref) {
      return ref
          .watch(currentMonthFixturesProvider)
          .whenData(
            (List<CurrentMonthFixtureItemDto> items) =>
                Map<String, SeasonFixtureCardDto>.unmodifiable(
                  <String, SeasonFixtureCardDto>{
                    for (final CurrentMonthFixtureItemDto item in items)
                      item.fixture.fixtureId: item.fixture,
                  },
                ),
          );
    });
