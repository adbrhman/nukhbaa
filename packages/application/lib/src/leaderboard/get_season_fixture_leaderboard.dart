import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/ledger/ports/participant_reader.dart';
import 'package:application/src/prediction/ports/fixture_prediction_repository.dart';
import 'package:application/src/scoring/ports/fixture_score_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: read a season's **live, "monthly" fixture leaderboard** —
/// the Axiom 4 Amendment sibling of `GetRoundLeaderboard`, scoped to every
/// individually-scored fixture linked to the season instead of a single
/// round.
///
/// A fixture leaderboard is a **read-side projection** aggregating every
/// already-computed `ParticipantFixtureScore` for the season's fixtures
/// (Axiom 5: the SAME points `ScoreFixture` already produced — this never
/// computes or stores a point total of its own). Unlike `GetRoundLeaderboard`
/// (gated on the round being fully `scored`), this board is **live/partial
/// by construction**: it reflects whatever has been scored so far, mirroring
/// the platform's live/partial scoring philosophy (Axiom 4 Amendment —
/// scoring runs the instant a fixture's result lands, never waiting on the
/// rest of the season).
///
/// Visibility gate: only a **member of the season** may view it — the same
/// gate as `GetSeasonLeaderboard` (any participant status; a withdrawn
/// member keeps their competitive record). A non-member is refused
/// [ErrorKind.authorization] `leaderboard.not_a_participant`.
///
/// Never throws; returns a typed [Result].
final class GetSeasonFixtureLeaderboard {
  /// Creates the use-case over its collaborators.
  const GetSeasonFixtureLeaderboard({
    required CompetitionRepository competitionRepository,
    required FixturePredictionRepository fixturePredictionRepository,
    required FixtureScoreRepository fixtureScoreRepository,
    required ParticipantReader participantReader,
  }) : _competition = competitionRepository,
       _fixturePredictions = fixturePredictionRepository,
       _fixtureScores = fixtureScoreRepository,
       _participants = participantReader;

  final CompetitionRepository _competition;
  final FixturePredictionRepository _fixturePredictions;
  final FixtureScoreRepository _fixtureScores;
  final ParticipantReader _participants;

  /// Returns the live `FixtureLeaderboard` for [seasonId], visible to
  /// [principal] as a member of that season.
  Future<Result<FixtureLeaderboard>> call({
    required AuthenticatedUser principal,
    required String seasonId,
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

    // Visibility: only a member of the season sees its standings — same gate
    // and error code as GetSeasonLeaderboard.
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
          'leaderboard.not_a_participant',
          'Only a member of the season may view its leaderboard',
        ),
      );
    }

    final fixturesResult = await _fixturePredictions.listSeasonFixtures(sId);
    if (fixturesResult is Err<List<FixtureRef>>) {
      return Result.err(fixturesResult.error);
    }
    final fixtures = (fixturesResult as Ok<List<FixtureRef>>).value;

    final scoresResult = await _fixtureScores.listBySeasonFixtures(fixtures);
    if (scoresResult is Err<List<ParticipantFixtureScore>>) {
      return Result.err(scoresResult.error);
    }
    final scores = (scoresResult as Ok<List<ParticipantFixtureScore>>).value;

    // Resolve each scored participant's display name so the board shows a
    // real name instead of a raw id (mirrors the season-standings VIEW's
    // identity.users join, without a VIEW to join through here since this
    // board is aggregated in-memory from live fixture scores).
    final participantIds = <ParticipantId>{
      for (final score in scores) score.participantId,
    }.toList(growable: false);
    final namesResult = await _participants.findDisplayNames(participantIds);
    if (namesResult is Err<Map<String, String>>) {
      return Result.err(namesResult.error);
    }
    final displayNames = (namesResult as Ok<Map<String, String>>).value;

    return FixtureLeaderboard.rank(
      seasonId: sId,
      scores: scores,
      displayNames: displayNames,
    );
  }
}
