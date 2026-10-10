import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

final _october = DateTime.utc(2026, 10);
const _league = H2hLeagueId('33333333-3333-4333-8333-333333333333');
final _me = player.userId;

H2hRound _round(int number, int day, {required bool locked}) => H2hRound(
  id: H2hRoundId('44444444-4444-4444-8444-00000000000$number'),
  monthStart: _october,
  number: number,
  day: DateTime.utc(2026, 10, day),
  fixtureCount: 6,
  approvedBy: null,
  lockedAt: locked ? DateTime.utc(2026, 10, day, 12) : null,
);

/// The October pilot, four seats. Round 1 settled, round 2 void, round 3
/// live, rounds 4 and 5 not started.
Future<MyH2hMonth> _read(DateTime now, {bool seated = true}) async {
  final leagues = FakeH2hLeagueStore();
  if (seated) {
    leagues.seat(
      _me,
      H2hSeat(
        leagueId: _league,
        monthStart: _october,
        division: H2hDivision.first,
        groupIndex: 0,
        slot: 0,
        capacity: 4,
        divisionGroups: 1,
        isPilot: true,
        joinedAt: _october,
      ),
    );
  }
  final rounds = FakeH2hRoundStore()
    // Listed out of order on purpose: the phases must not depend on it.
    ..addRound(_round(5, 13, locked: false))
    ..addRound(_round(1, 4, locked: true))
    ..addRound(_round(2, 6, locked: true))
    ..addRound(_round(3, 10, locked: true))
    ..addRound(_round(4, 11, locked: false))
    ..dayOf(DateTime.utc(2026, 10, 10), 8, DateTime.utc(2026, 10, 10, 12))
    ..dayOf(DateTime.utc(2026, 10, 11), 6, DateTime.utc(2026, 10, 11, 15))
    ..dayOf(DateTime.utc(2026, 10, 12), 9, DateTime.utc(2026, 10, 12, 16));
  final sheets = FakeH2hSheetReader()
    ..sheets[_league] = H2hGroupSheet(
      members: [
        for (final (i, user) in [_me, userNo(2), userNo(3), userNo(4)].indexed)
          H2hMember(
            userId: user,
            slot: i,
            joinedAt: DateTime.utc(2026, 10, 1, 0, i),
          ),
      ],
      // The caller played round 3 (0 points so far); u3, their opponent,
      // has no pick yet.
      scores: [
        H2hRoundScore(
          userId: _me,
          round: 3,
          points: 0,
          exactCount: 0,
          predictedCount: 2,
        ),
      ],
      settledRounds: const <int>{1},
      voidRounds: const <int>{2},
    );
  final clock = AtClock(now);
  final result = await GetMyH2hMonth(
    league: GetMyH2hLeague(
      leagues: leagues,
      rounds: rounds,
      sheets: sheets,
      profiles: NamingProfiles(),
      clock: clock,
    ),
    rounds: rounds,
    clock: clock,
  ).call(principal: player);
  return (result as Ok<MyH2hMonth>).value;
}

MyH2hRound _view(
  H2hRoundStatus status, {
  bool present = true,
  bool opponentPresent = true,
  int points = 0,
  double opponentPoints = 0,
  H2hMatchResult result = H2hMatchResult.draw,
}) => MyH2hRound(
  round: _round(1, 4, locked: status != H2hRoundStatus.upcoming),
  status: status,
  opponentId: userNo(2),
  match: status == H2hRoundStatus.upcoming
      ? null
      : H2hMatch(
          round: 1,
          day: DateTime.utc(2026, 10, 4),
          opponentId: userNo(2),
          points: points,
          opponentPoints: opponentPoints,
          present: present,
          opponentPresent: opponentPresent,
          result: result,
        ),
);

void main() {
  group('GetMyH2hMonth', () {
    test('each round takes its phase from the server state', () async {
      final month = await _read(DateTime.utc(2026, 10, 10, 9));

      expect(month.league.state, H2hLeagueState.open);
      expect(month.phases, <int, H2hRoundPhase>{
        1: H2hRoundPhase.settled,
        2: H2hRoundPhase.voided,
        3: H2hRoundPhase.live,
        4: H2hRoundPhase.open,
        5: H2hRoundPhase.upcoming,
      });
    });

    test('a live round shows points only, not the policy result', () async {
      final month = await _read(DateTime.utc(2026, 10, 10, 9));

      final live = month.league.rounds.singleWhere((r) => r.round.number == 3);
      expect(live.opponentId, userNo(3));
      // The raw policy result would tell the caller u3 has no pick yet.
      expect(live.match!.result, H2hMatchResult.win);
      expect(month.results[3], H2hMatchResult.draw);
      expect(month.results.containsKey(4), isFalse);
      expect(month.results.containsKey(2), isFalse);
    });

    test('first kickoffs of the round days only', () async {
      final month = await _read(DateTime.utc(2026, 10, 10, 9));

      expect(month.firstKickoffs, <int, DateTime>{
        3: DateTime.utc(2026, 10, 10, 12),
        4: DateTime.utc(2026, 10, 11, 15),
      });
    });

    test('days left after today, by the Riyadh day', () async {
      expect((await _read(DateTime.utc(2026, 10, 10, 9))).daysLeft, 21);
      // 00:00 Riyadh on the 11th.
      expect((await _read(DateTime.utc(2026, 10, 10, 21))).daysLeft, 20);
      // 23:59 Riyadh on the last day.
      expect((await _read(DateTime.utc(2026, 10, 31, 20, 59))).daysLeft, 0);
    });

    test('without a seat: no phases, still the days left', () async {
      final month = await _read(DateTime.utc(2026, 10, 10, 9), seated: false);

      expect(month.league.state, H2hLeagueState.notStarted);
      expect(month.phases, isEmpty);
      expect(month.firstKickoffs, isEmpty);
      expect(month.daysLeft, 21);
    });

    test('daysLeftIn', () {
      int left(int month, int day) => GetMyH2hMonth.daysLeftIn(
        monthStart: DateTime.utc(2026, month),
        today: DateTime.utc(2026, month, day),
      );
      expect(left(10, 1), 30);
      expect(left(10, 30), 1);
      expect(left(10, 31), 0);
      expect(left(11, 30), 0);
      expect(left(2, 1), 27);
    });
  });

  group('h2hRoundPhasesOf', () {
    test('only the lowest round not started is open', () {
      expect(
        h2hRoundPhasesOf([
          MyH2hRound(
            round: _round(7, 20, locked: false),
            status: H2hRoundStatus.upcoming,
            opponentId: null,
            match: null,
          ),
          MyH2hRound(
            round: _round(6, 18, locked: false),
            status: H2hRoundStatus.upcoming,
            opponentId: null,
            match: null,
          ),
        ]),
        <int, H2hRoundPhase>{6: H2hRoundPhase.open, 7: H2hRoundPhase.upcoming},
      );
    });
  });

  group('h2hShownResultOf', () {
    test('a settled round shows the policy result', () {
      expect(
        h2hShownResultOf(
          _view(
            H2hRoundStatus.settled,
            opponentPresent: false,
            result: H2hMatchResult.win,
          ),
        ),
        H2hMatchResult.win,
      );
    });

    test('a live round weighs points only, not whether they predicted', () {
      // The policy would call this a win (the opponent has no pick yet):
      // shown live, that would tell the caller so.
      expect(
        h2hShownResultOf(
          _view(
            H2hRoundStatus.live,
            opponentPresent: false,
            result: H2hMatchResult.win,
          ),
        ),
        H2hMatchResult.draw,
      );
      expect(
        h2hShownResultOf(
          _view(H2hRoundStatus.live, points: 4, opponentPoints: 2),
        ),
        H2hMatchResult.win,
      );
      expect(
        h2hShownResultOf(
          _view(H2hRoundStatus.live, points: 2, opponentPoints: 2.5),
        ),
        H2hMatchResult.loss,
      );
    });

    test('a live round the caller has not played is a loss', () {
      expect(
        h2hShownResultOf(_view(H2hRoundStatus.live, present: false)),
        H2hMatchResult.loss,
      );
    });

    test('nothing before the round starts', () {
      expect(h2hShownResultOf(_view(H2hRoundStatus.upcoming)), isNull);
    });
  });
}
