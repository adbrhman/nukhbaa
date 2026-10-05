import 'package:application/src/common/clock.dart';
import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/competition/ports/fixture_schedule_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/prediction/fixture_prediction_view.dart';
import 'package:application/src/prediction/ports/fixture_prediction_repository.dart';
import 'package:application/src/social/duel_policy.dart';
import 'package:application/src/social/ports/duel_challenge_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Command use-case: create a shareable Duel invitation for one fixture.
///
/// The caller must already have a prediction for the fixture. Application
/// performs cheap read-only preflight checks; migration 0090 remains the final
/// integrity backstop for races and cross-row invariants.
final class CreateDuelChallenge {
  const CreateDuelChallenge({
    required DuelChallengeRepository duels,
    required CompetitionRepository competition,
    required FixturePredictionRepository predictions,
    required FixtureScheduleRepository schedules,
    required Clock clock,
  }) : _duels = duels,
       _competition = competition,
       _predictions = predictions,
       _schedules = schedules,
       _clock = clock;

  final DuelChallengeRepository _duels;
  final CompetitionRepository _competition;
  final FixturePredictionRepository _predictions;
  final FixtureScheduleRepository _schedules;
  final Clock _clock;

  Future<Result<DuelChallenge>> call({
    required AuthenticatedUser principal,
    required String seasonId,
    required String fixtureId,
    int capacity = DuelPolicy.defaultCapacity,
    String? targetUserId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);

    final seasonResult = SeasonId.tryParse(seasonId);
    if (seasonResult is Err<SeasonId>) return Result.err(seasonResult.error);
    final season = (seasonResult as Ok<SeasonId>).value;

    final fixtureResult = FixtureRef.tryParse(fixtureId);
    if (fixtureResult is Err<FixtureRef>)
      return Result.err(fixtureResult.error);
    final fixture = (fixtureResult as Ok<FixtureRef>).value;

    UserId? target;
    if (targetUserId != null) {
      final targetResult = UserId.tryParse(targetUserId);
      if (targetResult is Err<UserId>) return Result.err(targetResult.error);
      target = (targetResult as Ok<UserId>).value;
    }

    final policy = DuelPolicy.validateCapacity(
      capacity: capacity,
      targetUserId: target,
    );
    if (policy is Err<void>) return Result.err(policy.error);

    if (target == principal.userId) {
      return const Result.err(
        AppError.validation(
          'social.duel_self_target',
          'A duel challenge cannot target the challenger',
        ),
      );
    }

    final link = await _predictions.findSeasonFixture(season, fixture);
    if (link is Err<SeasonFixture?>) return Result.err(link.error);
    if ((link as Ok<SeasonFixture?>).value == null) {
      return const Result.err(
        AppError.invariant(
          'social.duel_fixture_not_in_season',
          'The fixture is not part of this season',
        ),
      );
    }

    final participantResult = await _competition.findParticipant(
      season,
      principal.userId,
    );
    if (participantResult is Err<Participant?>) {
      return Result.err(participantResult.error);
    }
    final participant = (participantResult as Ok<Participant?>).value;
    if (participant == null || participant.status != ParticipantStatus.active) {
      return const Result.err(
        AppError.invariant(
          'social.duel_challenger_not_participant',
          'You must be an active participant in the season',
        ),
      );
    }

    final prediction = await _predictions.findByFixtureAndParticipant(
      fixture,
      participant.id,
    );
    if (prediction is Err<FixturePredictionView?>) {
      return Result.err(prediction.error);
    }
    if ((prediction as Ok<FixturePredictionView?>).value == null) {
      return const Result.err(
        AppError.invariant(
          'social.duel_prediction_required',
          'You must submit a prediction before creating a duel',
        ),
      );
    }

    final scheduleResult = await _schedules.findByFixture(fixture);
    if (scheduleResult is Err<FixtureSchedule?>) {
      return Result.err(scheduleResult.error);
    }
    final schedule = (scheduleResult as Ok<FixtureSchedule?>).value;
    if (schedule == null) {
      return const Result.err(
        AppError.invariant(
          'social.duel_fixture_not_scheduled',
          'The fixture has no registered kickoff time',
        ),
      );
    }
    final now = _clock.nowUtc();
    if (!schedule.kickoffAt.isAfter(
      now.add(const Duration(minutes: DuelPolicy.minimumLeadMinutes)),
    )) {
      return const Result.err(
        AppError.invariant(
          'social.duel_minimum_lead_time',
          'A duel must be created at least 30 minutes before kickoff',
        ),
      );
    }

    return _duels.createChallenge(
      seasonId: season,
      fixture: fixture,
      challengerParticipantId: participant.id,
      targetUserId: target,
      capacity: capacity,
      nowUtc: now,
    );
  }
}
