import 'package:application/src/common/clock.dart';
import 'package:application/src/common/id_generator.dart';
import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/competition/ports/fixture_schedule_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/prediction/fixture_prediction_view.dart';
import 'package:application/src/prediction/ports/fixture_prediction_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Use-case: submit (or amend) a participant's prediction for a single
/// fixture (docs/project-context.md, Axiom 4 Amendment — replaces the
/// round-scoped `SubmitPrediction`'s atomic batch with one independent
/// submission per fixture, so a participant can predict one fixture "or
/// more" without waiting on the rest of any round).
///
/// The client names the [seasonId] it is predicting under (there is no round
/// to derive it from anymore) plus the [fixtureId]; the participant is
/// resolved server-side from the verified principal + that season, exactly
/// as `SubmitPrediction` did (Axiom 2: never trust a client-supplied
/// participant id). Points are never accepted or computed here (Axioms 2/5).
///
/// Business invariants enforced (in order):
/// 1. **The fixture belongs to the season** — via `SeasonFixture`
///    (`prediction.fixture_not_in_season`; the per-fixture replacement for
///    the old `fixture_not_in_round` check now that `RoundFixture` is gone).
/// 2. **The caller is a participant of that season**
///    (`prediction.not_a_participant`).
/// 3. **The fixture has not kicked off** — [FixtureLock], computed from the
///    fixture's own [FixtureSchedule.kickoffAt] against the clock
///    (`prediction.fixture_locked`). A fixture with no registered schedule is
///    treated as not locked, matching `SubmitPrediction`.
/// 4. **At most one double per participant per UTC calendar day** — checked
///    against [FixturePredictionRepository.countDoublesOnDay] for the
///    fixture's kickoff day, excluding this fixture itself so re-marking an
///    already-double fixture on amend never double-counts
///    (`prediction.daily_double_exceeded`). Only checked when [isDouble] is
///    true.
///
/// **Idempotent**: a first call for `(fixture, participant)` inserts; a
/// repeat call amends the existing prediction in place — one row per
/// `(fixture, participant)`, never a second.
///
/// Never throws; returns a typed [Result].
final class SubmitFixturePrediction {
  /// Creates the use-case over its collaborators.
  const SubmitFixturePrediction({
    required FixturePredictionRepository fixturePredictionRepository,
    required CompetitionRepository competitionRepository,
    required FixtureScheduleRepository fixtureScheduleRepository,
    required IdGenerator idGenerator,
    required Clock clock,
  }) : _fixturePredictions = fixturePredictionRepository,
       _competition = competitionRepository,
       _fixtureSchedules = fixtureScheduleRepository,
       _idGenerator = idGenerator,
       _clock = clock;

  final FixturePredictionRepository _fixturePredictions;
  final CompetitionRepository _competition;
  final FixtureScheduleRepository _fixtureSchedules;
  final IdGenerator _idGenerator;
  final Clock _clock;

  /// Submits (or amends) [homeGoals]-[awayGoals] as [principal]'s prediction
  /// for fixture [fixtureId] under season [seasonId].
  Future<Result<FixturePredictionView>> call({
    required AuthenticatedUser principal,
    required String seasonId,
    required String fixtureId,
    required int homeGoals,
    required int awayGoals,
    bool isDouble = false,
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

    final fixtureRefResult = FixtureRef.tryParse(fixtureId);
    if (fixtureRefResult is Err<FixtureRef>) {
      return Result.err(fixtureRefResult.error);
    }
    final fixture = (fixtureRefResult as Ok<FixtureRef>).value;

    // Rule 1: the fixture must belong to the season.
    final linkResult = await _fixturePredictions.findSeasonFixture(
      sId,
      fixture,
    );
    if (linkResult is Err<SeasonFixture?>) {
      return Result.err(linkResult.error);
    }
    if ((linkResult as Ok<SeasonFixture?>).value == null) {
      return Result.err(
        AppError.validation(
          'prediction.fixture_not_in_season',
          'Fixture ${fixture.value} is not part of this season',
        ),
      );
    }

    // Rule 2: resolve the caller's participant in this season.
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
        AppError.invariant(
          'prediction.not_a_participant',
          'You must join the season before submitting a prediction',
        ),
      );
    }

    // Rule 3: the fixture must not have kicked off yet. No registered
    // schedule is treated as not locked (mirrors SubmitPrediction). A
    // synthetic "well after now" kickoff stands in for FixtureLock's pure
    // comparison when there is no real schedule to compare against.
    final schedulesResult = await _fixtureSchedules.findByFixtures([fixture]);
    if (schedulesResult is Err<List<FixtureSchedule>>) {
      return Result.err(schedulesResult.error);
    }
    final schedules = (schedulesResult as Ok<List<FixtureSchedule>>).value;
    final now = _clock.nowUtc();
    final kickoffAt = schedules.isEmpty ? null : schedules.first.kickoffAt;
    final effectiveKickoff = kickoffAt ?? now.add(const Duration(days: 1));

    final lockResult = FixtureLock.at(
      kickoffAt: effectiveKickoff,
      nowUtc: now,
    );
    if (lockResult is Err<FixtureLock>) {
      return Result.err(lockResult.error);
    }
    final lock = (lockResult as Ok<FixtureLock>).value;
    if (lock.isLocked) {
      return Result.err(
        AppError.invariant(
          'prediction.fixture_locked',
          'Fixture ${fixture.value} has already kicked off and can no '
              'longer be predicted',
        ),
      );
    }

    // Rule 4: at most one double per UTC calendar day, only when marking one.
    if (isDouble) {
      final dayReference = kickoffAt ?? now;
      final dayUtc = DateTime.utc(
        dayReference.year,
        dayReference.month,
        dayReference.day,
      );
      final countResult = await _fixturePredictions.countDoublesOnDay(
        participant.id,
        dayUtc,
        excludingFixture: fixture,
      );
      if (countResult is Err<int>) {
        return Result.err(countResult.error);
      }
      final existingDoubles = (countResult as Ok<int>).value;
      if (!DailyDoublePolicy.allowsAnotherDouble(existingDoubles)) {
        return Result.err(
          AppError.invariant(
            'prediction.daily_double_exceeded',
            'Only one fixture may be marked as your double per day',
          ),
        );
      }
    }

    // Idempotency read: first submission inserts, a repeat amends.
    final existingResult = await _fixturePredictions
        .findByFixtureAndParticipant(fixture, participant.id);
    if (existingResult is Err<FixturePredictionView?>) {
      return Result.err(existingResult.error);
    }
    final existing = (existingResult as Ok<FixturePredictionView?>).value;

    if (existing != null) {
      return _amend(existing.prediction, lock, homeGoals, awayGoals, isDouble, now);
    }
    return _insert(
      fixture,
      participant.id,
      lock,
      homeGoals,
      awayGoals,
      isDouble,
      now,
    );
  }

  Future<Result<FixturePredictionView>> _insert(
    FixtureRef fixture,
    ParticipantId participantId,
    FixtureLock lock,
    int homeGoals,
    int awayGoals,
    bool isDouble,
    DateTime now,
  ) async {
    final idResult = PredictionId.tryParse(_idGenerator.newUuid());
    if (idResult is Err<PredictionId>) {
      return Result.err(idResult.error);
    }

    final predictionResult = FixturePrediction.submit(
      id: (idResult as Ok<PredictionId>).value,
      fixture: fixture,
      participantId: participantId,
      lock: lock,
      homeGoals: homeGoals,
      awayGoals: awayGoals,
      isDouble: isDouble,
    );
    if (predictionResult is Err<FixturePrediction>) {
      return Result.err(predictionResult.error);
    }
    final prediction = (predictionResult as Ok<FixturePrediction>).value;

    final saved = await _fixturePredictions.save(prediction, now);
    return switch (saved) {
      Ok<void>() => Result.ok(
        FixturePredictionView(prediction: prediction, submittedAt: now),
      ),
      Err<void>(:final error) =>
        error.code == 'prediction.already_submitted'
            ? await _resolveConflictThenAmend(
                fixture,
                participantId,
                lock,
                homeGoals,
                awayGoals,
                isDouble,
                now,
                error,
              )
            : Result.err(error),
    };
  }

  Future<Result<FixturePredictionView>> _amend(
    FixturePrediction existing,
    FixtureLock lock,
    int homeGoals,
    int awayGoals,
    bool isDouble,
    DateTime now,
  ) async {
    final amendedResult = existing.amend(
      lock: lock,
      homeGoals: homeGoals,
      awayGoals: awayGoals,
      isDouble: isDouble,
    );
    if (amendedResult is Err<FixturePrediction>) {
      return Result.err(amendedResult.error);
    }
    final amended = (amendedResult as Ok<FixturePrediction>).value;

    final updated = await _fixturePredictions.update(amended, now);
    return switch (updated) {
      Ok<void>() => Result.ok(
        FixturePredictionView(prediction: amended, submittedAt: now),
      ),
      Err<void>(:final error) => Result.err(error),
    };
  }

  Future<Result<FixturePredictionView>> _resolveConflictThenAmend(
    FixtureRef fixture,
    ParticipantId participantId,
    FixtureLock lock,
    int homeGoals,
    int awayGoals,
    bool isDouble,
    DateTime now,
    AppError insertError,
  ) async {
    final reread = await _fixturePredictions.findByFixtureAndParticipant(
      fixture,
      participantId,
    );
    return switch (reread) {
      Ok<FixturePredictionView?>(:final value) =>
        value != null
            ? await _amend(value.prediction, lock, homeGoals, awayGoals, isDouble, now)
            : Result.err(insertError),
      Err<FixturePredictionView?>(:final error) => Result.err(error),
    };
  }
}
