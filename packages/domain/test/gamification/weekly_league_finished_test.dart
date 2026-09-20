import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _eventId = '99999999-8888-7777-6666-555555555555';
const _otherEventId = '11111111-8888-7777-6666-555555555555';
const _userId = '11111111-2222-3333-4444-555555555555';
const _leagueId = '22222222-2222-2222-2222-222222222222';

/// The Monday that opens the judged week.
DateTime _week() => DateTime.utc(2026, 9, 7);

/// That week's own end: Monday 2026-09-14 00:00 Riyadh, as UTC.
DateTime _weekEnd() => DateTime.utc(2026, 9, 13, 21);

Result<GamificationEvent> _finished({
  String id = _eventId,
  DateTime? weekStart,
  WeeklyLeagueTier tier = WeeklyLeagueTier.silver,
  int rank = 3,
  int points = 12,
  WeeklyLeagueOutcome outcome = WeeklyLeagueOutcome.promoted,
}) => GamificationEvent.weeklyLeagueFinished(
  id: id,
  userId: const UserId(_userId),
  leagueId: const WeeklyLeagueId(_leagueId),
  weekStart: weekStart ?? _week(),
  tier: tier,
  rank: rank,
  points: points,
  outcome: outcome,
  occurredAt: _weekEnd(),
);

void main() {
  group('GamificationEvent.weeklyLeagueFinished', () {
    test('keys on the user and the week', () {
      final result = _finished();

      expect(result.isOk, isTrue);
      final event = (result as Ok<GamificationEvent>).value;
      expect(event.dedupeKey, 'weekly_league_finished:$_userId:2026-09-07');
      expect(event.type, GamificationEventType.weeklyLeagueFinished);
    });

    test('replaying a week yields the same dedupe key', () {
      // What makes closing a week replayable: a second run builds the same
      // key, and the unique index turns the second write into a no-op.
      final first = _finished();
      final second = _finished(
        id: _otherEventId,
        rank: 1,
        points: 99,
        outcome: WeeklyLeagueOutcome.held,
      );

      expect(
        (first as Ok<GamificationEvent>).value.dedupeKey,
        (second as Ok<GamificationEvent>).value.dedupeKey,
      );
    });

    test('a date inside the week keys on that week Monday', () {
      final monday = _finished();
      final thursday = _finished(weekStart: DateTime.utc(2026, 9, 10));

      expect(
        (thursday as Ok<GamificationEvent>).value.dedupeKey,
        (monday as Ok<GamificationEvent>).value.dedupeKey,
      );
    });

    test('two different weeks never share a dedupe key', () {
      final first = _finished();
      final next = _finished(weekStart: DateTime.utc(2026, 9, 14));

      expect(
        (first as Ok<GamificationEvent>).value.dedupeKey,
        isNot((next as Ok<GamificationEvent>).value.dedupeKey),
      );
    });

    test('carries the standing and nothing else in the payload', () {
      final event = (_finished() as Ok<GamificationEvent>).value;

      expect(event.payload, <String, Object?>{
        'tier': 2,
        'rank': 3,
        'points': 12,
        'outcome': 'promoted',
      });
    });

    test('the payload is what lastFinishOf reads back', () {
      // `PostgresWeeklyLeagueRepository.lastFinishOf` reads payload->>'tier'
      // and payload->>'outcome': both must round-trip to the same values.
      for (final tier in WeeklyLeagueTier.values) {
        for (final outcome in WeeklyLeagueOutcome.values) {
          final result = _finished(tier: tier, outcome: outcome);
          final event = (result as Ok<GamificationEvent>).value;

          expect(WeeklyLeagueTier.ofLevel(event.payload['tier']! as int), tier);
          expect(
            WeeklyLeagueOutcome.values.singleWhere(
              (o) => o.wireName == event.payload['outcome'],
            ),
            outcome,
          );
        }
      }
    });

    test('is dated at the end of the week it judges', () {
      final event = (_finished() as Ok<GamificationEvent>).value;

      expect(event.occurredAt, _weekEnd());
      expect(event.occurredAt.isUtc, isTrue);
    });

    test('points at the group it was judged in', () {
      final event = (_finished() as Ok<GamificationEvent>).value;

      expect(event.refType, 'weekly_league');
      expect(event.refId, _leagueId);
    });

    test('is written under the current rule version', () {
      final event = (_finished() as Ok<GamificationEvent>).value;

      expect(event.ruleVersion, GamificationEvent.currentRuleVersion);
    });

    test('refuses a rank below one', () {
      expect(_finished(rank: 0).isErr, isTrue);
      expect(_finished(rank: -1).isErr, isTrue);
    });

    test('refuses a malformed event id', () {
      expect(_finished(id: 'not-a-uuid').isErr, isTrue);
    });
  });
}
