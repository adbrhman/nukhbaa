import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  const fixtureId = '11111111-1111-1111-1111-111111111111';
  const predictionId = '22222222-2222-2222-2222-222222222222';
  const participantId = '33333333-3333-3333-3333-333333333333';

  FixtureLock openLock() =>
      (FixtureLock.at(
                kickoffAt: DateTime.utc(2026, 8, 2),
                nowUtc: DateTime.utc(2026, 8, 1),
              )
              as Ok<FixtureLock>)
          .value;

  FixtureLock lockedLock() =>
      (FixtureLock.at(
                kickoffAt: DateTime.utc(2026, 8, 1),
                nowUtc: DateTime.utc(2026, 8, 2),
              )
              as Ok<FixtureLock>)
          .value;

  group('FixturePrediction.submit', () {
    test('creates a prediction when the fixture is still open', () {
      final result = FixturePrediction.submit(
        id: const PredictionId(predictionId),
        fixture: const FixtureRef(fixtureId),
        participantId: const ParticipantId(participantId),
        lock: openLock(),
        homeGoals: 2,
        awayGoals: 1,
        isDouble: true,
      );

      expect(result, isA<Ok<FixturePrediction>>());
      final prediction = (result as Ok<FixturePrediction>).value;
      expect(prediction.homeGoals, 2);
      expect(prediction.awayGoals, 1);
      expect(prediction.isDouble, isTrue);
      expect(prediction.fixture, const FixtureRef(fixtureId));
      expect(prediction.participantId, const ParticipantId(participantId));
    });

    test('rejects a submission once the fixture has kicked off', () {
      final result = FixturePrediction.submit(
        id: const PredictionId(predictionId),
        fixture: const FixtureRef(fixtureId),
        participantId: const ParticipantId(participantId),
        lock: lockedLock(),
        homeGoals: 1,
        awayGoals: 0,
      );

      expect(result, isA<Err<FixturePrediction>>());
      expect(
        (result as Err<FixturePrediction>).error.code,
        'prediction.fixture_locked',
      );
    });

    test('rejects negative goals', () {
      final result = FixturePrediction.submit(
        id: const PredictionId(predictionId),
        fixture: const FixtureRef(fixtureId),
        participantId: const ParticipantId(participantId),
        lock: openLock(),
        homeGoals: -1,
        awayGoals: 0,
      );

      expect(result, isA<Err<FixturePrediction>>());
      expect(
        (result as Err<FixturePrediction>).error.code,
        'prediction.score_negative',
      );
    });

    test('rejects goals above the max', () {
      final result = FixturePrediction.submit(
        id: const PredictionId(predictionId),
        fixture: const FixtureRef(fixtureId),
        participantId: const ParticipantId(participantId),
        lock: openLock(),
        homeGoals: 0,
        awayGoals: 100,
      );

      expect(result, isA<Err<FixturePrediction>>());
      expect(
        (result as Err<FixturePrediction>).error.code,
        'prediction.score_out_of_range',
      );
    });

    test('defaults isDouble to false', () {
      final result = FixturePrediction.submit(
        id: const PredictionId(predictionId),
        fixture: const FixtureRef(fixtureId),
        participantId: const ParticipantId(participantId),
        lock: openLock(),
        homeGoals: 0,
        awayGoals: 0,
      );

      expect((result as Ok<FixturePrediction>).value.isDouble, isFalse);
    });
  });

  group('FixturePrediction.amend', () {
    late FixturePrediction original;

    setUp(() {
      original =
          (FixturePrediction.submit(
                    id: const PredictionId(predictionId),
                    fixture: const FixtureRef(fixtureId),
                    participantId: const ParticipantId(participantId),
                    lock: openLock(),
                    homeGoals: 1,
                    awayGoals: 1,
                  )
                  as Ok<FixturePrediction>)
              .value;
    });

    test('preserves identity while updating the scoreline', () {
      final result = original.amend(
        lock: openLock(),
        homeGoals: 3,
        awayGoals: 0,
        isDouble: true,
      );

      expect(result, isA<Ok<FixturePrediction>>());
      final amended = (result as Ok<FixturePrediction>).value;
      expect(amended.id, original.id);
      expect(amended.fixture, original.fixture);
      expect(amended.participantId, original.participantId);
      expect(amended.homeGoals, 3);
      expect(amended.awayGoals, 0);
      expect(amended.isDouble, isTrue);
    });

    test('rejects amendment once the fixture has kicked off', () {
      final result = original.amend(
        lock: lockedLock(),
        homeGoals: 0,
        awayGoals: 0,
        isDouble: false,
      );

      expect(result, isA<Err<FixturePrediction>>());
      expect(
        (result as Err<FixturePrediction>).error.code,
        'prediction.fixture_locked',
      );
    });

    test('rejects an invalid scoreline on amendment', () {
      final result = original.amend(
        lock: openLock(),
        homeGoals: -5,
        awayGoals: 0,
        isDouble: false,
      );

      expect(result, isA<Err<FixturePrediction>>());
    });
  });

  group('FixturePrediction value semantics', () {
    test('equal when every field matches', () {
      final a =
          (FixturePrediction.submit(
                    id: const PredictionId(predictionId),
                    fixture: const FixtureRef(fixtureId),
                    participantId: const ParticipantId(participantId),
                    lock: openLock(),
                    homeGoals: 1,
                    awayGoals: 2,
                  )
                  as Ok<FixturePrediction>)
              .value;
      final b =
          (FixturePrediction.submit(
                    id: const PredictionId(predictionId),
                    fixture: const FixtureRef(fixtureId),
                    participantId: const ParticipantId(participantId),
                    lock: openLock(),
                    homeGoals: 1,
                    awayGoals: 2,
                  )
                  as Ok<FixturePrediction>)
              .value;

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
