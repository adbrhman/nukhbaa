import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

final _november = DateTime.utc(2026, 11);
const _league = H2hLeagueId('33333333-3333-4333-8333-333333333333');
final _me = player.userId;

// Four seats. Round 1: 0-3, 1-2. Round 2: 0-1, 2-3.
final _u2 = userNo(2);
final _u3 = userNo(3);
final _u4 = userNo(4);

H2hRound _round(int number, int day, {required bool locked}) => H2hRound(
  id: H2hRoundId('44444444-4444-4444-8444-00000000000$number'),
  monthStart: _november,
  number: number,
  day: DateTime.utc(2026, 11, day),
  fixtureCount: 4,
  approvedBy: null,
  lockedAt: locked ? DateTime.utc(2026, 11, day, 12) : null,
);

H2hFixturePick _pick(
  int home,
  int away, {
  bool isDouble = false,
  int? points,
  bool exact = false,
}) => H2hFixturePick(
  homeGoals: home,
  awayGoals: away,
  isDouble: isDouble,
  points: points,
  exact: exact,
);

H2hRoundFixture _fixture(
  String id,
  DateTime? kickoff, {
  bool counted = true,
  int? homeGoals,
  int? awayGoals,
  H2hFixturePick? mine,
  H2hFixturePick? theirs,
}) => H2hRoundFixture(
  fixtureId: id,
  homeTeam: 'home $id',
  awayTeam: 'away $id',
  homeTeamId: null,
  awayTeamId: null,
  kickoffAt: kickoff,
  counted: counted,
  homeGoals: homeGoals,
  awayGoals: awayGoals,
  mine: mine,
  theirs: theirs,
);

/// Round 1 on 3 November. It hands the opponent's pick back on EVERY
/// fixture, kicked off or not, as a broken adapter would: the use-case alone
/// must keep the not-started ones secret.
final class _LeakyReader implements H2hRoundFixtureReader {
  final List<({H2hRound round, UserId reader, UserId? opponent, DateTime now})>
  calls = [];

  @override
  Future<Result<List<H2hRoundFixture>>> fixturesOf({
    required H2hRound round,
    required UserId reader,
    required UserId? opponent,
    required DateTime nowUtc,
  }) async {
    calls.add((round: round, reader: reader, opponent: opponent, now: nowUtc));
    return Result.ok([
      // Listed out of order on purpose.
      _fixture(
        'f3',
        null,
        mine: _pick(0, 0),
        theirs: _pick(3, 3, isDouble: true),
      ),
      _fixture(
        'f2',
        DateTime.utc(2026, 11, 3, 15),
        mine: _pick(1, 0),
        theirs: _pick(2, 2, isDouble: true),
      ),
      _fixture(
        'f1',
        DateTime.utc(2026, 11, 3, 12),
        homeGoals: 2,
        awayGoals: 1,
        mine: _pick(2, 1, isDouble: true, points: 10, exact: true),
        theirs: _pick(0, 1, points: 0),
      ),
      _fixture(
        'f4',
        DateTime.utc(2026, 11, 3, 13),
        counted: false,
        mine: _pick(1, 1, exact: true),
        theirs: _pick(1, 1, isDouble: true, exact: true),
      ),
    ]);
  }
}

FakeH2hLeagueStore _seated() => FakeH2hLeagueStore()
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

FakeH2hSheetReader _sheet({required bool withOpponent, int myPoints = 10}) {
  final members = <UserId>[_me, _u2, _u3, if (withOpponent) _u4];
  return FakeH2hSheetReader()
    ..sheets[_league] = H2hGroupSheet(
      members: [
        for (final (i, user) in members.indexed)
          H2hMember(
            userId: user,
            slot: i,
            joinedAt: DateTime.utc(2026, 11, 1, 0, i),
          ),
      ],
      scores: [
        H2hRoundScore(
          userId: _me,
          round: 1,
          points: myPoints,
          exactCount: 1,
          predictedCount: 3,
        ),
      ],
      settledRounds: const <int>{},
      voidRounds: const <int>{},
    );
}

Future<Result<MyH2hRoundDetail>> _read({
  required DateTime now,
  _LeakyReader? reader,
  FakeH2hLeagueStore? leagues,
  bool withOpponent = true,
  int round = 1,
  int myPoints = 10,
}) {
  final clock = AtClock(now);
  final rounds = FakeH2hRoundStore()
    ..addRound(_round(1, 3, locked: true))
    ..addRound(_round(2, 5, locked: false));
  return GetMyH2hRound(
    league: GetMyH2hLeague(
      leagues: leagues ?? _seated(),
      rounds: rounds,
      sheets: _sheet(withOpponent: withOpponent, myPoints: myPoints),
      profiles: NamingProfiles(),
      clock: clock,
    ),
    fixtures: reader ?? _LeakyReader(),
    clock: clock,
  ).call(principal: player, round: round);
}

H2hRoundFixtureView _line(MyH2hRoundDetail detail, String id) =>
    detail.fixtures.singleWhere((f) => f.fixtureId == id);

void main() {
  group('GetMyH2hRound keeps the opponent secret until kickoff', () {
    test('a minute before kickoff the pick is withheld', () async {
      final detail =
          ((await _read(now: DateTime.utc(2026, 11, 3, 14, 59)))
                  as Ok<MyH2hRoundDetail>)
              .value;

      final f2 = _line(detail, 'f2');
      expect(f2.theirs, isNull);
      expect(f2.theirsHidden, isTrue);
      expect(f2.state, H2hFixtureState.notStarted);
      expect(f2.mine!.homeGoals, 1, reason: 'the caller sees their own pick');

      final f1 = _line(detail, 'f1');
      expect(f1.theirs!.awayGoals, 1);
      expect(f1.theirsHidden, isFalse);
      expect(f1.state, H2hFixtureState.finished);
    });

    test(
      'at the kickoff minute the pick is shown (the lock is inclusive)',
      () async {
        final detail =
            ((await _read(now: DateTime.utc(2026, 11, 3, 15)))
                    as Ok<MyH2hRoundDetail>)
                .value;

        final f2 = _line(detail, 'f2');
        expect(f2.theirs!.homeGoals, 2);
        expect(f2.theirs!.isDouble, isTrue);
        expect(f2.theirsHidden, isFalse);
        expect(f2.state, H2hFixtureState.live);
      },
    );

    test('a fixture with no kickoff stays hidden, however late', () async {
      final detail =
          ((await _read(now: DateTime.utc(2026, 11, 30, 20)))
                  as Ok<MyH2hRoundDetail>)
              .value;

      final f3 = _line(detail, 'f3');
      expect(f3.theirs, isNull);
      expect(f3.theirsHidden, isTrue);
      expect(f3.state, H2hFixtureState.notStarted);
    });

    test('their counts cover kicked-off fixtures that count, only', () async {
      final detail =
          ((await _read(now: DateTime.utc(2026, 11, 3, 14, 59)))
                  as Ok<MyH2hRoundDetail>)
              .value;

      // f1 only: f2 and f3 are not kicked off, f4 is void.
      expect(detail.theirs!.predicted, 1);
      expect(detail.theirs!.doubles, 0);
      expect(detail.theirs!.exact, 0);
    });

    test(
      'the reader is asked with the server clock and the opponent',
      () async {
        final reader = _LeakyReader();
        final now = DateTime.utc(2026, 11, 3, 14, 59);
        await _read(now: now, reader: reader);

        expect(reader.calls, hasLength(1));
        expect(reader.calls.single.now, now);
        expect(reader.calls.single.opponent, _u4);
        expect(reader.calls.single.reader, _me);
        expect(reader.calls.single.round.number, 1);
      },
    );
  });

  group('GetMyH2hRound reads the round', () {
    test(
      'fixtures by kickoff, none registered last; void stays void',
      () async {
        final detail =
            ((await _read(now: DateTime.utc(2026, 11, 3, 14, 59)))
                    as Ok<MyH2hRoundDetail>)
                .value;

        expect(detail.fixtures.map((f) => f.fixtureId).toList(), [
          'f1',
          'f4',
          'f2',
          'f3',
        ]);
        expect(_line(detail, 'f4').state, H2hFixtureState.voided);
        expect(detail.firstKickoff, DateTime.utc(2026, 11, 3, 12));
      },
    );

    test('my counts cover the fixtures that count', () async {
      final detail =
          ((await _read(now: DateTime.utc(2026, 11, 3, 14, 59)))
                  as Ok<MyH2hRoundDetail>)
              .value;

      // f1, f2, f3 count; f4 is void.
      expect(detail.mine.predicted, 3);
      expect(detail.mine.exact, 1);
      expect(detail.mine.doubles, 1);
    });

    test('the round, its phase, the opponent and the points', () async {
      final detail =
          ((await _read(now: DateTime.utc(2026, 11, 3, 14, 59)))
                  as Ok<MyH2hRoundDetail>)
              .value;

      expect(detail.phase, H2hRoundPhase.live);
      expect(detail.opponentId, _u4);
      expect(detail.opponentProfile!.displayName, 'name ${_u4.value}');
      expect(detail.myPoints, 10);
      expect(detail.opponentPoints, 0);
      expect(detail.result, H2hMatchResult.win);
    });

    test('a live round never tells whether the opponent predicted', () async {
      // u4 has no pick on any fixture yet, kicked off or not. The policy
      // calls that a win for the caller; shown live, it would say so.
      final detail =
          ((await _read(now: DateTime.utc(2026, 11, 3, 14, 59), myPoints: 0))
                  as Ok<MyH2hRoundDetail>)
              .value;

      expect(detail.myPoints, 0);
      expect(detail.opponentPoints, 0);
      expect(detail.result, H2hMatchResult.draw);
    });

    test('with the group average nothing of an opponent is shown', () async {
      final detail =
          ((await _read(
                    now: DateTime.utc(2026, 11, 3, 14, 59),
                    withOpponent: false,
                  ))
                  as Ok<MyH2hRoundDetail>)
              .value;

      expect(detail.opponentId, isNull);
      expect(detail.opponentProfile, isNull);
      expect(detail.theirs, isNull);
      for (final line in detail.fixtures) {
        expect(line.theirs, isNull, reason: line.fixtureId);
        expect(line.theirsHidden, isFalse, reason: line.fixtureId);
      }
    });

    test('the next round is open, and nothing of theirs shows', () async {
      final detail =
          ((await _read(now: DateTime.utc(2026, 11, 3, 14, 59), round: 2))
                  as Ok<MyH2hRoundDetail>)
              .value;

      expect(detail.phase, H2hRoundPhase.open);
      expect(detail.result, isNull);
      expect(detail.opponentId, _u2);
      // The leaky reader's 13:00 and 12:00 fixtures have kicked off on the
      // 3rd; everything kicking off later stays hidden.
      expect(_line(detail, 'f2').theirs, isNull);
      expect(_line(detail, 'f3').theirs, isNull);
    });

    test('a caller with no seat is refused', () async {
      final result = await _read(
        now: DateTime.utc(2026, 11, 3, 14, 59),
        leagues: FakeH2hLeagueStore(),
      );

      expect((result as Err<MyH2hRoundDetail>).error.code, 'h2h.not_seated');
    });

    test('a round the month does not have is refused', () async {
      final result = await _read(
        now: DateTime.utc(2026, 11, 3, 14, 59),
        round: 7,
      );

      expect((result as Err<MyH2hRoundDetail>).error.code, 'h2h.round_unknown');
    });
  });

  group('GetMyH2hRound.hasKickedOff', () {
    final kickoff = DateTime.utc(2026, 11, 3, 15);

    test('a microsecond before, at the kickoff, and with none', () {
      expect(
        GetMyH2hRound.hasKickedOff(
          kickoffAt: kickoff,
          nowUtc: kickoff.subtract(const Duration(microseconds: 1)),
        ),
        isFalse,
      );
      expect(
        GetMyH2hRound.hasKickedOff(kickoffAt: kickoff, nowUtc: kickoff),
        isTrue,
      );
      expect(
        GetMyH2hRound.hasKickedOff(kickoffAt: null, nowUtc: kickoff),
        isFalse,
      );
    });

    test('a kickoff that is not UTC is treated as not started', () {
      expect(
        GetMyH2hRound.hasKickedOff(
          kickoffAt: DateTime(2026, 11, 3, 15),
          nowUtc: DateTime.utc(2027),
        ),
        isFalse,
      );
    });
  });
}
