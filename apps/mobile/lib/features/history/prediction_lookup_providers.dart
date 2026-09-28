/// Constant-time lookups over two reads the UI already watches.
///
/// The two indexes perform no HTTP of their own: each one only indexes the
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
import '../fixture_prediction/fixture_prediction_providers.dart';
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

/// The fixture card behind every prediction in the caller's history, keyed
/// by `fixtureId`: the current-month feed first, then -- for a prediction
/// whose fixture is not in it -- the fixtures of the prediction's own
/// season (`GET /seasons/{id}/fixtures`, one cached read per such season).
///
/// The feed only carries the month in progress, so on the first day of a
/// month every prediction of the month before lost its team names and its
/// kickoff: the card fell back to the raw fixture id and the "completed"
/// filter dropped it. `seasonId` is the participant's season, which is the
/// monthly contest the fixture was linked to.
///
/// Nothing is requested while the feed is still on its first load, so the
/// month in progress is never fetched twice; a feed that failed leaves
/// every season to the fallback.
final historyFixturesByIdProvider = Provider<Map<String, SeasonFixtureCardDto>>(
  (ref) {
    final AsyncValue<Map<String, SeasonFixtureCardDto>> feed = ref.watch(
      currentMonthFixturesByIdProvider,
    );
    final Map<String, SeasonFixtureCardDto> current =
        feed.value ?? const <String, SeasonFixtureCardDto>{};
    if (feed.isLoading && !feed.hasValue) return current;
    final List<FixturePredictionDto> history =
        ref.watch(myFixturePredictionsProvider).value ??
        const <FixturePredictionDto>[];
    final Set<String> otherSeasons = <String>{
      for (final FixturePredictionDto p in history)
        if (!current.containsKey(p.fixtureId) && p.seasonId != null)
          p.seasonId!,
    };
    if (otherSeasons.isEmpty) return current;
    final Map<String, SeasonFixtureCardDto> merged =
        <String, SeasonFixtureCardDto>{...current};
    for (final String seasonId in otherSeasons) {
      final List<SeasonFixtureCardDto>? fixtures = ref
          .watch(seasonFixturesProvider(seasonId))
          .value;
      if (fixtures == null) continue;
      for (final SeasonFixtureCardDto fixture in fixtures) {
        merged.putIfAbsent(fixture.fixtureId, () => fixture);
      }
    }
    return Map<String, SeasonFixtureCardDto>.unmodifiable(merged);
  },
);
