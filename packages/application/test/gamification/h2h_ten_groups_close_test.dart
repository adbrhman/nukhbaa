/// CloseH2hMonth from December 2026 (NK352B, owner 2026-11-27): the even
/// groups (NK353_01) are drawn afresh every month, so a judged month carries
/// nobody: every member is `held` or `out`, with no `next_order` and no move
/// up or down, and the outcomes reader is not asked. November keeps the
/// carry it had.
library;

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

final _december = DateTime.utc(2026, 12);
final _november = DateTime.utc(2026, 11);

H2hLeagueId _group(int n) =>
    H2hLeagueId('11111111-1111-4111-8111-${n.toString().padLeft(12, '0')}');

H2hRoundId _rid(DateTime month, int n) => H2hRoundId(
  '22222222-2222-4222-8222-${month.month.toString().padLeft(4, '0')}'
  '${n.toString().padLeft(8, '0')}',
);

H2hMember _member(int user, int slot) => H2hMember(
  userId: userNo(user),
  slot: slot,
  joinedAt: DateTime.utc(2026, 12),
  fromRound: 1,
);

/// Counts how often the closing job asks for the right outcomes.
final class _CountingOutcomes implements H2hOutcomeReader {
  int calls = 0;

  @override
  Future<Result<Map<UserId, int>>> outcomesOf(DateTime monthStart) async {
    calls++;
    return Result.ok(<UserId, int>{});
  }
}

/// What a close wrote and how often it read the outcomes.
typedef _Closed = ({
  List<GamificationEvent> events,
  int outcomeReads,
  Map<DateTime, int> closed,
});

/// Closes [month]: three groups of four, each from round 1 and every round
/// settled. December: three groups of the first division (the
/// even-group shape); November: one elite group and two extra ones. User 3 predicted on
/// two days only.
Future<_Closed> _close(DateTime month) async {
  final december = month == _december;
  final leagues = FakeH2hLeagueStore()
    ..months[month] = H2hMonthInfo(
      monthStart: month,
      isPilot: false,
      seatedCount: 12,
    )
    ..drawn[month] = [
      for (final (n, division, index) in [
        (1, H2hDivision.first, 0),
        (
          5,
          december ? H2hDivision.first : H2hDivision.second,
          december ? 1 : 0,
        ),
        (
          6,
          december ? H2hDivision.first : H2hDivision.second,
          december ? 2 : 1,
        ),
      ])
        H2hDrawnGroup(
          leagueId: _group(n),
          group: H2hDrawGroup(
            division: division,
            groupIndex: index,
            seats: const <H2hDrawSeat>[],
          ),
        ),
    ];
  final rounds = FakeH2hRoundStore();
  for (var n = 1; n <= 19; n++) {
    rounds.addRound(
      H2hRound(
        id: _rid(month, n),
        monthStart: month,
        number: n,
        day: DateTime.utc(month.year, month.month, n),
        fixtureCount: 8,
        approvedBy: null,
        lockedAt: DateTime.utc(month.year, month.month, n),
      ),
    );
  }
  final reader = FakeH2hSheetReader();
  for (final (g, first) in [(1, 0), (5, 10), (6, 20)]) {
    reader.sheets[_group(g)] = H2hGroupSheet(
      members: [for (var s = 0; s < 4; s++) _member(first + s, s)],
      scores: [
        for (var n = 1; n <= 19; n++)
          for (var s = 0; s < 4; s++)
            H2hRoundScore(
              userId: userNo(first + s),
              round: n,
              points: 10 - s,
              exactCount: 0,
              predictedCount: 6,
            ),
      ],
      settledRounds: {for (var n = 1; n <= 19; n++) n},
      voidRounds: const <int>{},
    );
    for (var s = 0; s < 4; s++) {
      reader.activeDays[userNo(first + s)] = 20;
    }
  }
  reader.activeDays[userNo(3)] = 2;
  final events = RecordingEvents();
  final outcomes = _CountingOutcomes();
  final result = await CloseH2hMonth(
    leagues: leagues,
    rounds: rounds,
    sheets: reader,
    events: events,
    idGenerator: SequenceIds(),
    outcomes: outcomes,
  )(now: DateTime.utc(month.year, month.month + 1, 1, 12));
  expect((result as Ok<int>).value, 1);
  return (
    events: events.recorded,
    outcomeReads: outcomes.calls,
    closed: leagues.closed,
  );
}

void main() {
  group('CloseH2hMonth from December 2026', () {
    test('every member is held or out, nobody moves, no order is carried, '
        'and the outcomes are not read', () async {
      final done = await _close(_december);
      expect(done.events, hasLength(12));
      expect(done.closed[_december], 12);
      expect(done.outcomeReads, 0);
      final byUser = {for (final e in done.events) e.userId: e.payload};
      for (final payload in byUser.values) {
        expect(payload.containsKey('next_order'), isFalse);
        expect(payload['outcome'], anyOf('held', 'out'));
      }
      // Each group's leader is first in his own group and stays in the draw.
      for (final leader in [0, 10, 20]) {
        expect(byUser[userNo(leader)]!['rank'], 1, reason: '$leader');
        expect(byUser[userNo(leader)]!['outcome'], 'held', reason: '$leader');
        expect(
          byUser[userNo(leader)]!['next_division'],
          H2hDivision.first.level,
          reason: '$leader',
        );
        expect(
          byUser[userNo(leader)]!.containsKey('reason'),
          isFalse,
          reason: '$leader',
        );
      }
      // Two days with a prediction: out of the next draw, with his reason.
      expect(byUser[userNo(3)]!['outcome'], 'out');
      expect(byUser[userNo(3)]!['next_division'], isNull);
      expect(byUser[userNo(3)]!['reason'], 'active_days');
    });

    test('November still carries: the outcomes are read once', () async {
      final done = await _close(_november);
      expect(done.events, hasLength(12));
      expect(done.outcomeReads, 1);
    });
  });
}
