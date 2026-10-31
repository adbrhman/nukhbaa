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

    // Round 2's last fixture that counts kicks off at 20:00 on the 5th.
    final lastOfRound2 = DateTime.utc(2026, 11, 5, 20);

    Future<MyH2hLeague> read({
      DateTime? now,
      List<int> turns = const <int>[],
    }) async {
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
        turns: turns,
        lastKickoffs: {1: DateTime.utc(2026, 11, 3, 20), 2: lastOfRound2},
      );
      final result = await _useCase(
        leagues: leagues,
        rounds: rounds,
        sheets: sheets,
        now: now ?? DateTime.utc(2026, 11, 5, 15),
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

    test('each round shows where it stands; only the settled one names the '
        'opponent before the live one last kickoff', () async {
      final reading = await read();

      expect(reading.rounds.map((r) => r.status).toList(), [
        H2hRoundStatus.settled,
        H2hRoundStatus.live,
        H2hRoundStatus.upcoming,
      ]);
      expect(reading.rounds.map((r) => r.opponentId).toList(), [
        u4,
        null,
        null,
      ]);
      expect(reading.rounds.map((r) => r.opponentHidden).toList(), [
        false,
        true,
        true,
      ]);
      expect(reading.rounds.map((r) => r.revealsAt).toList(), [
        null,
        lastOfRound2,
        null,
      ]);
      expect(reading.rounds[0].match!.result, H2hMatchResult.win);
      // The live round: the caller's own points, no match against anyone.
      expect(reading.rounds[1].match, isNull);
      expect(reading.rounds[1].ownPoints, 1);
      expect(reading.rounds[2].match, isNull);
      expect(reading.rounds[2].ownPoints, isNull);
    });

    test('at the live round last kickoff its opponent is named', () async {
      final reading = await read(now: lastOfRound2);

      expect(reading.rounds.map((r) => r.opponentId).toList(), [u4, u2, null]);
      expect(reading.rounds[1].opponentHidden, isFalse);
      expect(reading.rounds[1].revealsAt, isNull);
      expect(reading.rounds[1].ownPoints, isNull);
      expect(reading.rounds[1].match!.points, 1);
      expect(reading.rounds[1].match!.opponentPoints, 4);
      expect(reading.rounds[1].match!.result, H2hMatchResult.loss);
      expect(reading.rounds[2].opponentHidden, isTrue);
    });

    test(
      'the group secret order decides the opponents and the table',
      () async {
        // Round 1 plays turn 3 (0-2, 1-3), round 2 turn 1 (0-3, 1-2).
        final reading = await read(now: lastOfRound2, turns: const [3, 1, 2]);

        expect(reading.rounds.map((r) => r.opponentId).toList(), [
          u3,
          u4,
          null,
        ]);
        // Round 1 in that order: me 5 beat u3's 3, u4's 2 lost to u2's 3.
        expect(reading.rounds[0].match!.opponentPoints, 3);
        expect(reading.rounds[0].match!.result, H2hMatchResult.win);
        final byUser = {
          for (final p in reading.placings) p.standing.userId: p.standing,
        };
        expect(byUser[u2]!.leaguePoints, 3);
        expect(byUser[u3]!.leaguePoints, 0);
        expect(byUser[u4]!.leaguePoints, 0);
        // Round 2 in that order: me 1 against u4, who has no score.
        expect(reading.rounds[1].match!.opponentPoints, 0);
        expect(reading.rounds[1].match!.result, H2hMatchResult.win);
      },
    );

    test(
      'carries names; an extra group of the elite draw has no zone (NK182)',
      () async {
        final reading = await read();

        expect(reading.profiles[u2]!.displayName, 'name ${u2.value}');
        // November 2026 is drawn by the elite draw: the second division
        // holds the extra groups, which neither go to the cup nor go down
        // by place.
        expect(reading.promotionZone, 0);
        expect(reading.relegationZone, 0);
      },
    );
  });
}
