import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _eventId = '99999999-8888-7777-6666-555555555555';
const _otherEventId = '11111111-8888-7777-6666-555555555555';
const _userId = '11111111-2222-3333-4444-555555555555';

Result<GamificationEvent> _unlocked({
  String id = _eventId,
  BadgeCode code = BadgeCode.firstPrediction,
  DateTime? occurredAt,
}) => GamificationEvent.badgeUnlocked(
  id: id,
  userId: const UserId(_userId),
  code: code,
  occurredAt: occurredAt ?? DateTime.utc(2026, 9, 22, 8),
);

void main() {
  group('GamificationEvent.badgeUnlocked', () {
    test('keys on the user and the badge', () {
      final result = _unlocked();

      expect(result.isOk, isTrue);
      final event = (result as Ok<GamificationEvent>).value;
      expect(event.dedupeKey, 'badge_unlocked:$_userId:first_prediction');
      expect(event.type, GamificationEventType.badgeUnlocked);
      expect(event.userId.value, _userId);
      expect(event.ruleVersion, GamificationEvent.currentRuleVersion);
    });

    test('carries the code and points at nothing', () {
      final result = _unlocked(code: BadgeCode.leagueElite);
      final event = (result as Ok<GamificationEvent>).value;

      expect(event.payload, <String, Object?>{'code': 'league_elite'});
      expect(event.refType, isNull);
      expect(event.refId, isNull);
    });

    test('awarding a badge again yields the same dedupe key', () {
      // What makes the evaluator replayable: a second run builds the same
      // key, and the unique index turns the second write into a no-op.
      final first = _unlocked();
      final again = _unlocked(
        id: _otherEventId,
        occurredAt: DateTime.utc(2026, 9, 25, 3),
      );

      expect(
        (first as Ok<GamificationEvent>).value.dedupeKey,
        (again as Ok<GamificationEvent>).value.dedupeKey,
      );
    });

    test('two different badges never share a dedupe key', () {
      final keys = <String>{
        for (final code in BadgeCode.values)
          (_unlocked(code: code) as Ok<GamificationEvent>).value.dedupeKey,
      };

      expect(keys.length, BadgeCode.values.length);
    });

    test('the moment of the award is stored as UTC', () {
      final result = _unlocked(occurredAt: DateTime(2026, 9, 22, 11));
      final event = (result as Ok<GamificationEvent>).value;

      expect(event.occurredAt.isUtc, isTrue);
    });

    test('refuses a malformed event id', () {
      expect(_unlocked(id: 'not-a-uuid').isErr, isTrue);
    });
  });
}
