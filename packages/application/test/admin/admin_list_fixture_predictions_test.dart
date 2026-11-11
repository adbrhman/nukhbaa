import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../prediction/fake_fixture_prediction_repository.dart';
import '../prediction/fake_fixture_schedule_repository.dart';
import 'fakes.dart';

const _fixtureId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _otherParticipantId = '88888888-8888-8888-8888-888888888888';
const _predictionId = '66666666-6666-6666-6666-666666666666';

final _submittedAt = DateTime.utc(2026, 8, 1, 12);
final _kickoff = DateTime.utc(2026, 8, 1, 18);

FixturePrediction _prediction(String id, String participantId) =>
    FixturePrediction.fromStored(
      id: PredictionId(id),
      fixture: const FixtureRef(_fixtureId),
      participantId: ParticipantId(participantId),
      homeGoals: 2,
      awayGoals: 1,
    );

void main() {
  late FakeFixturePredictionRepository predictions;
  late FakeFixtureScheduleRepository schedules;
  late InMemoryAuditLogRepository auditLog;

  AdminListFixturePredictions useCaseAt(DateTime now) =>
      AdminListFixturePredictions(
        fixturePredictionRepository: predictions,
        fixtureScheduleRepository: schedules,
        auditRecorder: auditRecorderOver(auditLog),
        clock: FakeClock(now),
      );

  setUp(() {
    predictions = FakeFixturePredictionRepository();
    schedules = FakeFixtureScheduleRepository()
      ..seed(
        FixtureSchedule.fromStored(
          fixture: const FixtureRef(_fixtureId),
          homeTeam: 'Hilal',
          awayTeam: 'Nassr',
          kickoffAt: _kickoff,
        ),
      );
    auditLog = InMemoryAuditLogRepository();
  });

  test('refuses a non-admin caller before any read or audit', () async {
    predictions.seedPrediction(
      _prediction(_predictionId, _otherParticipantId),
      _submittedAt,
    );
    final result = await useCaseAt(_kickoff)(
      principal: principal(userId: adminUuid, role: PlatformRole.user),
      fixtureId: _fixtureId,
    );
    final error = (result as Err<List<FixturePredictionView>>).error;
    expect(error.kind, ErrorKind.authorization);
    expect(error.code, 'auth.insufficient_role');
    expect(auditLog.rows, isEmpty);
  });

  test('rejects a malformed fixture id before any read or audit', () async {
    final result = await useCaseAt(_kickoff)(
      principal: principal(userId: adminUuid),
      fixtureId: 'not-a-uuid',
    );
    final error = (result as Err<List<FixturePredictionView>>).error;
    expect(error.kind, ErrorKind.validation);
    expect(error.code, 'competition.fixture_ref_malformed');
    expect(auditLog.rows, isEmpty);
  });

  group('sealed until kickoff, for the admins too (script 261)', () {
    test('one minute before kickoff an admin reads nothing', () async {
      predictions.seedPrediction(
        _prediction(_predictionId, _otherParticipantId),
        _submittedAt,
      );

      final result =
          await useCaseAt(_kickoff.subtract(const Duration(minutes: 1)))(
            principal: principal(userId: adminUuid),
            fixtureId: _fixtureId,
          );

      final error = (result as Err<List<FixturePredictionView>>).error;
      expect(error.code, 'prediction.fixture_not_started');
      expect(error.kind, ErrorKind.invariant);
      expect(auditLog.rows, isEmpty);
    });

    test('a fixture with no kickoff stays sealed', () async {
      schedules = FakeFixtureScheduleRepository();
      predictions.seedPrediction(
        _prediction(_predictionId, _otherParticipantId),
        _submittedAt,
      );

      final result = await useCaseAt(_kickoff.add(const Duration(days: 1)))(
        principal: principal(userId: adminUuid),
        fixtureId: _fixtureId,
      );

      expect(
        (result as Err<List<FixturePredictionView>>).error.code,
        'prediction.fixture_not_started',
      );
      expect(auditLog.rows, isEmpty);
    });
  });

  test("at kickoff returns every participant's raw prediction for the "
      'fixture, auditing the read', () async {
    predictions.seedPrediction(
      _prediction(_predictionId, _otherParticipantId),
      _submittedAt,
    );

    final result = await useCaseAt(_kickoff)(
      principal: principal(userId: adminUuid),
      fixtureId: _fixtureId,
    );

    final list = (result as Ok<List<FixturePredictionView>>).value;
    expect(list, hasLength(1));
    expect(list.single.prediction.homeGoals, 2);
    expect(list.single.prediction.awayGoals, 1);

    expect(auditLog.rows, hasLength(1));
    expect(auditLog.rows.single.action, AuditAction.fixturePredictionsViewed);
    expect(auditLog.rows.single.targetRef, _fixtureId);
  });

  test(
    'an unpredicted fixture returns an empty list, still auditing the read',
    () async {
      final result = await useCaseAt(_kickoff.add(const Duration(hours: 1)))(
        principal: principal(userId: adminUuid),
        fixtureId: _fixtureId,
      );

      final list = (result as Ok<List<FixturePredictionView>>).value;
      expect(list, isEmpty);
      expect(auditLog.rows, hasLength(1));
    },
  );
}
