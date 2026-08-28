/// The Prediction History **view** state — a read-only provider over the
/// caller's own aggregated prediction history (mirrors the other feature
/// `*_providers.dart` files: a plain `FutureProvider` wrapping one `api_client`
/// read).
library;

import 'package:contracts/contracts.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';

part 'prediction_history_providers.g.dart';

T _unwrap<T>(Result<T> result) => switch (result) {
  Ok<T>(:final value) => value,
  Err<T>(:final error) => throw error,
};

/// `GET /me/predictions` — every prediction the caller has ever submitted,
/// across every round and season, newest first.
@riverpod
Future<List<PredictionDto>> myPredictions(Ref ref) async {
  final api = ref.watch(predictionApiProvider);
  return _unwrap(await api.myPredictions());
}

/// `GET /me/fixture-predictions` — every per-fixture prediction the caller
/// has ever submitted, across every fixture and season, newest first
/// (docs/project-context.md, Axiom 4 Amendment; the per-fixture sibling of
/// [myPredictions]).
@riverpod
Future<List<FixturePredictionDto>> myFixturePredictions(Ref ref) async {
  final api = ref.watch(predictionApiProvider);
  return _unwrap(await api.myFixturePredictions());
}

/// One entry in the unified prediction history — either a round-scoped
/// [PredictionDto] or a per-fixture [FixturePredictionDto]. The two prediction
/// kinds are separate ports/routes (Axiom 4 Amendment keeps them apart on
/// purpose); this type exists only so [PredictionHistoryScreen] can render
/// both in one newest-first list without closing the underlying data gap by
/// pretending they are the same shape.
sealed class PredictionHistoryEntry {
  /// The submission instant, parsed once so entries from both sources sort
  /// together.
  DateTime get submittedAt;
}

/// A round-scoped prediction entry.
final class RoundPredictionEntry implements PredictionHistoryEntry {
  /// Wraps a stored round prediction.
  RoundPredictionEntry(this.prediction)
    : submittedAt = DateTime.parse(prediction.submittedAt);

  /// The wrapped round prediction.
  final PredictionDto prediction;

  @override
  final DateTime submittedAt;
}

/// A per-fixture prediction entry.
final class FixturePredictionEntry implements PredictionHistoryEntry {
  /// Wraps a stored fixture prediction.
  FixturePredictionEntry(this.prediction)
    : submittedAt = DateTime.parse(prediction.submittedAt);

  /// The wrapped fixture prediction.
  final FixturePredictionDto prediction;

  @override
  final DateTime submittedAt;
}

/// The unified prediction history: [myPredictions] and [myFixturePredictions]
/// merged into one newest-first list. Both reads are fetched in parallel;
/// either source failing fails the whole read (mirrors how every other
/// browse provider in this app surfaces a transport/server error — there is
/// no partial-degrade case defined for this screen yet).
@riverpod
Future<List<PredictionHistoryEntry>> predictionHistory(Ref ref) async {
  final api = ref.watch(predictionApiProvider);
  final results = await (
    api.myPredictions(),
    api.myFixturePredictions(),
  ).wait;
  final rounds = _unwrap(results.$1);
  final fixtures = _unwrap(results.$2);
  final entries = <PredictionHistoryEntry>[
    for (final prediction in rounds) RoundPredictionEntry(prediction),
    for (final prediction in fixtures) FixturePredictionEntry(prediction),
  ]..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
  return entries;
}
