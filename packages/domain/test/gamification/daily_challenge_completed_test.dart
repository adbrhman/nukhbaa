import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _eventId = '99999999-8888-7777-6666-555555555555';
const _otherEventId = '11111111-8888-7777-6666-555555555555';
const _userId = '11111111-2222-3333-4444-555555555555';

DateTime _day() => DateTime.utc(2026, 9, 19);

void main() {
  group('GamificationEvent.dailyChallengeCompleted', () {
    test('keys on the user and the day, not on the prediction', () {
      final result = GamificationEvent.dailyChallengeCompleted(
        id: _eventId,
        userId: const UserId(_userId),
        day: _day(),
        fixtureCount: 5,
        occurredAt: DateTime.utc(2026, 9, 19, 17, 30),
      );

      expect(result.isOk, isTrue);
      final event = (result as Ok<GamificationEvent>).value;
      expect(event.dedupeKey, 'daily_challenge_completed:$_userId:2026-09-19');
      expect(event.type, GamificationEventType.dailyChallengeCompleted);
    });

    test('two completions of the same day share one dedupe key', () {
      // What makes "a completed day is never un-completed" mechanical: a
      // re-evaluation after a late fixture produces the same key, and the
      // unique index turns the second write into a no-op.
      final first = GamificationEvent.dailyChallengeCompleted(
        id: _eventId,
        userId: const UserId(_userId),
        day: _day(),
        fixtureCount: 5,
        occurredAt: DateTime.utc(2026, 9, 19, 17, 30),
      );
      final second = GamificationEvent.dailyChallengeCompleted(
        id: _otherEventId,
        userId: const UserId(_userId),
        day: _day(),
        fixtureCount: 7,
        occurredAt: DateTime.utc(2026, 9, 19, 21),
      );

      expect(
        (first as Ok<GamificationEvent>).value.dedupeKey,
        (second as Ok<GamificationEvent>).value.dedupeKey,
      );
    });

    test('carries the day and the fixture count, and no reference', () {
      final result = GamificationEvent.dailyChallengeCompleted(
        id: _eventId,
        userId: const UserId(_userId),
        day: _day(),
        fixtureCount: 5,
        occurredAt: DateTime.utc(2026, 9, 19, 17, 30),
      );

      final event = (result as Ok<GamificationEvent>).value;
      expect(event.payload['day'], '2026-09-19');
      expect(event.payload['fixtures'], 5);
      expect(event.refType, isNull);
      expect(event.refId, isNull);
    });

    test('refuses a day that held no fixtures', () {
      final result = GamificationEvent.dailyChallengeCompleted(
        id: _eventId,
        userId: const UserId(_userId),
        day: _day(),
        fixtureCount: 0,
        occurredAt: DateTime.utc(2026, 9, 19, 17, 30),
      );

      expect(result.isErr, isTrue);
    });
  });
}
