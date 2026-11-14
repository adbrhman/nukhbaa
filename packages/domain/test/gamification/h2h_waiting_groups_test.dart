/// New players and the waiting group (NK277, decided by the owner on
/// 2026-11-14, December 2026 on): the draw's last extra group under twenty
/// waits; a waiting group plays no round before it starts; a group that
/// starts with fewer than seven rounds left takes no part in the month's
/// promotion and relegation but keeps its results. November keeps its
/// draw.
library;

import 'package:domain/domain.dart';
import 'package:test/test.dart';

UserId _u(int i) =>
    UserId('00000000-0000-4000-8277-${i.toString().padLeft(12, '0')}');

List<UserId> _players(int n) => [for (var i = 0; i < n; i++) _u(i)];

H2hPlacing _placing(int user, int rank, {int slot = -1}) => H2hPlacing(
  rank: rank,
  standing: H2hStanding(
    userId: _u(user),
    slot: slot < 0 ? rank - 1 : slot,
    joinedAt: DateTime.utc(2026, 12),
    won: 0,
    drawn: 0,
    lost: 0,
    pointsFor: 99 - rank,
    exactCount: 0,
    presentRounds: 0,
    matches: const <H2hMatch>[],
  ),
);

H2hEliteGroup _group(
  H2hDivision division,
  int index,
  int first,
  int size, {
  bool counted = true,
}) => H2hEliteGroup(
  division: division,
  groupIndex: index,
  counted: counted,
  placings: [for (var k = 0; k < size; k++) _placing(first + k, k + 1)],
);

H2hCommitment _c({int absent = 0, int predicted = 50}) => H2hCommitment(
  absentRounds: absent,
  predicted: predicted,
  exact: 0,
  outcomes: 0,
  points: 0,
);

void main() {
  group('the draw', () {
    test('December: the last extra group under twenty waits, in twenty '
        'seats', () {
      final groups = H2hLeaguePolicy.eliteDraw(
        _players(113),
        waitingRest: true,
      );
      final extra = [
        for (final g in groups)
          if (g.division == H2hLeaguePolicy.extraDivision) g,
      ];
      expect(extra, hasLength(2));
      expect(extra[0].seats, hasLength(20));
      expect(extra[0].waiting, isFalse);
      expect(extra[1].seats, hasLength(13));
      expect(extra[1].waiting, isTrue);
      expect(extra[1].capacity, H2hLeaguePolicy.groupCapacity);
      expect(
        groups.where((g) => g.division == H2hLeaguePolicy.eliteDivision),
        everyElement(
          isA<H2hDrawGroup>().having((g) => g.waiting, 'waiting', isFalse),
        ),
      );
    });

    test('December: a single player left over waits alone, no 21st seat', () {
      final groups = H2hLeaguePolicy.eliteDraw(
        _players(101),
        waitingRest: true,
      );
      final extra = [
        for (final g in groups)
          if (g.division == H2hLeaguePolicy.extraDivision) g,
      ];
      expect([for (final g in extra) g.seats.length], [20, 1]);
      expect([for (final g in extra) g.waiting], [false, true]);
      expect(extra.every((g) => g.capacity == 20), isTrue);
    });

    test('December: twenty exactly leaves no waiting group', () {
      final groups = H2hLeaguePolicy.eliteDraw(
        _players(100),
        waitingRest: true,
      );
      expect(groups.any((g) => g.waiting), isFalse);
    });

    test('November keeps its draw: the single player is the 21st of 22 '
        'seats and nobody waits', () {
      final groups = H2hLeaguePolicy.eliteDraw(_players(101));
      final extra = [
        for (final g in groups)
          if (g.division == H2hLeaguePolicy.extraDivision) g,
      ];
      expect([for (final g in extra) g.seats.length], [21]);
      expect(extra.single.capacity, 22);
      expect(groups.any((g) => g.waiting), isFalse);
    });
  });

  group('the start', () {
    test('seven rounds or more left take part; fewer, or never started, do '
        'not', () {
      expect(H2hLeaguePolicy.countsForMovement(1), isTrue);
      expect(H2hLeaguePolicy.countsForMovement(13), isTrue);
      expect(H2hLeaguePolicy.countsForMovement(14), isFalse);
      expect(H2hLeaguePolicy.countsForMovement(19), isFalse);
      expect(
        H2hLeaguePolicy.countsForMovement(H2hLeaguePolicy.waitingFromRound),
        isFalse,
      );
    });

    test('a group starts at its earliest seat; a waiting member plays '
        'nothing', () {
      final drawn = [
        H2hMember(userId: _u(1), slot: 0, joinedAt: DateTime.utc(2026, 12)),
        H2hMember(
          userId: _u(2),
          slot: 1,
          joinedAt: DateTime.utc(2026, 12),
          fromRound: 9,
        ),
      ];
      expect(H2hLeaguePolicy.groupStartOf(drawn), 1);
      final late = [
        for (var s = 0; s < 3; s++)
          H2hMember(
            userId: _u(10 + s),
            slot: s,
            joinedAt: DateTime.utc(2026, 12),
            fromRound: 8,
          ),
      ];
      expect(H2hLeaguePolicy.groupStartOf(late), 8);
      final waiting = H2hMember(
        userId: _u(20),
        slot: 0,
        joinedAt: DateTime.utc(2026, 12),
        fromRound: H2hLeaguePolicy.waitingFromRound,
      );
      expect(waiting.waiting, isTrue);
      expect(late.first.waiting, isFalse);
      expect([
        for (var r = 1; r <= 19; r++) waiting.activeIn(r),
      ], everyElement(isFalse));
    });

    test('a group that started at round 8 plays rounds 8 on, nothing '
        'before: no loss, no absence', () {
      final members = [
        for (var s = 0; s < 20; s++)
          H2hMember(
            userId: _u(s),
            slot: s,
            joinedAt: DateTime.utc(2026, 12),
            fromRound: 8,
          ),
      ];
      final rounds = [
        for (var n = 1; n <= 9; n++)
          H2hRoundRef(number: n, day: DateTime.utc(2026, 12, n)),
      ];
      final scores = [
        for (var n = 1; n <= 9; n++)
          for (var s = 0; s < 20; s++)
            H2hRoundScore(
              userId: _u(s),
              round: n,
              points: s,
              exactCount: 0,
              predictedCount: 6,
            ),
      ];
      final table = H2hLeaguePolicy.table(
        capacity: 20,
        members: members,
        rounds: rounds,
        scores: scores,
      );
      for (final standing in table) {
        expect(standing.played, 2, reason: '${standing.userId}');
        expect(
          [for (final m in standing.matches) m.round],
          [8, 9],
          reason: '${standing.userId}',
        );
      }
    });

    test('a waiting group that never started has no match at all', () {
      final members = [
        for (var s = 0; s < 5; s++)
          H2hMember(
            userId: _u(s),
            slot: s,
            joinedAt: DateTime.utc(2026, 12),
            fromRound: H2hLeaguePolicy.waitingFromRound,
          ),
      ];
      final table = H2hLeaguePolicy.table(
        capacity: 20,
        members: members,
        rounds: [
          for (var n = 1; n <= 19; n++)
            H2hRoundRef(number: n, day: DateTime.utc(2026, 12, n)),
        ],
        scores: const <H2hRoundScore>[],
      );
      expect(table, hasLength(5));
      expect(table.every((s) => s.matches.isEmpty && s.lost == 0), isTrue);
    });
  });

  group('the carry', () {
    // Four elite groups (0..79), group 5 counted (100..119), group 6
    // started at round 15 (200..219), group 7 never started (300..304).
    final groups = <H2hEliteGroup>[
      for (var g = 0; g < 4; g++)
        _group(H2hLeaguePolicy.eliteDivision, g, g * 20, 20),
      _group(H2hLeaguePolicy.extraDivision, 0, 100, 20),
      _group(H2hLeaguePolicy.extraDivision, 1, 200, 20, counted: false),
      H2hEliteGroup(
        division: H2hLeaguePolicy.extraDivision,
        groupIndex: 2,
        counted: false,
        placings: [
          // Joined in the order 304, 303, ... 300 (slot 0 is 304).
          for (var k = 0; k < 5; k++) _placing(300 + k, k + 1, slot: 4 - k),
        ],
      ),
    ];
    final everyone = <int>[
      for (var i = 0; i < 80; i++) i,
      for (var i = 100; i < 120; i++) i,
      for (var i = 200; i < 220; i++) i,
      for (var i = 300; i < 305; i++) i,
    ];
    // Group 6 played: 210..219 missed nothing, the rest missed two. The
    // never-started group has no measure.
    final commitment = <UserId, H2hCommitment>{
      for (var i = 0; i < 120; i++) _u(i): _c(absent: 1),
      for (var i = 200; i < 220; i++) _u(i): _c(absent: i < 210 ? 2 : 0),
    };
    final finishes = H2hEliteCarry.next(
      groups: groups,
      eligible: {for (final i in everyone) _u(i)},
      commitment: commitment,
    );
    final byUser = {
      for (final f in finishes)
        everyone.firstWhere((i) => _u(i) == f.placing.standing.userId): f,
    };

    test('every member once, the order 0..n-1 with no gap', () {
      expect(finishes, hasLength(everyone.length));
      final orders = [for (final f in finishes) f.nextOrder!]..sort();
      expect(orders, [for (var i = 0; i < everyone.length; i++) i]);
    });

    test('a group that took no part: nobody up, nobody down, held, not '
        'counted', () {
      for (var i = 200; i < 220; i++) {
        expect(byUser[i]!.outcome, H2hLeagueOutcome.held, reason: '$i');
        expect(byUser[i]!.counted, isFalse);
        expect(byUser[i]!.nextOrder, greaterThanOrEqualTo(100));
      }
      for (var i = 300; i < 305; i++) {
        expect(byUser[i]!.outcome, H2hLeagueOutcome.held, reason: '$i');
        expect(byUser[i]!.counted, isFalse);
      }
    });

    test('the elite is filled from group 5 alone; group 5 sends nobody '
        'down, being the last group that took part', () {
      final up = [
        for (final e in byUser.entries)
          if (e.value.outcome == H2hLeagueOutcome.promoted) e.key,
      ];
      expect(up, hasLength(12));
      expect(up.every((i) => i >= 100 && i < 120), isTrue);
      expect([
        for (var i = 100; i < 120; i++)
          if (byUser[i]!.outcome == H2hLeagueOutcome.relegated) i,
      ], isEmpty);
    });

    test('after every other group: the late group by commitment, then the '
        'never-started group in the order it joined', () {
      final lastCounted = [
        for (final f in finishes)
          if (f.counted) f.nextOrder!,
      ].reduce((a, b) => a > b ? a : b);
      final late = [for (var i = 200; i < 220; i++) byUser[i]!.nextOrder!];
      expect(late.every((o) => o > lastCounted), isTrue);
      // The ones who missed nothing come first.
      final firstTen = [for (var i = 210; i < 220; i++) byUser[i]!.nextOrder!];
      final lastTen = [for (var i = 200; i < 210; i++) byUser[i]!.nextOrder!];
      expect(
        firstTen.reduce((a, b) => a > b ? a : b),
        lessThan(lastTen.reduce((a, b) => a < b ? a : b)),
      );
      final never = [for (var i = 304; i >= 300; i--) byUser[i]!.nextOrder!];
      expect(never.first, greaterThan(late.reduce((a, b) => a > b ? a : b)));
      expect(never, orderedEquals([...never]..sort()));
    });

    test('a group counted by default: the November carry is unchanged', () {
      const g = H2hEliteGroup(
        division: H2hDivision.second,
        groupIndex: 0,
        placings: <H2hPlacing>[],
      );
      expect(g.counted, isTrue);
    });
  });
}
