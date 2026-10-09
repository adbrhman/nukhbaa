import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _eventId = '99999999-8888-7777-6666-555555555555';
const _otherEventId = '11111111-8888-7777-6666-555555555555';
const _userId = '11111111-2222-3333-4444-555555555555';
const _leagueId = '33333333-3333-3333-3333-333333333333';

/// That month's own end: 2026-12-01 00:00 Riyadh, as UTC.
DateTime _monthEnd() => DateTime.utc(2026, 11, 30, 21);

Result<GamificationEvent> _finished({
  String id = _eventId,
  DateTime? monthStart,
  int rank = 2,
  H2hDivision? nextDivision = H2hDivision.first,
  H2hLeagueOutcome outcome = H2hLeagueOutcome.promoted,
}) => GamificationEvent.h2hLeagueFinished(
  id: id,
  userId: const UserId(_userId),
  leagueId: const H2hLeagueId(_leagueId),
  monthStart: monthStart ?? DateTime.utc(2026, 11),
  division: H2hDivision.second,
  rank: rank,
  leaguePoints: 37,
  points: 69,
  nextDivision: nextDivision,
  outcome: outcome,
  occurredAt: _monthEnd(),
);

void main() {
  group('GamificationEvent.h2hLeagueFinished', () {
    test('keys on the user and the month', () {
      final result = _finished();

      expect(result.isOk, isTrue);
      final event = (result as Ok<GamificationEvent>).value;
      expect(event.dedupeKey, 'h2h_league_finished:$_userId:2026-11-01');
      expect(event.type, GamificationEventType.h2hLeagueFinished);
      expect(event.type.wireName, 'h2h_league_finished');
    });

    test('any day of the month keys on its first day', () {
      final first = _finished();
      final later = _finished(
        id: _otherEventId,
        monthStart: DateTime.utc(2026, 11, 17),
      );

      expect(
        (later as Ok<GamificationEvent>).value.dedupeKey,
        (first as Ok<GamificationEvent>).value.dedupeKey,
      );
    });

    test('carries the standing and the next division, and points at the '
        'group', () {
      final event = (_finished() as Ok<GamificationEvent>).value;

      expect(event.payload, {
        'month': '2026-11-01',
        'division': 2,
        'rank': 2,
        'league_points': 37,
        'points': 69,
        'next_division': 1,
        'outcome': 'promoted',
      });
      expect(event.refType, 'h2h_league');
      expect(event.refId, _leagueId);
      expect(event.occurredAt, _monthEnd());
    });

    test('a member who is not drawn carries no next division', () {
      final event =
          (_finished(nextDivision: null, outcome: H2hLeagueOutcome.out)
                  as Ok<GamificationEvent>)
              .value;

      expect(event.payload['next_division'], isNull);
      expect(event.payload['outcome'], 'out');
    });

    test('a next division and the outcome must agree', () {
      final noDivision = _finished(nextDivision: null);
      final outWithDivision = _finished(outcome: H2hLeagueOutcome.out);

      for (final result in [noDivision, outWithDivision]) {
        expect(result.isOk, isFalse);
        expect(
          (result as Err<GamificationEvent>).error.code,
          'gamification.h2h_league_outcome_mismatch',
        );
      }
    });

    test('a rank below 1 is refused', () {
      final result = _finished(rank: 0);

      expect(result.isOk, isFalse);
      expect(
        (result as Err<GamificationEvent>).error.code,
        'gamification.h2h_league_rank_invalid',
      );
    });

    test('a malformed event id is refused', () {
      expect(_finished(id: 'not-a-uuid').isOk, isFalse);
    });
  });
}
