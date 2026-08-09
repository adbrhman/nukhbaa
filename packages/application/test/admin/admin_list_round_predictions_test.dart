import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fake_competition_repository.dart';
import '../competition/fakes.dart';
import '../prediction/fake_prediction_repository.dart';
import 'fakes.dart';

const _roundId = '44444444-4444-4444-4444-444444444444';
const _otherParticipantId = '88888888-8888-8888-8888-888888888888';
const _predictionId = '66666666-6666-6666-6666-666666666666';
const _fixtureA = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

final _submittedAt = DateTime.utc(2026, 8, 1, 12);

Round _round({RoundStatus status = RoundStatus.open}) {
  final open =
      (Round.open(
                id: const RoundId(_roundId),
                seasonId: const SeasonId(seasonUuid),
                sequence: 1,
                predictionDeadline: DateTime.utc(2026, 8, 2),
                ruleset: testSnapshot(),
              )
              as Ok<Round>)
          .value;
  if (status == RoundStatus.open) return open;
  final locked = (open.transitionTo(RoundStatus.locked) as Ok<Round>).value;
  if (status == RoundStatus.locked) return locked;
  return (locked.transitionTo(RoundStatus.scored) as Ok<Round>).value;
}

Prediction _prediction(String id, String participantId) =>
    (Prediction.submit(
              id: PredictionId(id),
              roundId: const RoundId(_roundId),
              participantId: ParticipantId(participantId),
              roundStatus: RoundStatus.open,
              scores: [
                (FixtureScorePrediction.create(
                          fixture: const FixtureRef(_fixtureA),
                          homeGoals: 2,
                          awayGoals: 1,
                        )
                        as Ok<FixtureScorePrediction>)
                    .value,
              ],
            )
            as Ok<Prediction>)
        .value;

void main() {
  late FakePredictionRepository predictions;
  late FakeCompetitionRepository competition;
  late InMemoryAuditLogRepository auditLog;
  late AdminListRoundPredictions useCase;

  setUp(() {
    predictions = FakePredictionRepository();
    competition = FakeCompetitionRepository();
    auditLog = InMemoryAuditLogRepository();
    useCase = AdminListRoundPredictions(
      competitionRepository: competition,
      predictionRepository: predictions,
      auditRecorder: auditRecorderOver(auditLog),
    );
  });

  test(
    'refuses a non-admin caller before any read or audit',
    () async {
      competition.seedRound(_round(status: RoundStatus.scored));
      final result = await useCase(
        principal: principal(userId: adminUuid, role: PlatformRole.user),
        roundId: _roundId,
      );
      final error = (result as Err<List<PredictionView>>).error;
      expect(error.kind, ErrorKind.authorization);
      expect(error.code, 'auth.insufficient_role');
      expect(auditLog.rows, isEmpty);
    },
  );

  test('rejects a round that is not yet scored', () async {
    competition.seedRound(_round(status: RoundStatus.locked));
    final result = await useCase(
      principal: principal(userId: adminUuid),
      roundId: _roundId,
    );
    final error = (result as Err<List<PredictionView>>).error;
    expect(error.kind, ErrorKind.invariant);
    expect(error.code, 'admin.round_not_scored');
    expect(auditLog.rows, isEmpty);
  });

  test(
    'returns every participant\'s raw prediction for a scored round, '
    'auditing the read',
    () async {
      competition.seedRound(_round(status: RoundStatus.scored));
      predictions.seedPrediction(
        _prediction(_predictionId, _otherParticipantId),
        _submittedAt,
      );

      final result = await useCase(
        principal: principal(userId: adminUuid),
        roundId: _roundId,
      );

      final list = (result as Ok<List<PredictionView>>).value;
      expect(list, hasLength(1));
      expect(list.single.prediction.scores.single.homeGoals, 2);
      expect(list.single.prediction.scores.single.awayGoals, 1);

      expect(auditLog.rows, hasLength(1));
      expect(auditLog.rows.single.action, AuditAction.roundPredictionsViewed);
      expect(auditLog.rows.single.targetRef, _roundId);
    },
  );

  test('a missing round is an invariant precondition failure', () async {
    final result = await useCase(
      principal: principal(userId: adminUuid),
      roundId: _roundId,
    );
    final error = (result as Err<List<PredictionView>>).error;
    expect(error.kind, ErrorKind.invariant);
    expect(error.code, 'competition.round_not_found');
  });
}
