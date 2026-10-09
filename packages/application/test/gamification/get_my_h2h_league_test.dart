import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

final _november = DateTime.utc(2026, 11);
const _league = H2hLeagueId('33333333-3333-4333-8333-333333333333');
final _me = player.userId;

H2hRound _round(int number, int day, {required bool locked}) => H2hRound(
  id: H2hRoundId('44444444-4444-4444-8444-00000000000$number'),
  monthStart: _november,
  number: number,
  day: DateTime.utc(2026, 11, day),
  fixtureCount: 8,
  approvedBy: null,
  lockedAt: locked ? DateTime.utc(2026, 11, day, 12) : null,
);

H2hRoundScore _score(UserId user, int round, int points) => H2hRoundScore(
  userId: user,
  round: round,
  points: points,
  exactCount: 0,
  predictedCount: 3,
);

GetMyH2hLeague _useCase({
  required FakeH2hLeagueStore leagues,
  FakeH2hRoundStore? rounds,
  FakeH2hSheetReader? sheets,
  required DateTime now,
}) => GetMyH2hLeague(
  leagues: leagues,
  rounds: rounds ?? FakeH2hRoundStore(),
  sheets: sheets ?? FakeH2hSheetReader(),
  profiles: NamingProfiles(),
  clock: AtClock(now),
);

void main() {
  group('GetMyH2hLeague without a seat', () {
    test('before the league opens it has not started', () async {
      final result = await _useCase(
        leagues: FakeH2hLeagueStore(),
        now: DateTime.utc(2026, 10, 20),
      ).call(principal: player);

      expect(
        (result as Ok<MyH2hLeague>).value.state,
        H2hLeagueState.notStarted,
      );
    });

    test('on the month first night the draw is pending', () async {
      final result = await _useCase(
        leagues: FakeH2hLeagueStore(),
        now: DateTime.utc(2026, 10, 31, 22), // 01:00 Riyadh, November
      ).call(principal: player);

      final reading = (result as Ok<MyH2hLeague>).value;
      expect(reading.state, H2hLeagueState.drawPending);
      expect(reading.monthStart, _november);
    });

    test('a drawn month without the caller says so', () async {
      final leagues = FakeH2hLeagueStore()
        ..months[_november] = H2hMonthInfo(
          monthStart: _november,
          isPilot: false,
          seatedCount: 80,
        );

      final result = await _useCase(
        leagues: leagues,
        now: DateTime.utc(2026, 11, 5),
      ).call(principal: player);

      expect((result as Ok<MyH2hLeague>).value.state, H2hLeagueState.notInDraw);
    });
  });

  group('GetMyH2hLeague with a seat', () {
    // Four seats. Round 1: 0-3, 1-2. Round 2: 0-1, 2-3. Round 3: 0-2, 1-3.
    final u2 = userNo(2);
    final u3 = userNo(3);
    final u4 = userNo(4);

    Future<MyH2hLeague> read() async {
      final leagues = FakeH2hLeagueStore()
        ..seat(
          _me,
          H2hSeat(
            leagueId: _league,
            monthStart: _november,
            division: H2hDivision.second,
            groupIndex: 0,
            slot: 0,
            capacity: 4,
            divisionGroups: 1,
            isPilot: false,
            joinedAt: _november,
          ),
        );
      final rounds = FakeH2hRoundStore()
        ..addRound(_round(1, 3, locked: true))
        ..addRound(_round(2, 5, locked: true))
        ..addRound(_round(3, 7, locked: false));
      final sheets = FakeH2hSheetReader();
      sheets.sheets[_league] = H2hGroupSheet(
        members: [
          for (final (i, user) in [_me, u2, u3, u4].indexed)
            H2hMember(
              userId: user,
              slot: i,
              joinedAt: DateTime.utc(2026, 11, 1, 0, i),
            ),
        ],
        scores: [
          _score(_me, 1, 5),
          _score(u4, 1, 2),
          _score(u2, 1, 3),
          _score(u3, 1, 3),
          _score(_me, 2, 1),
          _score(u2, 2, 4),
        ],
        settledRounds: const <int>{1},
        voidRounds: const <int>{},
      );
      final result = await _useCase(
        leagues: leagues,
        rounds: rounds,
        sheets: sheets,
        now: DateTime.utc(2026, 11, 5, 15),
      ).call(principal: player);
      return (result as Ok<MyH2hLeague>).value;
    }

    test('the table counts settled rounds only', () async {
      final reading = await read();

      expect(reading.state, H2hLeagueState.open);
      expect(reading.placings.map((p) => p.standing.userId).toList(), [
        _me,
        u2,
        u3,
        u4,
      ]);
      expect(reading.placings.first.standing.leaguePoints, 3);
      expect(reading.placings.first.standing.played, 1);
      expect(reading.myRank, 1);
    });

    test(
      'each round shows where it stands and whom the caller meets',
      () async {
        final reading = await read();

        expect(reading.rounds.map((r) => r.status).toList(), [
          H2hRoundStatus.settled,
          H2hRoundStatus.live,
          H2hRoundStatus.upcoming,
        ]);
        expect(reading.rounds.map((r) => r.opponentId).toList(), [u4, u2, u3]);
        expect(reading.rounds[0].match!.result, H2hMatchResult.win);
        expect(reading.rounds[1].match!.points, 1);
        expect(reading.rounds[1].match!.opponentPoints, 4);
        expect(reading.rounds[1].match!.result, H2hMatchResult.loss);
        expect(reading.rounds[2].match, isNull);
      },
    );

    test(
      'carries names and the zones of a four-member second division',
      () async {
        final reading = await read();

        expect(reading.profiles[u2]!.displayName, 'name ${u2.value}');
        expect(reading.promotionZone, 2);
        expect(reading.relegationZone, 2);
      },
    );
  });
}
