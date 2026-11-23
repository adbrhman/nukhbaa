import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

final _november = DateTime.utc(2026, 11);

/// 2026-11-22 12:00 UTC: 15:00 in Riyadh, the 22nd.
final _now = DateTime.utc(2026, 11, 22, 12);

/// The Elite Cup of November as stored; every other month holds none.
final class _Cups implements H2hCupStore {
  _Cups(this.state);

  final H2hCupState state;

  @override
  Future<Result<H2hCupState>> stateOf(DateTime monthStart) async =>
      Result.ok(monthStart == _november ? state : H2hCupState.empty);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected ${invocation.memberName}');
}

H2hCupEntry _entry(int user, int place, int group) => H2hCupEntry(
  userId: userNo(user),
  place: place,
  groupNumber: group,
  leaguePoints: 40,
  pointsFor: 100,
  exactCount: 10,
);

/// Path 1's four qualifiers are users 1-4 (groups 1-4); path 2's are 5-8.
List<H2hCupEntry> _entries({int pathOne = 4}) => [
  for (var g = 1; g <= pathOne; g++) _entry(g, 1, g),
  for (var g = 1; g <= 4; g++) _entry(4 + g, 2, g),
];

H2hCupStage _stage({
  required H2hCupRound round,
  required List<H2hCupPair> pairs,
  List<H2hCupResult> results = const <H2hCupResult>[],
  DateTime? lockedAt,
  int place = 1,
  DateTime? day,
}) => H2hCupStage(
  id: const H2hCupStageId('55555555-5555-4555-8555-555555555555'),
  monthStart: _november,
  step: H2hCupStep(place, round),
  attempt: 1,
  day: day ?? DateTime.utc(2026, 11, 22),
  fixtureCount: 8,
  lockedAt: lockedAt,
  pairs: pairs,
  results: results,
);

GetMyH2hCup _useCase(H2hCupState state, {DateTime? now}) => GetMyH2hCup(
  cups: _Cups(state),
  profiles: NamingProfiles(),
  clock: AtClock(now ?? _now),
);

Future<MyH2hCup> _read(
  H2hCupState state, {
  AuthenticatedUser who = const AuthenticatedUser(
    userId: UserId('00000000-0000-4000-9000-000000000001'),
    role: PlatformRole.user,
  ),
  DateTime? now,
}) async {
  final result = await _useCase(state, now: now)(principal: who);
  return (result as Ok<MyH2hCup>).value;
}

void main() {
  group('GetMyH2hCup', () {
    test('a qualifier sees his path, his pair and who he faces', () async {
      final cup = await _read(
        H2hCupState(
          entries: _entries(),
          stages: [
            _stage(
              round: H2hCupRound.semi,
              pairs: [
                H2hCupPair(slot: 1, home: userNo(1), away: userNo(3)),
                H2hCupPair(slot: 2, home: userNo(2), away: userNo(4)),
              ],
            ),
          ],
          titles: const <H2hCupTitle>[],
        ),
      );

      expect(cup.state, MyH2hCupState.qualified);
      expect(cup.monthStart, _november);
      expect(cup.place, 1);
      expect(cup.groupNumber, 1);
      expect(cup.entrants.map((p) => p.userId).toList(), [
        userNo(1),
        userNo(2),
        userNo(3),
        userNo(4),
      ]);
      expect(cup.entrants.where((p) => p.isMe).single.userId, userNo(1));
      expect(cup.stages, hasLength(2));

      final semi = cup.stages.first;
      expect(semi.round, H2hCupRound.semi);
      expect(semi.phase, MyH2hCupPhase.scheduled);
      expect(semi.day, DateTime.utc(2026, 11, 22));
      expect(semi.cupDay, 1);
      expect(semi.expectedDay, 20);
      expect(semi.pairs, hasLength(2));
      final mine = semi.pairs.singleWhere((p) => p.isMine);
      expect(mine.home.isMe, isTrue);
      expect(mine.away.userId, userNo(3));
      expect(mine.away.displayName, 'name ${userNo(3).value}');
      expect(mine.away.groupNumber, 3);
      expect(mine.decided, isFalse);

      final finale = cup.stages.last;
      expect(finale.round, H2hCupRound.finale);
      expect(finale.phase, MyH2hCupPhase.waiting);
      expect(finale.pairs, isEmpty);
      expect(finale.day, isNull);
      expect(finale.expectedDay, 21);
    });

    test('a frozen stage is live, a judged one is decided', () async {
      final live = await _read(
        H2hCupState(
          entries: _entries(),
          stages: [
            _stage(
              round: H2hCupRound.semi,
              pairs: [H2hCupPair(slot: 1, home: userNo(1), away: userNo(3))],
              lockedAt: DateTime.utc(2026, 11, 22, 9),
            ),
          ],
          titles: const <H2hCupTitle>[],
        ),
      );
      expect(live.stages.first.phase, MyH2hCupPhase.live);

      final decided = await _read(
        H2hCupState(
          entries: _entries(),
          stages: [
            _stage(
              round: H2hCupRound.semi,
              pairs: [H2hCupPair(slot: 1, home: userNo(1), away: userNo(3))],
              lockedAt: DateTime.utc(2026, 11, 22, 9),
              results: [
                H2hCupResult(
                  slot: 1,
                  winner: userNo(3),
                  outcome: H2hCupOutcome.points.wire,
                  home: const H2hCupSide(points: 7, exact: 1, predicted: 6),
                  away: const H2hCupSide(points: 9, exact: 0, predicted: 6),
                ),
              ],
            ),
          ],
          titles: const <H2hCupTitle>[],
        ),
      );
      final pair = decided.stages.first.pairs.single;
      expect(decided.stages.first.phase, MyH2hCupPhase.decided);
      expect(pair.decided, isTrue);
      expect(pair.result?.winner, userNo(3));
      expect(pair.result?.outcome, 'points');
      expect(pair.result?.home.points, 7);
      expect(pair.result?.away.points, 9);
    });

    test('three qualifiers: the one without a pair has a bye', () async {
      final cup = await _read(
        who: AuthenticatedUser(userId: userNo(3), role: PlatformRole.user),
        H2hCupState(
          entries: _entries(pathOne: 3),
          stages: [
            _stage(
              round: H2hCupRound.semi,
              pairs: [H2hCupPair(slot: 1, home: userNo(1), away: userNo(2))],
            ),
          ],
          titles: const <H2hCupTitle>[],
        ),
      );

      final semi = cup.stages.first;
      expect(semi.bye?.userId, userNo(3));
      expect(semi.bye?.isMe, isTrue);
      expect(semi.pairs.where((p) => p.isMine), isEmpty);
    });

    test('two qualifiers go straight to the final', () async {
      final cup = await _read(
        H2hCupState(
          entries: _entries(pathOne: 2),
          stages: const <H2hCupStage>[],
          titles: const <H2hCupTitle>[],
        ),
      );

      expect(cup.stages.first.phase, MyH2hCupPhase.skipped);
      expect(cup.stages.last.phase, MyH2hCupPhase.waiting);
    });

    test('a player outside the cup is not qualified', () async {
      final cup = await _read(
        who: AuthenticatedUser(userId: userNo(99), role: PlatformRole.user),
        H2hCupState(
          entries: _entries(),
          stages: const <H2hCupStage>[],
          titles: const <H2hCupTitle>[],
        ),
      );

      expect(cup.state, MyH2hCupState.notQualified);
      expect(cup.stages, isEmpty);
      expect(cup.entrants, isEmpty);
    });

    test('the title of his path arrives with the champion named', () async {
      final cup = await _read(
        H2hCupState(
          entries: _entries(),
          stages: [
            _stage(
              round: H2hCupRound.finale,
              pairs: [H2hCupPair(slot: 1, home: userNo(1), away: userNo(2))],
              results: [
                H2hCupResult(
                  slot: 1,
                  winner: userNo(1),
                  outcome: H2hCupOutcome.exact.wire,
                  home: const H2hCupSide(points: 5, exact: 2, predicted: 4),
                  away: const H2hCupSide(points: 5, exact: 1, predicted: 4),
                ),
              ],
            ),
          ],
          titles: [
            H2hCupTitle(
              place: 1,
              champion: userNo(1),
              runnerUp: userNo(2),
              how: 'final',
            ),
          ],
        ),
      );

      expect(cup.title?.how, 'final');
      expect(cup.title?.champion?.isMe, isTrue);
      expect(cup.title?.runnerUp?.userId, userNo(2));
    });

    test('the cup of last month is still shown while it is on', () async {
      final cup = await _read(
        H2hCupState(
          entries: _entries(),
          stages: const <H2hCupStage>[],
          titles: const <H2hCupTitle>[],
        ),
        now: DateTime.utc(2026, 12, 1, 9),
      );

      expect(cup.state, MyH2hCupState.qualified);
      expect(cup.monthStart, _november);
    });

    test('a finished cup goes off the screen after a few days', () async {
      final titles = [
        for (var place = 1; place <= 3; place++)
          H2hCupTitle(
            place: place,
            champion: userNo(place),
            runnerUp: null,
            how: 'final',
          ),
      ];
      final state = H2hCupState(
        entries: _entries(),
        stages: [
          _stage(
            round: H2hCupRound.finale,
            pairs: [H2hCupPair(slot: 1, home: userNo(1), away: userNo(2))],
            day: DateTime.utc(2026, 11, 22),
          ),
        ],
        titles: titles,
      );

      final fresh = await _read(state, now: DateTime.utc(2026, 11, 24, 9));
      expect(fresh.state, MyH2hCupState.qualified);

      final old = await _read(state, now: DateTime.utc(2026, 11, 28, 9));
      expect(old.state, MyH2hCupState.notQualified);
    });

    test('before the elite draw there is no cup', () async {
      final cup = await _read(
        H2hCupState(
          entries: _entries(),
          stages: const <H2hCupStage>[],
          titles: const <H2hCupTitle>[],
        ),
        now: DateTime.utc(2026, 10, 20, 9),
      );

      expect(cup.state, MyH2hCupState.notQualified);
    });
  });
}
