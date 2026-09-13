import 'package:application/src/admin/audit_recorder.dart';
import 'package:application/src/admin/ports/user_admin_repository.dart';
import 'package:application/src/competition/ports/fixture_schedule_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/prediction/fixture_prediction_view.dart';
import 'package:application/src/prediction/ports/fixture_prediction_repository.dart';
import 'package:application/src/scoring/ports/fixture_result_repository.dart';
import 'package:application/src/scoring/ports/fixture_score_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Admin read for ONE selected user's fixture-prediction history.
///
/// The repository query is scoped by user id (`FixturePredictionRepository.listByUser`),
/// so the client never receives a cross-user prediction collection. Schedules,
/// results and server-computed scores are joined on the server to build the
/// report. No points are calculated by the client and no ledger is touched.
final class AdminGetUserFixturePredictions {
  const AdminGetUserFixturePredictions({
    required UserAdminRepository userAdminRepository,
    required FixturePredictionRepository fixturePredictionRepository,
    required FixtureScheduleRepository fixtureScheduleRepository,
    required FixtureResultRepository fixtureResultRepository,
    required FixtureScoreRepository fixtureScoreRepository,
    required AuditRecorder auditRecorder,
  }) : _users = userAdminRepository,
       _predictions = fixturePredictionRepository,
       _schedules = fixtureScheduleRepository,
       _results = fixtureResultRepository,
       _scores = fixtureScoreRepository,
       _audit = auditRecorder;

  final UserAdminRepository _users;
  final FixturePredictionRepository _predictions;
  final FixtureScheduleRepository _schedules;
  final FixtureResultRepository _results;
  final FixtureScoreRepository _scores;
  final AuditRecorder _audit;

  Future<Result<AdminUserPredictionHistory>> call({
    required AuthenticatedUser principal,
    required String userId,
    DateTime? fromUtc,
    DateTime? toUtc,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);

    final parsedUser = UserId.tryParse(userId);
    if (parsedUser is Err<UserId>) return Result.err(parsedUser.error);
    final targetId = (parsedUser as Ok<UserId>).value;

    final rangeError = _validateRange(fromUtc, toUtc);
    if (rangeError != null) return Result.err(rangeError);

    final userResult = await _users.findUserById(targetId);
    if (userResult is Err<User?>) return Result.err(userResult.error);
    final user = (userResult as Ok<User?>).value;
    if (user == null) {
      return const Result.err(
        AppError.invariant('identity.user_not_found', 'User was not found'),
      );
    }

    final audit = await _audit.record(
      actorId: principal.userId,
      action: AuditAction.userPredictionsViewed,
      targetRef: targetId.value,
    );
    if (audit is Err<AuditEntry>) return Result.err(audit.error);

    final predictionResult = await _predictions.listByUser(targetId);
    if (predictionResult is Err<List<FixturePredictionView>>) {
      return Result.err(predictionResult.error);
    }
    final views = (predictionResult as Ok<List<FixturePredictionView>>).value;
    if (views.isEmpty) {
      return Result.ok(
        AdminUserPredictionHistory(
          user: user,
          predictions: const [],
          predictionCount: 0,
          exactCount: 0,
          correctDoubleCount: 0,
          totalPoints: 0,
        ),
      );
    }

    final fixtureRefs = <FixtureRef>{
      for (final view in views) view.prediction.fixture,
    }.toList(growable: false);

    final schedulesResult = await _schedules.findByFixtures(fixtureRefs);
    if (schedulesResult is Err<List<FixtureSchedule>>) {
      return Result.err(schedulesResult.error);
    }
    final schedules = (schedulesResult as Ok<List<FixtureSchedule>>).value;
    final scheduleByFixture = <String, FixtureSchedule>{
      for (final schedule in schedules) schedule.fixture.value: schedule,
    };

    for (final view in views) {
      if (!scheduleByFixture.containsKey(view.prediction.fixture.value)) {
        return const Result.err(
          AppError.transient(
            'competition.fixture_schedule_missing',
            'A stored prediction has no fixture schedule',
          ),
        );
      }
    }

    final filteredViews = views
        .where((view) {
          final kickoff =
              scheduleByFixture[view.prediction.fixture.value]!.kickoffAt;
          return _inRange(kickoff, fromUtc, toUtc);
        })
        .toList(growable: false);

    if (filteredViews.isEmpty) {
      return Result.ok(
        AdminUserPredictionHistory(
          user: user,
          predictions: const [],
          predictionCount: 0,
          exactCount: 0,
          correctDoubleCount: 0,
          totalPoints: 0,
        ),
      );
    }

    final filteredFixtures = <FixtureRef>{
      for (final view in filteredViews) view.prediction.fixture,
    }.toList(growable: false);

    final resultResult = await _results.findByFixtures(filteredFixtures);
    if (resultResult is Err<List<FixtureResult>>) {
      return Result.err(resultResult.error);
    }
    final results = (resultResult as Ok<List<FixtureResult>>).value;
    final resultByFixture = <String, FixtureResult>{
      for (final result in results) result.fixture.value: result,
    };

    final scoreResult = await _scores.listBySeasonFixtures(filteredFixtures);
    if (scoreResult is Err<List<ParticipantFixtureScore>>) {
      return Result.err(scoreResult.error);
    }
    final scores = (scoreResult as Ok<List<ParticipantFixtureScore>>).value;
    final scoreByKey = <String, ParticipantFixtureScore>{
      for (final score in scores)
        _scoreKey(score.participantId, score.fixture): score,
    };

    final built = <AdminUserPrediction>[];
    for (final view in filteredViews) {
      final prediction = view.prediction;
      final schedule = scheduleByFixture[prediction.fixture.value]!;
      final actual = resultByFixture[prediction.fixture.value];
      final score =
          scoreByKey[_scoreKey(prediction.participantId, prediction.fixture)];
      built.add(
        AdminUserPrediction(
          predictionId: prediction.id,
          fixtureId: prediction.fixture,
          kickoffAt: schedule.kickoffAt,
          leagueName: schedule.leagueName,
          leagueLogoUrl: schedule.leagueLogoUrl,
          homeTeam: schedule.homeTeam,
          awayTeam: schedule.awayTeam,
          predictedHomeGoals: prediction.homeGoals,
          predictedAwayGoals: prediction.awayGoals,
          finalHomeGoals: actual?.homeGoals,
          finalAwayGoals: actual?.awayGoals,
          grade: score?.result.grade ?? FixtureScoreGrade.pending,
          isDouble: prediction.isDouble,
          points: score?.points,
        ),
      );
    }

    built.sort((a, b) {
      final byKickoff = a.kickoffAt.compareTo(b.kickoffAt);
      if (byKickoff != 0) return byKickoff;
      return a.fixtureId.value.compareTo(b.fixtureId.value);
    });

    var exactCount = 0;
    var correctDoubleCount = 0;
    var totalPoints = 0;
    for (final row in built) {
      if (row.grade == FixtureScoreGrade.exactScoreline) {
        exactCount++;
        if (row.isDouble) correctDoubleCount++;
      }
      totalPoints += row.points ?? 0;
    }

    return Result.ok(
      AdminUserPredictionHistory(
        user: user,
        predictions: built,
        predictionCount: built.length,
        exactCount: exactCount,
        correctDoubleCount: correctDoubleCount,
        totalPoints: totalPoints,
      ),
    );
  }

  static String _scoreKey(ParticipantId participant, FixtureRef fixture) =>
      '${participant.value}|${fixture.value}';

  static bool _inRange(DateTime kickoff, DateTime? fromUtc, DateTime? toUtc) {
    final instant = kickoff.toUtc();
    final from = fromUtc?.toUtc();
    final to = toUtc?.toUtc();
    if (from != null && instant.isBefore(from)) return false;
    if (to != null && !instant.isBefore(to)) return false;
    return true;
  }

  static AppError? _validateRange(DateTime? fromUtc, DateTime? toUtc) {
    if ((fromUtc == null) != (toUtc == null)) {
      return const AppError.validation(
        'admin.predictions_invalid_range',
        'Both range boundaries are required',
      );
    }
    if (fromUtc != null && toUtc != null && !toUtc.isAfter(fromUtc)) {
      return const AppError.validation(
        'admin.predictions_invalid_range',
        'The prediction range is invalid',
      );
    }
    return null;
  }
}

/// Server-composed report model; [totalPoints] and row [points] originate from
/// the Scoring read model and are not calculated on the client.
final class AdminUserPredictionHistory {
  const AdminUserPredictionHistory({
    required this.user,
    required this.predictions,
    required this.predictionCount,
    required this.exactCount,
    required this.correctDoubleCount,
    required this.totalPoints,
  });

  final User user;
  final List<AdminUserPrediction> predictions;
  final int predictionCount;
  final int exactCount;
  final int correctDoubleCount;
  final int totalPoints;
}

final class AdminUserPrediction {
  const AdminUserPrediction({
    required this.predictionId,
    required this.fixtureId,
    required this.kickoffAt,
    required this.homeTeam,
    required this.awayTeam,
    required this.predictedHomeGoals,
    required this.predictedAwayGoals,
    required this.grade,
    required this.isDouble,
    this.leagueName,
    this.leagueLogoUrl,
    this.finalHomeGoals,
    this.finalAwayGoals,
    this.points,
  });

  final PredictionId predictionId;
  final FixtureRef fixtureId;
  final DateTime kickoffAt;
  final String? leagueName;
  final String? leagueLogoUrl;
  final String homeTeam;
  final String awayTeam;
  final int predictedHomeGoals;
  final int predictedAwayGoals;
  final int? finalHomeGoals;
  final int? finalAwayGoals;
  final FixtureScoreGrade grade;
  final bool isDouble;
  final int? points;
}
