import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../prediction/fake_fixture_prediction_repository.dart';
import '../prediction/fake_fixture_schedule_repository.dart';
import '../scoring/fake_fixture_score_repository.dart';
import '../scoring/fakes.dart';
import 'fakes.dart';

const _fixture1 = '77777777-7777-4777-8777-777777777777';
const _fixture2 = '88888888-8888-4888-8888-888888888888';
const _prediction1 = '99999999-9999-4999-8999-999999999999';
const _prediction2 = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _participant = participantUuid;

void main() {
  test(
    'returns only the selected user and server-computed score data',
    () async {
      final users = InMemoryUserAdminRepository();
      final predictions = FakeFixturePredictionRepository();
      final schedules = FakeFixtureScheduleRepository();
      final results = FakeFixtureResultRepository();
      final scores = FakeFixtureScoreRepository();
      final auditLog = InMemoryAuditLogRepository();
      final audit = auditRecorderOver(auditLog);

      final target = storedUser(id: targetUuid, email: 'target@example.com');
      final other = storedUser(
        id: adminUuid,
        email: 'other@example.com',
      ).copyWith(displayName: 'Other');
      users.seed(target);
      users.seed(other);

      final participant = ParticipantId(_participant);
      final fixture1 = FixtureRef(_fixture1);
      final fixture2 = FixtureRef(_fixture2);

      predictions.seedParticipantOwner(participant, target.id);
      predictions.seedPrediction(
        FixturePrediction.fromStored(
          id: PredictionId(_prediction1),
          fixture: fixture1,
          participantId: participant,
          homeGoals: 2,
          awayGoals: 1,
          isDouble: true,
        ),
        DateTime.utc(2026, 9, 13, 10),
      );
      predictions.seedPrediction(
        FixturePrediction.fromStored(
          id: PredictionId(_prediction2),
          fixture: fixture2,
          participantId: participant,
          homeGoals: 0,
          awayGoals: 0,
        ),
        DateTime.utc(2026, 9, 12, 10),
      );

      schedules.seed(
        FixtureSchedule.fromStored(
          fixture: fixture1,
          homeTeam: 'يوفنتوس',
          awayTeam: 'ميلان',
          kickoffAt: DateTime.utc(2026, 9, 13, 18),
          leagueName: 'الدوري الإيطالي',
        ),
      );
      schedules.seed(
        FixtureSchedule.fromStored(
          fixture: fixture2,
          homeTeam: 'روما',
          awayTeam: 'لاتسيو',
          kickoffAt: DateTime.utc(2026, 9, 12, 18),
          leagueName: 'الدوري الإيطالي',
        ),
      );
      results.seed(
        FixtureResult.fromStored(fixture: fixture1, homeGoals: 2, awayGoals: 1),
      );
      results.seed(
        FixtureResult.fromStored(fixture: fixture2, homeGoals: 1, awayGoals: 0),
      );
      final scoreResult = FixtureScoreResult(
        fixture: fixture1,
        grade: FixtureScoreGrade.exactScoreline,
        points: 6,
      );
      await scores.saveFixtureScores([
        ParticipantFixtureScore.fromStored(
          fixture: fixture1,
          participantId: participant,
          rulesetVersion: 1,
          result: scoreResult,
        ),
      ]);

      final useCase = AdminGetUserFixturePredictions(
        userAdminRepository: users,
        fixturePredictionRepository: predictions,
        fixtureScheduleRepository: schedules,
        fixtureResultRepository: results,
        fixtureScoreRepository: scores,
        auditRecorder: audit,
      );

      final result = await useCase(
        principal: principal(userId: adminUuid),
        userId: targetUuid,
        fromUtc: DateTime.utc(2026, 9, 13),
        toUtc: DateTime.utc(2026, 9, 14),
      );

      expect(result, isA<Ok<AdminUserPredictionHistory>>());
      final history = (result as Ok<AdminUserPredictionHistory>).value;
      expect(history.user.id.value, targetUuid);
      expect(history.predictionCount, 1);
      expect(history.exactCount, 1);
      expect(history.correctDoubleCount, 1);
      expect(history.totalPoints, 6);
      expect(history.predictions, hasLength(1));
      expect(history.predictions.single.fixtureId.value, _fixture1);
      expect(history.predictions.single.points, 6);
      expect(
        history.predictions.single.grade,
        FixtureScoreGrade.exactScoreline,
      );
      expect(auditLog.rows.single.action, AuditAction.userPredictionsViewed);
      expect(auditLog.rows.single.targetRef, targetUuid);
    },
  );
}
