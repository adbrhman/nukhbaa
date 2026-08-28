import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fakes.dart';
import 'fake_fixture_prediction_repository.dart';

const _userId = '11111111-1111-1111-1111-111111111111';
const _otherUserId = '22222222-2222-2222-2222-222222222222';
const _participantId = '55555555-5555-5555-5555-555555555555';
const _otherFixtureParticipantId = '77777777-7777-7777-7777-777777777777';
const _foreignParticipantId = '88888888-8888-8888-8888-888888888888';
const _predictionId = '66666666-6666-6666-6666-666666666666';
const _otherPredictionId = '99999999-9999-9999-9999-999999999999';
const _foreignPredictionId = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
const _fixtureA = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _fixtureB = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

final _early = DateTime.utc(2026, 8, 1, 12);
final _late = DateTime.utc(2026, 8, 1, 13);

FixturePrediction _prediction(
  String id,
  String fixture,
  String participantId,
) => FixturePrediction.fromStored(
  id: PredictionId(id),
  fixture: FixtureRef(fixture),
  participantId: ParticipantId(participantId),
  homeGoals: 2,
  awayGoals: 1,
);

void main() {
  late FakeFixturePredictionRepository fixturePredictions;
  late ListMyFixturePredictions useCase;

  setUp(() {
    fixturePredictions = FakeFixturePredictionRepository();
    useCase = ListMyFixturePredictions(
      fixturePredictionRepository: fixturePredictions,
    );
  });

  test(
    'lists every fixture prediction owned by the caller across fixtures, '
    'newest first',
    () async {
      fixturePredictions
        ..seedParticipantOwner(
          const ParticipantId(_participantId),
          const UserId(_userId),
        )
        ..seedParticipantOwner(
          const ParticipantId(_otherFixtureParticipantId),
          const UserId(_userId),
        )
        // Seed out of time order; expect newest (latest submittedAt) first.
        ..seedPrediction(
          _prediction(_predictionId, _fixtureA, _participantId),
          _early,
        )
        ..seedPrediction(
          _prediction(
            _otherPredictionId,
            _fixtureB,
            _otherFixtureParticipantId,
          ),
          _late,
        );

      final result = await useCase(principal: userPrincipal(_userId));

      final list = (result as Ok<List<FixturePredictionView>>).value;
      expect(list, hasLength(2));
      expect(list.first.prediction.id, const PredictionId(_otherPredictionId));
      expect(list.first.submittedAt, _late);
      expect(list.last.prediction.id, const PredictionId(_predictionId));
      expect(list.last.submittedAt, _early);
    },
  );

  test(
    "excludes another user's fixture predictions even when present",
    () async {
      fixturePredictions
        ..seedParticipantOwner(
          const ParticipantId(_participantId),
          const UserId(_userId),
        )
        ..seedParticipantOwner(
          const ParticipantId(_foreignParticipantId),
          const UserId(_otherUserId),
        )
        ..seedPrediction(
          _prediction(_predictionId, _fixtureA, _participantId),
          _early,
        )
        ..seedPrediction(
          _prediction(_foreignPredictionId, _fixtureB, _foreignParticipantId),
          _late,
        );

      final result = await useCase(principal: userPrincipal(_userId));

      final list = (result as Ok<List<FixturePredictionView>>).value;
      expect(list, hasLength(1));
      expect(list.single.prediction.id, const PredictionId(_predictionId));
    },
  );

  test('a caller with no fixture predictions yet gets an empty list', () async {
    final result = await useCase(principal: userPrincipal(_userId));

    expect((result as Ok<List<FixturePredictionView>>).value, isEmpty);
  });

  test('propagates a repository failure unchanged', () async {
    fixturePredictions.failNextWith(
      const AppError.transient('prediction.transient_failure', 'db down'),
    );

    final result = await useCase(principal: userPrincipal(_userId));

    final error = (result as Err<List<FixturePredictionView>>).error;
    expect(error.kind, ErrorKind.transient);
    expect(error.code, 'prediction.transient_failure');
  });
}
