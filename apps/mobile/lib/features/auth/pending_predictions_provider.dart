/// What the caller has not predicted yet, from reads the home screen already
/// watches.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../fixture_prediction/current_month_fixtures_providers.dart';
import '../history/prediction_lookup_providers.dart';

/// The still-open, still-unpredicted fixtures of the current month.
///
/// "Open" is the same rule the prediction card enforces: a fixture locks the
/// moment its kickoff passes. It is recomputed on every read against "now"
/// rather than stored, so a card cannot sit on the screen claiming a match is
/// open after it has started.
@immutable
class PendingPredictions {
  /// Creates a summary.
  const PendingPredictions({required this.count, required this.next});

  /// How many fixtures are open and unpredicted.
  final int count;

  /// The one closing soonest, or null when [count] is zero.
  final CurrentMonthFixtureItemDto? next;

  /// Whether there is anything to nudge about at all.
  bool get isEmpty => count == 0;
}

/// Derives [PendingPredictions] from the month's fixtures minus the caller's
/// own predictions.
///
/// A plain `Provider` over two `AsyncValue`s rather than a fetch of its own:
/// it performs no HTTP, and both inputs are already on screen. While either
/// is still loading the result is `null` -- the nudge simply does not appear
/// yet, which is the honest state for a claim about what you have not done.
final pendingPredictionsProvider = Provider<PendingPredictions?>((ref) {
  final fixtures = ref.watch(currentMonthFixturesProvider).value;
  final predicted = ref.watch(myFixturePredictionsByFixtureProvider).value;
  if (fixtures == null || predicted == null) return null;

  final nowUtc = DateTime.now().toUtc();
  CurrentMonthFixtureItemDto? soonest;
  DateTime? soonestKickoff;
  var count = 0;

  for (final item in fixtures) {
    if (predicted.containsKey(item.fixture.fixtureId)) continue;
    final raw = item.fixture.kickoffAt;
    if (raw == null) continue;
    final kickoff = DateTime.tryParse(raw)?.toUtc();
    // Same lock rule as the prediction card: kickoff reached means closed.
    if (kickoff == null || !kickoff.isAfter(nowUtc)) continue;

    count++;
    if (soonestKickoff == null || kickoff.isBefore(soonestKickoff)) {
      soonestKickoff = kickoff;
      soonest = item;
    }
  }

  return PendingPredictions(count: count, next: soonest);
});
