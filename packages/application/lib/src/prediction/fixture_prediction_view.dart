import 'package:domain/domain.dart';

/// A read model that pairs a [FixturePrediction] with the submission instant
/// its repository stamped on it — the per-fixture sibling of [PredictionView]
/// (docs/project-context.md, Axiom 4 Amendment), for the same reason:
/// `FixturePrediction` carries no `submittedAt` (a persistence fact, not a
/// domain invariant), but the wire DTO needs one.
///
/// Pure and immutable; value-comparable by `(prediction, submittedAt, seasonId)`.
final class FixturePredictionView {
  /// Pairs [prediction] with the UTC [submittedAt] instant it was stored
  /// under, and optionally [seasonId].
  const FixturePredictionView({
    required this.prediction,
    required this.submittedAt,
    this.seasonId,
  });

  /// The fixture-prediction aggregate.
  final FixturePrediction prediction;

  /// The submission instant (UTC) the repository stamped on this prediction.
  /// For an amended prediction this is the amendment instant.
  final DateTime submittedAt;

  /// The season this prediction belongs to, derived from
  /// `participant_id -> competition.participants.season_id` (a permanent,
  /// unambiguous N:1 relationship — not the M:N
  /// `competition.season_fixtures` link, which answers a different question).
  /// Populated only by [FixturePredictionRepository.listByUser], whose query
  /// joins `competition.participants`; null from every other repository
  /// method, whose queries do not select this column.
  final SeasonId? seasonId;

  @override
  bool operator ==(Object other) =>
      other is FixturePredictionView &&
      other.prediction == prediction &&
      other.submittedAt == submittedAt &&
      other.seasonId == seasonId;

  @override
  int get hashCode => Object.hash(prediction, submittedAt, seasonId);
}
