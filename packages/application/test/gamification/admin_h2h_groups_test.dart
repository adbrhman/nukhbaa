import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

final _november = DateTime.utc(2026, 11);
const _groupA = H2hLeagueId('33333333-3333-4333-8333-33333333333a');
const _groupB = H2hLeagueId('33333333-3333-4333-8333-33333333333b');
final _now = DateTime.utc(2026, 11, 5, 15);

H2hRound _round(int number, int day, {required bool locked}) => H2hRound(
  id: H2hRoundId('44444444-4444-4444-8444-00000000000$number'),
  monthStart: _november,
  number: number,
  day: DateTime.utc(2026, 11, day),
  fixtureCount: 6,
  approvedBy: null,
  lockedAt: locked ? DateTime.utc(2026, 11, day, 12) : null,
);

H2hRoundScore _score(UserId user, int round, int points) => H2hRoundScore(
  userId: user,
  round: round,
  points: points,
  exactCount: 0,
  predictedCount: 2,
);

/// Two groups of four in the open division (users 1-4 and 5-8). Round 1
/// settled, round 2 not started.
({
  FakeH2hLeagueStore leagues,
  FakeH2hRoundStore rounds,
  FakeH2hSheetReader sheets,
})
_world() {
  final leagues = FakeH2hLeagueStore()
    ..months[_november] = H2hMonthInfo(
      monthStart: _november,
      isPilot: false,
      seatedCount: 8,
    )
    ..drawn[_november] = <H2hDrawnGroup>[
      for (final (index, id) in [_groupA, _groupB].indexed)
        H2hDrawnGroup(
          leagueId: id,
          group: H2hDrawGroup(
            division: H2hDivision.fourth,
            groupIndex: index,
            seats: [
              for (var s = 0; s < 4; s++)
                H2hDrawSeat(userId: userNo(index * 4 + s + 1), slot: s),
            ],
          ),
        ),
    ]
    // User 6 sits in slot 1 of group B.
    ..seat(
      userNo(6),
      H2hSeat(
        leagueId: _groupB,
        monthStart: _november,
        division: H2hDivision.fourth,
        groupIndex: 1,
        slot: 1,
        capacity: 4,
        divisionGroups: 2,
        isPilot: false,
        joinedAt: _november,
      ),
    );
  final rounds = FakeH2hRoundStore()
    ..addRound(_round(1, 3, locked: true))
    ..addRound(_round(2, 7, locked: false));
  final sheets = FakeH2hSheetReader();
  for (final (index, id) in [_groupA, _groupB].indexed) {
    sheets.sheets[id] = H2hGroupSheet(
      members: [
        for (var s = 0; s < 4; s++)
          H2hMember(
            userId: userNo(index * 4 + s + 1),
            slot: s,
            joinedAt: DateTime.utc(2026, 11, 1, 0, s),
          ),
      ],
      scores: [
        for (var s = 0; s < 4; s++)
          _score(userNo(index * 4 + s + 1), 1, 10 - s),
      ],
      settledRounds: const <int>{1},
      voidRounds: const <int>{},
    );
  }
  return (leagues: leagues, rounds: rounds, sheets: sheets);
}

void main() {
  group('AdminGetH2hGroups', () {
    AdminGetH2hGroups useCase() {
      final w = _world();
      return AdminGetH2hGroups(
        leagues: w.leagues,
        rounds: w.rounds,
        sheets: w.sheets,
        profiles: NamingProfiles(),
        clock: AtClock(_now),
      );
    }

    test('every group, its table and its zones', () async {
      final result = await useCase()(principal: admin);

      final month = (result as Ok<H2hAdminMonth>).value;
      expect(month.monthStart, _november);
      expect(month.info!.seatedCount, 8);
      expect(month.rounds.map((r) => r.number).toList(), [1, 2]);
      expect(month.groups.map((g) => g.ref.leagueId).toList(), [
        _groupA,
        _groupB,
      ]);
      final first = month.groups.first;
      expect(first.members, hasLength(4));
      expect(first.placings.first.standing.played, 1);
      // The open division: nobody goes down; with two groups only
      // 3 ~/ 2 = 1 place up is certain in each.
      expect(first.relegationZone, 0);
      expect(first.promotionZone, 1);
      expect(month.profiles[userNo(8)]!.displayName, 'name ${userNo(8).value}');
    });

    test('a player is refused', () async {
      final result = await useCase()(principal: player);

      expect(
        (result as Err<H2hAdminMonth>).error.kind,
        ErrorKind.authorization,
      );
    });
  });

  group('AdminGetH2hGroupRound', () {
    AdminGetH2hGroupRound useCase() {
      final w = _world();
      return AdminGetH2hGroupRound(
        leagues: w.leagues,
        rounds: w.rounds,
        sheets: w.sheets,
        profiles: NamingProfiles(),
        clock: AtClock(_now),
      );
    }

    test('every member of the group is in exactly one match', () async {
      final result = await useCase()(
        principal: admin,
        leagueId: _groupB,
        round: 1,
      );

      final group = (result as Ok<H2hAdminGroupRound>).value;
      expect(group.phase, H2hRoundPhase.settled);
      final seen = <UserId>[
        for (final pair in group.pairs) ...[
          pair.home,
          if (pair.away case final away?) away,
        ],
      ];
      expect(seen.toSet(), {for (var n = 5; n <= 8; n++) userNo(n)});
      expect(seen, hasLength(4));
      expect(group.pairs.every((p) => p.homePoints != null), isTrue);
    });

    test('the round ahead is open and carries no points', () async {
      final result = await useCase()(
        principal: admin,
        leagueId: _groupA,
        round: 2,
      );

      final group = (result as Ok<H2hAdminGroupRound>).value;
      expect(group.phase, H2hRoundPhase.open);
      expect(group.pairs.every((p) => p.winner == null), isTrue);
    });

    test('an unknown group or round is refused', () async {
      final noGroup = await useCase()(
        principal: admin,
        leagueId: const H2hLeagueId('33333333-3333-4333-8333-333333333399'),
        round: 1,
      );
      final noRound = await useCase()(
        principal: admin,
        leagueId: _groupA,
        round: 9,
      );

      expect(
        (noGroup as Err<H2hAdminGroupRound>).error.code,
        'h2h.group_unknown',
      );
      expect(
        (noRound as Err<H2hAdminGroupRound>).error.code,
        'h2h.round_unknown',
      );
    });

    test('a player is refused', () async {
      final result = await useCase()(
        principal: player,
        leagueId: _groupA,
        round: 1,
      );

      expect(
        (result as Err<H2hAdminGroupRound>).error.kind,
        ErrorKind.authorization,
      );
    });
  });

  group('AdminGetH2hPlayer', () {
    test('reads the month exactly as the player sees it', () async {
      final w = _world();
      final clock = AtClock(_now);
      final useCase = AdminGetH2hPlayer(
        month: GetMyH2hMonth(
          league: GetMyH2hLeague(
            leagues: w.leagues,
            rounds: w.rounds,
            sheets: w.sheets,
            profiles: NamingProfiles(),
            clock: clock,
          ),
          rounds: w.rounds,
          clock: clock,
        ),
      );

      final result = await useCase(principal: admin, userId: userNo(6));

      final month = (result as Ok<MyH2hMonth>).value;
      expect(month.league.state, H2hLeagueState.open);
      expect(month.league.readerId, userNo(6));
      expect(month.league.seat!.leagueId, _groupB);
      expect(month.phases, {1: H2hRoundPhase.settled, 2: H2hRoundPhase.open});
    });

    test('a player is refused', () async {
      final w = _world();
      final clock = AtClock(_now);
      final result = await AdminGetH2hPlayer(
        month: GetMyH2hMonth(
          league: GetMyH2hLeague(
            leagues: w.leagues,
            rounds: w.rounds,
            sheets: w.sheets,
            profiles: NamingProfiles(),
            clock: clock,
          ),
          rounds: w.rounds,
          clock: clock,
        ),
      )(principal: player, userId: userNo(6));

      expect((result as Err<MyH2hMonth>).error.kind, ErrorKind.authorization);
    });
  });

  group('h2hGroupPairs', () {
    final members = [
      for (var s = 0; s < 4; s++)
        H2hMember(
          userId: userNo(s + 1),
          slot: s,
          joinedAt: DateTime.utc(2026, 11, 1, 0, s),
        ),
    ];

    test('round 1 of four: 0-3 and 1-2, the first named member first', () {
      final pairs = h2hGroupPairs(
        members: members,
        capacity: 4,
        round: H2hRoundRef(number: 1, day: DateTime.utc(2026, 11, 3)),
        status: H2hRoundStatus.settled,
        scores: [
          _score(userNo(1), 1, 5),
          _score(userNo(4), 1, 2),
          _score(userNo(2), 1, 3),
          _score(userNo(3), 1, 3),
        ],
        first: userNo(3),
      );

      expect(pairs.map((p) => (p.home, p.away)).toList(), [
        (userNo(3), userNo(2)),
        (userNo(1), userNo(4)),
      ]);
      expect(pairs.first.winner, H2hPairWinner.draw);
      expect(pairs.last.winner, H2hPairWinner.home);
    });
  });
}
