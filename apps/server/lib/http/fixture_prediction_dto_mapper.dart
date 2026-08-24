import 'package:application/application.dart';
import 'package:contracts/contracts.dart';

/// Projects a [FixturePredictionView] (a fixture-prediction aggregate plus the
/// submission instant the repository stamped) onto the versioned wire shape
/// [FixturePredictionDto] (API ADR §4) — the per-fixture sibling of
/// `predictionViewToJson` (docs/project-context.md, Axiom 4 Amendment).
///
/// Integrity boundary (Axioms 2/5): only the user's stored *intent* crosses
/// the wire — the fixture id and predicted goals, plus the `is_double` flag.
/// No points, score, or competitive-record value is ever included; those are
/// produced server-side by `ScoreFixture` and never part of this read model.
/// `submitted_at` is the exact instant the repository stamped (carried on the
/// view), never fabricated at the edge.
Map<String, Object?> fixturePredictionViewToJson(FixturePredictionView view) {
  final prediction = view.prediction;
  return FixturePredictionDto(
    id: prediction.id.value,
    participantId: prediction.participantId.value,
    fixtureId: prediction.fixture.value,
    submittedAt: view.submittedAt.toIso8601String(),
    homeGoals: prediction.homeGoals,
    awayGoals: prediction.awayGoals,
    isDouble: prediction.isDouble,
  ).toJson();
}
