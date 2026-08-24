import 'package:domain/domain.dart';

/// A read model that pairs a [FixturePrediction] with the submission instant
/// its repository stamped on it — the per-fixture sibling of [PredictionView]
/// (docs/project-context.md, Axiom 4 Amendment), for the same reason:
/// `FixturePrediction` carries no `submittedAt` (a persistence fact, not a
/// domain invariant), but the wire DTO needs one.
///
/// Pure and immutable; value-comparable by `(prediction, submittedAt)`.
final class FixturePredictionView {
  /// Pairs [prediction] with the UTC [submittedAt] instant it was stored under.
  const FixturePredictionView({
    required this.prediction,
    required this.submittedAt,
  });

  /// The fixture-prediction aggregate.
  final FixturePrediction prediction;

  /// The submission instant (UTC) the repository stamped on this prediction.
  /// For an amended prediction this is the amendment instant.
  final DateTime submittedAt;

  @override
  bool operator ==(Object other) =>
      other is FixturePredictionView &&
      other.prediction == prediction &&
      other.submittedAt == submittedAt;

  @override
  int get hashCode => Object.hash(prediction, submittedAt);
}
