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
