import 'package:application/src/common/clock.dart';
import 'package:application/src/competition/fixture_visibility.dart';
import 'package:application/src/competition/ports/competition_repository.dart';
import 'package:application/src/competition/ports/fixture_schedule_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/ledger/ports/participant_reader.dart';
import 'package:application/src/prediction/fixture_prediction_view.dart';
import 'package:application/src/prediction/ports/fixture_prediction_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Every participant's prediction for one fixture, and the name each one
/// plays under -- the read behind "everyone's predictions" on a match card.
final class FixturePredictionReveal {
  /// Creates the reveal of [predictions] with their [displayNames].
  const FixturePredictionReveal({
    required this.predictions,
    required this.displayNames,
  });

  /// Every stored prediction for the fixture, unordered.
  final List<FixturePredictionView> predictions;

  /// Participant id value -> display name. A participant without a name is
  /// simply absent.
  final Map<String, String> displayNames;
}

/// Query use-case: list every participant's prediction for a fixture -- but
/// only **once the fixture has kicked off** (the per-fixture sibling of
/// `ListRoundPredictions`, decided 2026-09-28).
///
/// This is the fair-play gate: before kickoff a forecast is private, because
/// revealing it would let a caller copy it. The gate is the SAME instant that
/// closes submission -- [FixtureLock] over the fixture's own schedule and the
/// server [Clock] -- so there is no moment in which a prediction can still be
/// changed and another one can already be seen. The device clock plays no
/// part.
///
/// Refusals, in order:
/// * not a member of the season: [ErrorKind.authorization]
///   `prediction.not_a_participant`;
/// * the fixture is not linked to the season: [ErrorKind.invariant]
///   `prediction.fixture_not_in_season`;
/// * no registered kickoff, or kickoff still ahead: [ErrorKind.invariant]
///   `prediction.fixture_not_started`. A fixture without a kickoff stays
///   hidden -- absence of a kickoff is not evidence that it has passed (the
///   same rule `SubmitFixturePrediction` applies).
///
/// Never throws; returns a typed [Result].
final class ListFixturePredictions {
  /// Creates the use-case over its collaborators.
  const ListFixturePredictions({
    required CompetitionRepository competitionRepository,
    required FixturePredictionRepository fixturePredictionRepository,
    required FixtureScheduleRepository fixtureScheduleRepository,
    required ParticipantReader participantReader,
    required Clock clock,
  }) : _competition = competitionRepository,
       _fixturePredictions = fixturePredictionRepository,
       _schedules = fixtureScheduleRepository,
       _participants = participantReader,
       _clock = clock;

  final CompetitionRepository _competition;
  final FixturePredictionRepository _fixturePredictions;
  final FixtureScheduleRepository _schedules;
  final ParticipantReader _participants;
  final Clock _clock;

  /// Reveals every prediction for [fixtureId] within [seasonId] to
  /// [principal], a member of that season, once the fixture has kicked off.
  Future<Result<FixturePredictionReveal>> call({
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

    final participantResult = await _competition.findParticipant(
      sId,
      principal.userId,
    );
    if (participantResult is Err<Participant?>) {
      return Result.err(participantResult.error);
    }
    if ((participantResult as Ok<Participant?>).value == null) {
      return const Result.err(
        AppError.authorization(
          'prediction.not_a_participant',
          'Only a member of the season may view its predictions',
        ),
      );
    }

    final linkResult = await _fixturePredictions.findSeasonFixture(
      sId,
      fixture,
    );
    if (linkResult is Err<SeasonFixture?>) {
      return Result.err(linkResult.error);
    }
    if ((linkResult as Ok<SeasonFixture?>).value == null) {
      return const Result.err(
        AppError.invariant(
          'prediction.fixture_not_in_season',
          'This fixture is not linked to the given season',
        ),
      );
    }

    final schedulesResult = await _schedules.findByFixtures([fixture]);
    if (schedulesResult is Err<List<FixtureSchedule>>) {
      return Result.err(schedulesResult.error);
    }
    final schedules = (schedulesResult as Ok<List<FixtureSchedule>>).value;
    if (schedules.isEmpty) {
      return const Result.err(_notStarted);
    }
    // A hidden fixture reveals nothing, and a test fixture reveals its
    // predictions to admins only (migration 0098).
    if (!FixtureVisibility.playable(principal, schedules.first)) {
      return const Result.err(FixtureVisibility.unavailable);
    }
    final lockResult = FixtureLock.at(
      kickoffAt: schedules.first.kickoffAt.toUtc(),
      nowUtc: _clock.nowUtc(),
    );
    if (lockResult is Err<FixtureLock>) {
      return Result.err(lockResult.error);
    }
    if (!(lockResult as Ok<FixtureLock>).value.isLocked) {
      return const Result.err(_notStarted);
    }

    final predictionsResult = await _fixturePredictions.listByFixture(fixture);
    if (predictionsResult is Err<List<FixturePredictionView>>) {
      return Result.err(predictionsResult.error);
    }
    final predictions =
        (predictionsResult as Ok<List<FixturePredictionView>>).value;
    if (predictions.isEmpty) {
      return const Result.ok(
        FixturePredictionReveal(
          predictions: <FixturePredictionView>[],
          displayNames: <String, String>{},
        ),
      );
    }

    final namesResult = await _participants.findDisplayNames([
      for (final view in predictions) view.prediction.participantId,
    ]);
    if (namesResult is Err<Map<String, String>>) {
      return Result.err(namesResult.error);
    }

    return Result.ok(
      FixturePredictionReveal(
        predictions: predictions,
        displayNames: (namesResult as Ok<Map<String, String>>).value,
      ),
    );
  }

  static const AppError _notStarted = AppError.invariant(
    'prediction.fixture_not_started',
    'Predictions stay hidden until the fixture kicks off',
  );
}
