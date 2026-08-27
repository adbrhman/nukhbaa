import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/prediction/ports/fixture_prediction_repository.dart';
import 'package:application/src/scoring/ports/fixture_score_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: read every participant's computed score for a single
/// fixture within a season (docs/project-context.md, Axiom 4 Amendment —
/// Step 1 of the 7.10.x Round -> Season/Fixture migration; the per-fixture
/// sibling of [GetRoundScores]).
///
/// Visibility gate: unlike [GetRoundScores] (which blocks all results until
/// the round is fully `RoundStatus.scored`), this follows
/// [GetSeasonFixtureLeaderboard]'s live/partial philosophy — only membership
/// in the season is required. An empty list before the fixture has been
/// scored is a legitimate result, never an error.
///
/// [seasonId] is required (Axiom 3/4: a fixture has no owning season of its
/// own) so [fixtureId]'s season link can be verified via
/// [FixturePredictionRepository.findSeasonFixture] before reading scores. A
/// fixture not linked to [seasonId] is rejected [ErrorKind.invariant]
/// `prediction.fixture_not_in_season` — the same code
/// `SubmitFixturePrediction` uses for the identical condition.
///
/// Never throws; returns a typed [Result].
final class GetFixtureScores {
  /// Creates the use-case over its collaborators.
  const GetFixtureScores({
    required CompetitionRepository competitionRepository,
    required FixturePredictionRepository fixturePredictionRepository,
    required FixtureScoreRepository fixtureScoreRepository,
  }) : _competition = competitionRepository,
       _fixturePredictions = fixturePredictionRepository,
       _fixtureScores = fixtureScoreRepository;

  final CompetitionRepository _competition;
  final FixturePredictionRepository _fixturePredictions;
  final FixtureScoreRepository _fixtureScores;

  /// Lists every participant's [ParticipantFixtureScore] for [fixtureId]
  /// within [seasonId], visible to [principal] as a member of that season.
  Future<Result<List<ParticipantFixtureScore>>> call({
    required AuthenticatedUser principal,
    required String seasonId,
    required String fixtureId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final seasonIdResult = SeasonId.tryParse(seasonId);
    if (seasonIdResult is Err<SeasonId>) {
      return Result.err(seasonIdResult.error);
    }
    final sId = (seasonIdResult as Ok<SeasonId>).value;

    final fixtureResult = FixtureRef.tryParse(fixtureId);
    if (fixtureResult is Err<FixtureRef>) {
      return Result.err(fixtureResult.error);
    }
    final fixture = (fixtureResult as Ok<FixtureRef>).value;

    // Visibility: only a member of the season sees its fixtures' scores —
    // same gate GetRoundScores uses, mirrored to the fixture context.
    final participantResult = await _competition.findParticipant(
      sId,
      principal.userId,
    );
    if (participantResult is Err<Participant?>) {
      return Result.err(participantResult.error);
    }
    final participant = (participantResult as Ok<Participant?>).value;
    if (participant == null) {
      return const Result.err(
        AppError.authorization(
          'scoring.not_a_participant',
          'Only a participant of the season may view its scores',
        ),
      );
    }

    // Membership in the season alone is not enough — the fixture itself must
    // actually be linked to this season (Axiom 3/4).
    final linkResult = await _fixturePredictions.findSeasonFixture(
      sId,
      fixture,
    );
    if (linkResult is Err<SeasonFixture?>) {
      return Result.err(linkResult.error);
    }
    final link = (linkResult as Ok<SeasonFixture?>).value;
    if (link == null) {
      return const Result.err(
        AppError.invariant(
          'prediction.fixture_not_in_season',
          'This fixture is not linked to the given season',
        ),
      );
    }

    // Live/partial by construction: an empty list before scoring is a
    // legitimate result, not an error.
    return _fixtureScores.listByFixture(fixture);
  }
}
