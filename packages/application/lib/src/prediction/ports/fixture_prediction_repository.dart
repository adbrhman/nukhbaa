import 'package:application/src/prediction/fixture_prediction_view.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Persistence port for the per-fixture Prediction context
/// (docs/project-context.md, Axiom 4 Amendment — replaces the round-scoped
/// [PredictionRepository] for the new [FixturePrediction] aggregate; kept as
/// its own port rather than merged into it, exactly as [PredictionRepository]
/// was kept separate from `CompetitionRepository` — Database ADR, Section 1).
///
/// General contract for every method (Application ADR, Section 2):
/// * MUST NOT throw — every outcome is a typed [Result].
/// * MUST map infrastructure failures to [ErrorKind.transient].
/// * MUST map a storage-only integrity conflict (the unique
///   `(participant_id, fixture_id)` violation) to [ErrorKind.invariant]
///   `prediction.already_submitted`.
abstract interface class FixturePredictionRepository {
  /// Finds the single prediction for `(fixture, participantId)`, or
  /// `Ok(null)` when the participant has not yet predicted this fixture.
  Future<Result<FixturePredictionView?>> findByFixtureAndParticipant(
    FixtureRef fixture,
    ParticipantId participantId,
  );

  /// Persists a brand-new [prediction] stamped [submittedAt] (UTC).
  Future<Result<void>> save(FixturePrediction prediction, DateTime submittedAt);

  /// Persists an amended [prediction] in place, refreshing [submittedAt]
  /// (UTC). Identity (`id`, `fixture`, `participantId`) is unchanged — an
  /// amendment is the same row, never a second prediction.
  Future<Result<void>> update(
    FixturePrediction prediction,
    DateTime submittedAt,
  );

  /// Returns the `SeasonFixture` link for `(seasonId, fixture)`, or
  /// `Ok(null)` when the fixture is not linked to that season — the
  /// per-fixture replacement for the old round-fixture membership check,
  /// kept here (not on `CompetitionRepository`) for the same reason the
  /// round-fixture read was: it keeps that port frozen.
  Future<Result<SeasonFixture?>> findSeasonFixture(
    SeasonId seasonId,
    FixtureRef fixture,
  );

  /// Counts how many fixtures [participantId] has already marked as their
  /// double whose kickoff falls on the UTC calendar day [dayUtc] (midnight
  /// UTC of that day), optionally excluding [excludingFixture] (an amendment
  /// of an already-double fixture must not count itself) — the query
  /// [DailyDoublePolicy] is checked against.
  Future<Result<int>> countDoublesOnDay(
    ParticipantId participantId,
    DateTime dayUtc, {
    FixtureRef? excludingFixture,
  });

  /// Lists every participant's [FixturePredictionView] for [fixture],
  /// unordered — the per-fixture replacement for the round-wide
  /// `listByRound`, used by `ScoreFixture` to grade every participant who
  /// predicted this fixture.
  Future<Result<List<FixturePredictionView>>> listByFixture(FixtureRef fixture);

  /// Lists every fixture linked to [seasonId] via
  /// `competition.season_fixtures`, ordered by display order — the
  /// season-scoped fixture set the live "monthly" fixture leaderboard
  /// aggregates over (Axiom 4 Amendment). A season with no linked fixtures
  /// (or one that does not exist) yields `Ok(<empty list>)`.
  Future<Result<List<FixtureRef>>> listSeasonFixtures(SeasonId seasonId);
}
