import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../prediction/fake_fixture_prediction_repository.dart';
import 'fakes.dart';

const _fixtureId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _otherParticipantId = '88888888-8888-8888-8888-888888888888';
const _predictionId = '66666666-6666-6666-6666-666666666666';

final _submittedAt = DateTime.utc(2026, 8, 1, 12);

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
  late InMemoryAuditLogRepository auditLog;
  late AdminListFixturePredictions useCase;

  setUp(() {
    predictions = FakeFixturePredictionRepository();
    auditLog = InMemoryAuditLogRepository();
    useCase = AdminListFixturePredictions(
      fixturePredictionRepository: predictions,
      auditRecorder: auditRecorderOver(auditLog),
    );
  });

  test('refuses a non-admin caller before any read or audit', () async {
    predictions.seedPrediction(
      _prediction(_predictionId, _otherParticipantId),
      _submittedAt,
    );
    final result = await useCase(
      principal: principal(userId: adminUuid, role: PlatformRole.user),
      fixtureId: _fixtureId,
    );
    final error = (result as Err<List<FixturePredictionView>>).error;
    expect(error.kind, ErrorKind.authorization);
    expect(error.code, 'auth.insufficient_role');
    expect(auditLog.rows, isEmpty);
  });

  test('rejects a malformed fixture id before any read or audit', () async {
    final result = await useCase(
      principal: principal(userId: adminUuid),
      fixtureId: 'not-a-uuid',
    );
    final error = (result as Err<List<FixturePredictionView>>).error;
    expect(error.kind, ErrorKind.validation);
    expect(error.code, 'competition.fixture_ref_malformed');
    expect(auditLog.rows, isEmpty);
  });

  test("returns every participant's raw prediction for the fixture, "
      'auditing the read', () async {
    predictions.seedPrediction(
      _prediction(_predictionId, _otherParticipantId),
      _submittedAt,
    );

    final result = await useCase(
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
      final result = await useCase(
        principal: principal(userId: adminUuid),
        fixtureId: _fixtureId,
      );

      final list = (result as Ok<List<FixturePredictionView>>).value;
      expect(list, isEmpty);
      expect(auditLog.rows, hasLength(1));
    },
  );
}
