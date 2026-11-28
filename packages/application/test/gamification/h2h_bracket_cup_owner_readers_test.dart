// NK361_01
/// The readers of the Elite Cup that are not the board read the bracket of
/// December 2026 (NK361_01, owner decision 2026-11-28): one path, the place 1,
/// holding the sixteen qualifiers, whose stages are the four rounds of the
/// bracket in order. `GetMyH2hCup` (`GET /me/h2h-cup`) and `GetOwnerH2hCup`
/// (the owners' page) read three paths of a semi-final and a final before it;
/// the bracket's `quarter` and `round16` stages were never found by them.
library;

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

final _december = DateTime.utc(2026, 12);

/// 2026-12-22 12:00 UTC: 15:00 in Riyadh, the 22nd.
final _now = DateTime.utc(2026, 12, 22, 12);

/// The Elite Cup of December as stored; every other month holds none.
final class _Cups implements H2hCupStore {
  _Cups(this.state);

  final H2hCupState state;

  @override
  Future<Result<H2hCupState>> stateOf(DateTime monthStart) async =>
      Result.ok(monthStart == _december ? state : H2hCupState.empty);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected ${invocation.memberName}');
}

H2hCupEntry _entry(int n, int place, int group) => H2hCupEntry(
  userId: userNo(n),
  place: place,
  groupNumber: group,
  leaguePoints: 40,
  pointsFor: 100,
  exactCount: 10,
);

/// The sixteen: the first place of each of eight groups is user g, the
/// second place is user g + 10.
List<H2hCupEntry> _sixteen() => [
  for (var g = 1; g <= 8; g++) ...[_entry(g, 1, g), _entry(g + 10, 2, g)],
];

H2hCupStageId _id(int n) =>
    H2hCupStageId('44444444-4444-4444-8444-${n.toString().padLeft(12, '0')}');

H2hCupPair _pair(int slot, int home, int away) =>
    H2hCupPair(slot: slot, home: userNo(home), away: userNo(away));

H2hCupResult _won(int slot, int winner) => H2hCupResult(
  slot: slot,
  winner: userNo(winner),
  outcome: 'points',
  home: H2hCupSide.absent,
  away: H2hCupSide.absent,
);

/// The round of sixteen: user s against a second place of another group.
List<H2hCupPair> _roundOfSixteen() => [
  for (var s = 1; s <= 8; s++) _pair(s, s, s == 8 ? 11 : s + 11),
];

/// Eight pairs decided, the first side of each winning.
List<H2hCupResult> _firstsWon() => [for (var s = 1; s <= 8; s++) _won(s, s)];

/// The quarter-finals of the winners 1 to 8.
List<H2hCupPair> _quarters() => [
  for (var s = 1; s <= 4; s++) _pair(s, 2 * s - 1, 2 * s),
];

H2hCupStage _stage(
  H2hCupRound round,
  List<H2hCupPair> pairs, {
  List<H2hCupResult> results = const <H2hCupResult>[],
  bool locked = true,
  int day = 20,
}) => H2hCupStage(
  id: _id(round.index + 1),
  monthStart: _december,
  step: H2hCupStep(1, round, bracket: true),
  attempt: 1,
  day: DateTime.utc(2026, 12, day),
  fixtureCount: 8,
  lockedAt: locked ? DateTime.utc(2026, 12, day, 9) : null,
  pairs: pairs,
  results: results,
);

H2hCupState _cup(
  List<H2hCupStage> stages, {
  List<H2hCupEntry>? entries,
  List<H2hCupTitle> titles = const <H2hCupTitle>[],
}) =>
    H2hCupState(entries: entries ?? _sixteen(), stages: stages, titles: titles);

/// The cup of a player of the bracket, or of a watcher.
Future<MyH2hCup> _mine(H2hCupState state, {required int user}) async {
  final result =
      await GetMyH2hCup(
        cups: _Cups(state),
        profiles: NamingProfiles(),
        clock: AtClock(_now),
      )(
        principal: AuthenticatedUser(
          userId: userNo(user),
          role: PlatformRole.user,
        ),
      );
  expect(result, isA<Ok<MyH2hCup>>(), reason: '$result');
  return (result as Ok<MyH2hCup>).value;
}

/// The owners' cup of the latest month holding one.
Future<OwnerH2hCup> _owners(H2hCupState state) async {
  final result = await GetOwnerH2hCup(
    cups: _Cups(state),
    rounds: FakeH2hRoundStore(),
    profiles: NamingProfiles(),
    clock: AtClock(_now),
  )(principal: admin);
  expect(result, isA<Ok<OwnerH2hCup>>(), reason: '$result');
  return (result as Ok<OwnerH2hCup>).value;
}

List<H2hCupRound> _rounds(List<MyH2hCupStage> stages) => [
  for (final stage in stages) stage.round,
];

List<MyH2hCupPhase> _phases(List<MyH2hCupStage> stages) => [
  for (final stage in stages) stage.phase,
];

const _fourRounds = <H2hCupRound>[
  H2hCupRound.round16,
  H2hCupRound.quarter,
  H2hCupRound.semi,
  H2hCupRound.finale,
];

/// Fifteen qualifiers (user 18 missing): seven pairs in the round of sixteen,
/// user 8 without a pair.
H2hCupState _fifteen() => _cup(
  [
    _stage(
      H2hCupRound.round16,
      [for (var s = 1; s <= 7; s++) _pair(s, s, s + 10)],
      results: [for (var s = 1; s <= 7; s++) _won(s, s)],
    ),
    _stage(H2hCupRound.quarter, _quarters(), day: 21),
  ],
  entries: [
    for (final entry in _sixteen())
      if (entry.userId != userNo(18)) entry,
  ],
);

/// A bracket of two: only the final was ever played, and it is decided.
H2hCupState _crownedFinalOnly() => _cup(
  [
    _stage(H2hCupRound.finale, [_pair(1, 1, 11)], results: [_won(1, 1)]),
  ],
  entries: [_entry(1, 1, 1), _entry(11, 2, 1)],
  titles: [
    H2hCupTitle(
      place: 1,
      champion: userNo(1),
      runnerUp: userNo(11),
      how: 'final',
    ),
  ],
);

void main() {
  group('GetMyH2hCup: the bracket of December 2026', () {
    test('a second place reads the one path with the four rounds', () async {
      final cup = await _mine(
        _cup([
          _stage(H2hCupRound.round16, _roundOfSixteen(), results: _firstsWon()),
          _stage(H2hCupRound.quarter, _quarters(), day: 21),
        ]),
        user: 11,
      );

      expect(cup.state, MyH2hCupState.qualified);
      expect(cup.monthStart, _december);
      expect(cup.place, 1);
      expect(cup.groupNumber, 1);
      expect(cup.entrants, hasLength(16));
      expect(_rounds(cup.stages), _fourRounds);
      expect([for (final stage in cup.stages) stage.cupDay], [1, 2, 3, 4]);
      expect(_phases(cup.stages), [
        MyH2hCupPhase.decided,
        MyH2hCupPhase.live,
        MyH2hCupPhase.waiting,
        MyH2hCupPhase.waiting,
      ]);
      expect(cup.stages.first.pairs, hasLength(8));
      expect(cup.stages[1].pairs, hasLength(4));
      expect(cup.title, isNull);
      final mine = [
        for (final pair in cup.stages.first.pairs)
          if (pair.isMine) pair.slot,
      ];
      expect(mine, [8]);
    });

    test('a player outside the bracket watches the same path', () async {
      final cup = await _mine(
        _cup([_stage(H2hCupRound.round16, _roundOfSixteen())]),
        user: 99,
      );

      expect(cup.state, MyH2hCupState.spectator);
      expect(cup.place, 1);
      expect(cup.groupNumber, 0);
      expect(cup.entrants, hasLength(16));
      expect(_rounds(cup.stages), _fourRounds);
      expect(cup.stages.first.pairs, hasLength(8));
    });

    test('of fifteen players the one without a pair goes on', () async {
      final cup = await _mine(_fifteen(), user: 8);

      expect(cup.stages[0].pairs, hasLength(7));
      expect(cup.stages[0].bye?.userId, userNo(8));
      expect(cup.stages[0].bye?.isMe, isTrue);
      expect(cup.stages[1].pairs, hasLength(4));
      expect(cup.stages[1].bye, isNull);
    });

    test('rounds never played once the title is decided are skipped', () async {
      final cup = await _mine(_crownedFinalOnly(), user: 1);

      expect(_phases(cup.stages), [
        MyH2hCupPhase.skipped,
        MyH2hCupPhase.skipped,
        MyH2hCupPhase.skipped,
        MyH2hCupPhase.decided,
      ]);
      expect(cup.title?.champion?.userId, userNo(1));
      expect(cup.title?.champion?.isMe, isTrue);
      expect(cup.title?.runnerUp?.userId, userNo(11));
    });
  });

  group('GetOwnerH2hCup: the bracket of December 2026', () {
    test('the owners read one path of sixteen with four rounds', () async {
      final cup = await _owners(
        _cup([
          _stage(H2hCupRound.round16, _roundOfSixteen(), results: _firstsWon()),
          _stage(H2hCupRound.quarter, _quarters(), day: 21),
        ]),
      );

      expect(cup.monthStart, _december);
      expect(cup.months.last.monthStart, _december);
      expect(cup.months.last.hasCup, isTrue);
      final path = cup.paths.single;
      expect(path.place, 1);
      expect(path.entrants, hasLength(16));
      expect(path.entrants.first.displayName, 'name ${userNo(1).value}');
      expect(_rounds(path.stages), _fourRounds);
      expect(_phases(path.stages), [
        MyH2hCupPhase.decided,
        MyH2hCupPhase.live,
        MyH2hCupPhase.waiting,
        MyH2hCupPhase.waiting,
      ]);
      expect(path.stages.first.pairs, hasLength(8));
      expect(path.stages.first.pairs.first.result?.winner, userNo(1));
      expect(path.stages.first.pairs.every((p) => !p.isMine), isTrue);
      expect(path.title, isNull);
    });

    test('of fifteen players the one without a pair goes on', () async {
      final path = (await _owners(_fifteen())).paths.single;

      expect(path.entrants, hasLength(15));
      expect(path.stages[0].bye?.userId, userNo(8));
      expect(path.stages[1].bye, isNull);
    });

    test('a crowned bracket names its champion', () async {
      final path = (await _owners(_crownedFinalOnly())).paths.single;

      expect(_phases(path.stages), [
        MyH2hCupPhase.skipped,
        MyH2hCupPhase.skipped,
        MyH2hCupPhase.skipped,
        MyH2hCupPhase.decided,
      ]);
      expect(path.title?.how, 'final');
      expect(path.title?.champion?.userId, userNo(1));
      expect(path.title?.runnerUp?.userId, userNo(11));
    });
  });
}
