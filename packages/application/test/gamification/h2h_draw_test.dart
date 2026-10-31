import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

final _october = DateTime.utc(2026, 10);
final _november = DateTime.utc(2026, 11);
final _december = DateTime.utc(2026, 12);

/// 2026-10-31 21:30 UTC is 2026-11-01 00:30 in Riyadh: already November.
final _novemberNight = DateTime.utc(2026, 10, 31, 21, 30);

/// 2026-11-30 22:00 UTC is 2026-12-01 01:00 in Riyadh.
final _decemberNight = DateTime.utc(2026, 11, 30, 22);

DrawH2hMonth _draw(FakeH2hLeagueStore store, FakeH2hDrawSource source) =>
    DrawH2hMonth(leagues: store, source: source, idGenerator: SequenceIds());

List<UserId> _users(int from, int count) => [
  for (var i = from; i < from + count; i++) userNo(i),
];

Map<H2hDivision, int> _seatsByDivision(FakeH2hLeagueStore store, DateTime m) {
  final counts = <H2hDivision, int>{};
  for (final g in store.drawn[m] ?? const <H2hDrawnGroup>[]) {
    counts[g.group.division] =
        (counts[g.group.division] ?? 0) + g.group.seats.length;
  }
  return counts;
}

void main() {
  group('DrawH2hMonth', () {
    test('draws nothing before the league opens', () async {
      final store = FakeH2hLeagueStore();
      final result = await _draw(
        store,
        FakeH2hDrawSource(),
      ).call(now: DateTime.utc(2026, 10, 15));

      expect((result as Ok<int>).value, 0);
      expect(store.drawCalls, 0);
    });

    test('seeds the first month from the active players of the month before, '
        'in the Riyadh month', () async {
      final store = FakeH2hLeagueStore();
      final source = FakeH2hDrawSource()..active[_october] = _users(1, 45);

      final result = await _draw(store, source).call(now: _novemberNight);

      expect((result as Ok<int>).value, 45);
      expect(store.months[_november]!.isPilot, isFalse);
      // NK182: fewer than 80 players all go into the four elite groups.
      expect(_seatsByDivision(store, _november), {H2hDivision.first: 45});
      expect(store.drawn[_november], hasLength(4));
      final first = store.drawn[_november]!.first.group;
      expect(first.division, H2hDivision.first);
      expect(first.seats.first.userId, userNo(1));
      expect(source.carriedAsked, isEmpty);
    });

    test('NK182: November seats the first 80 in four even elite groups and '
        'the rest in extra groups of twenty, in the order', () async {
      final store = FakeH2hLeagueStore();
      final order = _users(1, 121);
      final source = FakeH2hDrawSource()..active[_october] = order;

      final result = await _draw(store, source).call(now: _novemberNight);

      expect((result as Ok<int>).value, 121);
      final drawn = store.drawn[_november]!;
      expect(
        [
          for (final g in drawn)
            (g.group.division, g.group.groupIndex, g.group.seats.length),
        ],
        [
          (H2hDivision.first, 0, 20),
          (H2hDivision.first, 1, 20),
          (H2hDivision.first, 2, 20),
          (H2hDivision.first, 3, 20),
          (H2hDivision.second, 0, 20),
          // The 121st player is not left out: the last group holds 21.
          (H2hDivision.second, 1, 21),
        ],
      );
      // The snake: the 1st, 8th and 9th of the order share group 1; the
      // 4th and 5th share group 4.
      expect(
        [for (final s in drawn[0].group.seats.take(3)) s.userId],
        [userNo(1), userNo(8), userNo(9)],
      );
      expect(
        [for (final s in drawn[3].group.seats.take(2)) s.userId],
        [userNo(4), userNo(5)],
      );
      // Group 5 starts with the 81st of the order.
      expect(drawn[4].group.seats.first.userId, userNo(81));
      expect(drawn[5].group.capacity, 22);
    });

    test('draws a month once', () async {
      final store = FakeH2hLeagueStore();
      final source = FakeH2hDrawSource()..active[_october] = _users(1, 5);
      await _draw(store, source).call(now: _novemberNight);

      final again = await _draw(store, source).call(now: _novemberNight);

      expect((again as Ok<int>).value, 0);
      expect(store.drawCalls, 1);
    });

    test('a pilot October does not count: November is seeded', () async {
      final store = FakeH2hLeagueStore()
        ..months[_october] = H2hMonthInfo(
          monthStart: _october,
          isPilot: true,
          seatedCount: 6,
        );
      final source = FakeH2hDrawSource()..active[_october] = _users(1, 3);

      final result = await _draw(store, source).call(now: _novemberNight);

      expect((result as Ok<int>).value, 3);
      expect(source.carriedAsked, isEmpty);
    });

    test('a later month waits until the month before is judged', () async {
      final store = FakeH2hLeagueStore()
        ..months[_november] = H2hMonthInfo(
          monthStart: _november,
          isPilot: false,
          seatedCount: 45,
        );
      final source = FakeH2hDrawSource()..active[_november] = _users(1, 45);

      final result = await _draw(store, source).call(now: _decemberNight);

      expect((result as Ok<int>).value, 0);
      expect(store.months.containsKey(_december), isFalse);
    });

    test('a later month of the elite draw waits for the carry rules, even '
        'once last month is judged', () async {
      final store = FakeH2hLeagueStore()
        ..months[_november] = H2hMonthInfo(
          monthStart: _november,
          isPilot: false,
          seatedCount: 45,
        )
        ..closed[_november] = 45;
      final carried = <H2hCarry>[
        // Deliberately out of order: the draw sorts them.
        for (var i = 0; i < 20; i++)
          H2hCarry(
            userId: userNo(100 + i),
            nextDivision: H2hDivision.second,
            division: H2hDivision.second,
            rank: i + 1,
          ),
        for (var i = 0; i < 20; i++)
          H2hCarry(
            userId: userNo(200 + i),
            nextDivision: H2hDivision.first,
            division: H2hDivision.first,
            rank: i + 1,
          ),
        for (var i = 0; i < 5; i++)
          H2hCarry(
            userId: userNo(300 + i),
            nextDivision: H2hDivision.third,
            division: H2hDivision.third,
            rank: i + 1,
          ),
      ];
      final source = FakeH2hDrawSource()
        ..carried[_november] = carried
        ..active[_november] = [
          ...carried.map((c) => c.userId),
          userNo(900),
          userNo(901),
        ];

      final result = await _draw(store, source).call(now: _decemberNight);

      // NK182: the carry of the elite groups is the next batch. A judged
      // November leaves December undrawn, with the reason, rather than
      // drawing it by the old ladder: a draw is never repeated.
      expect((result as Err<int>).error.code, 'h2h.elite_carry_pending');
      expect(store.months.containsKey(_december), isFalse);
      expect(store.drawCalls, 0);
      expect(source.carriedAsked, isEmpty);
    });
  });

  group('StartH2hPilot', () {
    StartH2hPilot pilot(
      FakeH2hLeagueStore store,
      FakeH2hDrawSource source,
      DateTime now,
    ) => StartH2hPilot(
      leagues: store,
      source: source,
      idGenerator: SequenceIds(),
      clock: AtClock(now),
    );

    final octoberDay = DateTime.utc(2026, 10, 20, 12);

    test('only an admin starts it', () async {
      final result = await pilot(
        FakeH2hLeagueStore(),
        FakeH2hDrawSource()..pilot = _users(1, 4),
        octoberDay,
      ).call(principal: player);

      expect((result as Err<int>).error.kind, ErrorKind.authorization);
    });

    test('draws the pilot users into a pilot month', () async {
      final store = FakeH2hLeagueStore();
      final result = await pilot(
        store,
        FakeH2hDrawSource()..pilot = _users(1, 6),
        octoberDay,
      ).call(principal: admin);

      expect((result as Ok<int>).value, 6);
      expect(store.months[_october]!.isPilot, isTrue);
    });

    test('is refused once the league is open', () async {
      final result = await pilot(
        FakeH2hLeagueStore(),
        FakeH2hDrawSource()..pilot = _users(1, 6),
        DateTime.utc(2026, 11, 5),
      ).call(principal: admin);

      expect((result as Err<int>).error.code, 'h2h.pilot_after_launch');
    });

    test('needs at least two pilot users', () async {
      final result = await pilot(
        FakeH2hLeagueStore(),
        FakeH2hDrawSource()..pilot = _users(1, 1),
        octoberDay,
      ).call(principal: admin);

      expect((result as Err<int>).error.code, 'h2h.pilot_too_small');
    });

    test('a month is drawn once', () async {
      final store = FakeH2hLeagueStore();
      final source = FakeH2hDrawSource()..pilot = _users(1, 4);
      await pilot(store, source, octoberDay).call(principal: admin);

      final again = await pilot(
        store,
        source,
        octoberDay,
      ).call(principal: admin);

      expect((again as Err<int>).error.code, 'h2h.pilot_already_drawn');
    });
  });
}
