import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

final _november = DateTime.utc(2026, 11);
final _october = DateTime.utc(2026, 10);
const _groupA = H2hLeagueId('33333333-3333-4333-8333-33333333333a');
const _groupB = H2hLeagueId('33333333-3333-4333-8333-33333333333b');
const _groupC = H2hLeagueId('33333333-3333-4333-8333-33333333333c');

H2hRound _round(DateTime month) => H2hRound(
  id: const H2hRoundId('44444444-4444-4444-8444-000000000001'),
  monthStart: month,
  number: 1,
  day: DateTime.utc(month.year, month.month, 3),
  fixtureCount: 6,
  approvedBy: null,
  lockedAt: DateTime.utc(month.year, month.month, 3, 12),
);

H2hGroupSheet _sheet(int firstUser) => H2hGroupSheet(
  members: [
    for (var s = 0; s < 4; s++)
      H2hMember(
        userId: userNo(firstUser + s),
        slot: s,
        joinedAt: DateTime.utc(2026, 11, 1, 0, s),
      ),
  ],
  scores: [
    for (var s = 0; s < 4; s++)
      H2hRoundScore(
        userId: userNo(firstUser + s),
        round: 1,
        points: 10 - s,
        exactCount: 0,
        predictedCount: 2,
      ),
  ],
  settledRounds: const <int>{1},
  voidRounds: const <int>{},
);

/// Two elite groups (users 1-4, 5-8) and one open-division group (9-12) in
/// [month]; round 1 settled.
GetH2hEliteTables _useCase({
  DateTime? month,
  bool pilot = false,
  bool drawn = true,
}) {
  final at = month ?? _november;
  final leagues = FakeH2hLeagueStore();
  if (drawn) {
    leagues
      ..months[at] = H2hMonthInfo(
        monthStart: at,
        isPilot: pilot,
        seatedCount: 12,
      )
      ..drawn[at] = <H2hDrawnGroup>[
        for (final (index, entry) in [
          (_groupA, H2hDivision.first),
          (_groupB, H2hDivision.first),
          (_groupC, H2hDivision.fourth),
        ].indexed)
          H2hDrawnGroup(
            leagueId: entry.$1,
            group: H2hDrawGroup(
              division: entry.$2,
              groupIndex: entry.$2 == H2hDivision.first ? index : 0,
              seats: [
                for (var s = 0; s < 4; s++)
                  H2hDrawSeat(userId: userNo(index * 4 + s + 1), slot: s),
              ],
            ),
          ),
      ];
  }
  final rounds = FakeH2hRoundStore()..addRound(_round(at));
  final sheets = FakeH2hSheetReader()
    ..sheets[_groupA] = _sheet(1)
    ..sheets[_groupB] = _sheet(5)
    ..sheets[_groupC] = _sheet(9);
  return GetH2hEliteTables(
    groups: AdminGetH2hGroups(
      leagues: leagues,
      rounds: rounds,
      sheets: sheets,
      profiles: NamingProfiles(),
      clock: AtClock(DateTime.utc(at.year, at.month, 5, 15)),
    ),
  );
}

void main() {
  group('GetH2hEliteTables', () {
    test('a player reads the elite groups, not the open division', () async {
      final result = await _useCase()(principal: player);

      final month = (result as Ok<H2hAdminMonth>).value;
      expect(month.monthStart, _november);
      expect(month.groups.map((g) => g.ref.leagueId).toList(), [
        _groupA,
        _groupB,
      ]);
      expect(
        month.groups.every((g) => g.ref.division == H2hDivision.first),
        isTrue,
      );
      // The table is the settled round's.
      expect(month.groups.first.placings.first.standing.played, 1);
      // No cup places beyond the elite's, nobody goes down.
      expect(month.groups.first.relegationZone, 0);
    });

    test('only the elite members are named', () async {
      final result = await _useCase()(principal: player);

      final month = (result as Ok<H2hAdminMonth>).value;
      expect(month.profiles.keys.toSet(), {
        for (var n = 1; n <= 8; n++) userNo(n),
      });
    });

    test('rounds and matches are not part of the reading', () async {
      final result = await _useCase()(principal: player);

      expect((result as Ok<H2hAdminMonth>).value.rounds, isEmpty);
    });

    test('an admin may read it too', () async {
      final result = await _useCase()(principal: admin);

      expect((result as Ok<H2hAdminMonth>).value.groups, hasLength(2));
    });

    test('a month before the elite draw has none', () async {
      final result = await _useCase(month: _october)(principal: player);

      final month = (result as Ok<H2hAdminMonth>).value;
      expect(month.groups, isEmpty);
      expect(month.profiles, isEmpty);
    });

    test('a hidden pilot month has none', () async {
      final result = await _useCase(pilot: true)(principal: player);

      expect((result as Ok<H2hAdminMonth>).value.groups, isEmpty);
    });

    test('a month not drawn has none', () async {
      final result = await _useCase(drawn: false)(principal: player);

      final month = (result as Ok<H2hAdminMonth>).value;
      expect(month.info, isNull);
      expect(month.groups, isEmpty);
    });
  });
}
