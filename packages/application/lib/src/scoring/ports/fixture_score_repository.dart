import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Persistence port for computed **per-fixture scores**
/// (docs/project-context.md, Axiom 4 Amendment — the per-fixture sibling of
/// `ScoreRepository`, for the new [ParticipantFixtureScore] aggregate; kept
/// as its own port for the same reason `ScoreRepository` is separate from
/// the competition/prediction ports).
///
/// A score is a **server-owned read value** (Axioms 2/5): only `ScoreFixture`
/// (fed by the pure `Scoring.scoreFixture`) ever produces the
/// [ParticipantFixtureScore]s written here.
///
/// General contract for every method (Application ADR, Section 2):
/// * MUST NOT throw — every outcome is a typed [Result].
/// * MUST map infrastructure failures to [ErrorKind.transient].
/// * MUST map a storage-only integrity conflict to [ErrorKind.invariant].
abstract interface class FixtureScoreRepository {
  /// Persists every [scores] entry for a fixture **atomically**
  /// (all-or-nothing), replacing any previously stored score for the same
  /// `(fixture, participant)` in place so re-scoring is idempotent.
  ///
  /// Every [ParticipantFixtureScore] in [scores] MUST share the same
  /// fixture; the adapter does not mix fixtures in a single call.
  Future<Result<void>> saveFixtureScores(
    List<ParticipantFixtureScore> scores,
  );

  /// Lists every participant's [ParticipantFixtureScore] for [fixture],
  /// ordered by participant id for a stable read. An empty list means the
  /// fixture has not been scored yet.
  Future<Result<List<ParticipantFixtureScore>>> listByFixture(
    FixtureRef fixture,
  );
}
