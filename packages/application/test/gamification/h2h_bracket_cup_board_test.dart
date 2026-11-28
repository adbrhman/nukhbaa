// NK360_01
/// The Elite Cup board reads the bracket of December 2026 (NK360_01, owner
/// decision 2026-11-28): one path, the place 1, holding the sixteen
/// qualifiers, whose stages are the four rounds of the bracket in order. Up
/// to November 2026 the board keeps its three paths.
library;

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

final _november = DateTime.utc(2026, 11);
final _december = DateTime.utc(2026, 12);

/// 2026-12-22 12:00 UTC: 15:00 in Riyadh, the 22nd.
final _now = DateTime.utc(2026, 12, 22, 12);

/// User 1, a first place of group 1.
final _me = AuthenticatedUser(userId: userNo(1), role: PlatformRole.user);

/// The Elite Cups as stored, by month: only their state is asked.
final class _Cups implements H2hCupStore {
  _Cups(this.byMonth);

  final Map<DateTime, H2hCupState> byMonth;

  @override
  Future<Result<H2hCupState>> stateOf(DateTime monthStart) async =>
      Result.ok(byMonth[monthStart] ?? H2hCupState.empty);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected ${invocation.memberName}');
}

/// A reader of picks with nothing to read: the board's rounds are what this
/// test looks at.
final class _NoPicks implements H2hCupPickReader {
  @override
  Future<Result<Map<H2hCupStageId, List<H2hCupStageFixture>>>> fixturesOf({
    required List<H2hCupStage> stages,
    required UserId reader,
    required DateTime nowUtc,
  }) async => const Result.ok(<H2hCupStageId, List<H2hCupStageFixture>>{});
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
    H2hCupStageId('33333333-3333-4333-8333-${n.toString().padLeft(12, '0')}');

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

Future<H2hCupBoard> _read(
  Map<DateTime, H2hCupState> cups, {
  DateTime? now,
  AuthenticatedUser? who,
}) async {
  final result = await GetH2hCupBoard(
    cups: _Cups(cups),
    picks: _NoPicks(),
    profiles: NamingProfiles(),
    clock: AtClock(now ?? _now),
  )(principal: who ?? _me);
  expect(result, isA<Ok<H2hCupBoard>>(), reason: '$result');
  return (result as Ok<H2hCupBoard>).value;
}

List<MyH2hCupPhase> _phases(H2hCupBoardPathView path) => [
  for (final stage in path.stages) stage.phase,
];

void main() {
  group('GetH2hCupBoard: the bracket of December 2026', () {
    test('one path holds the four rounds, the first one scheduled', () async {
      final board = await _read({
        _december: _cup([
          _stage(H2hCupRound.round16, _roundOfSixteen(), locked: false),
        ]),
      });

      expect(board.monthStart, _december);
      final path = board.paths.single;
      expect(path.place, 1);
      expect(
        [for (final stage in path.stages) stage.round],
        [
          H2hCupRound.round16,
          H2hCupRound.quarter,
          H2hCupRound.semi,
          H2hCupRound.finale,
        ],
      );
      expect([for (final stage in path.stages) stage.cupDay], [1, 2, 3, 4]);
      expect(_phases(path), [
        MyH2hCupPhase.scheduled,
        MyH2hCupPhase.waiting,
        MyH2hCupPhase.waiting,
        MyH2hCupPhase.waiting,
      ]);
      expect(path.stages.first.pairs, hasLength(8));
      expect(path.stages.first.bye, isNull);
      expect(path.title, isNull);
    });

    test('names, groups and the caller come with the sixteen', () async {
      final board = await _read({
        _december: _cup([_stage(H2hCupRound.round16, _roundOfSixteen())]),
      });

      final pair = board.paths.single.stages.first.pairs.first;
      expect(pair.home.userId, userNo(1));
      expect(pair.home.groupNumber, 1);
      expect(pair.home.isMe, isTrue);
      expect(pair.away.userId, userNo(12));
      expect(pair.away.groupNumber, 2);
      expect(pair.away.isMe, isFalse);
      expect(pair.away.displayName, 'name ${userNo(12).value}');
    });

    test('the quarter-finals follow a decided round of sixteen', () async {
      final board = await _read({
        _december: _cup([
          _stage(H2hCupRound.round16, _roundOfSixteen(), results: _firstsWon()),
          _stage(H2hCupRound.quarter, _quarters(), day: 21),
        ]),
      });

      final path = board.paths.single;
      expect(_phases(path), [
        MyH2hCupPhase.decided,
        MyH2hCupPhase.live,
        MyH2hCupPhase.waiting,
        MyH2hCupPhase.waiting,
      ]);
      expect(path.stages.first.pairs.first.decided, isTrue);
      expect(path.stages.first.pairs.first.winner, userNo(1));
      expect(path.stages[1].pairs, hasLength(4));
      expect(path.stages[1].pairs.first.decided, isFalse);
    });

    test('of fifteen players one has no pair and goes on', () async {
      final fifteen = [
        for (final entry in _sixteen())
          if (entry.userId != userNo(18)) entry,
      ];
      final board = await _read({
        _december: _cup([
          _stage(
            H2hCupRound.round16,
            [for (var s = 1; s <= 7; s++) _pair(s, s, s + 10)],
            results: [for (var s = 1; s <= 7; s++) _won(s, s)],
          ),
          _stage(H2hCupRound.quarter, _quarters(), day: 21),
        ], entries: fifteen),
      });

      final stages = board.paths.single.stages;
      expect(stages[0].pairs, hasLength(7));
      expect(stages[0].bye?.userId, userNo(8));
      expect(stages[1].pairs, hasLength(4));
      expect(stages[1].bye, isNull);
    });

    test('a crowned bracket names its champion, every round decided', () async {
      final board = await _read({
        _december: _cup(
          [
            _stage(
              H2hCupRound.round16,
              _roundOfSixteen(),
              results: _firstsWon(),
            ),
            _stage(
              H2hCupRound.quarter,
              _quarters(),
              results: [for (var s = 1; s <= 4; s++) _won(s, 2 * s - 1)],
              day: 21,
            ),
            _stage(
              H2hCupRound.semi,
              [_pair(1, 1, 3), _pair(2, 5, 7)],
              results: [_won(1, 1), _won(2, 5)],
              day: 22,
            ),
            _stage(
              H2hCupRound.finale,
              [_pair(1, 1, 5)],
              results: [_won(1, 1)],
              day: 23,
            ),
          ],
          titles: [
            H2hCupTitle(
              place: 1,
              champion: userNo(1),
              runnerUp: userNo(5),
              how: 'final',
            ),
          ],
        ),
      }, now: DateTime.utc(2026, 12, 24, 12));

      final path = board.paths.single;
      expect(_phases(path), everyElement(MyH2hCupPhase.decided));
      expect(path.title?.how, 'final');
      expect(path.title?.champion?.userId, userNo(1));
      expect(path.title?.runnerUp?.userId, userNo(5));
    });

    test('rounds never played once the title is decided are skipped', () async {
      final board = await _read({
        _december: _cup(
          [
            _stage(
              H2hCupRound.finale,
              [_pair(1, 1, 11)],
              results: [_won(1, 1)],
            ),
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
        ),
      });

      expect(_phases(board.paths.single), [
        MyH2hCupPhase.skipped,
        MyH2hCupPhase.skipped,
        MyH2hCupPhase.skipped,
        MyH2hCupPhase.decided,
      ]);
    });

    test('a player outside the cup watches the same bracket', () async {
      final board = await _read({
        _december: _cup([_stage(H2hCupRound.round16, _roundOfSixteen())]),
      }, who: AuthenticatedUser(userId: userNo(99), role: PlatformRole.user));

      final path = board.paths.single;
      expect(path.place, 1);
      expect(path.stages.first.pairs, hasLength(8));
      expect(path.stages.first.pairs.first.home.isMe, isFalse);
    });
  });

  group('GetH2hCupBoard: November 2026 keeps its three paths', () {
    test('two paths, each a semi-final then a final', () async {
      final november = H2hCupState(
        entries: [
          for (var g = 1; g <= 4; g++) _entry(g, 1, g),
          for (var g = 1; g <= 4; g++) _entry(4 + g, 2, g),
        ],
        stages: [
          H2hCupStage(
            id: _id(9),
            monthStart: _november,
            step: const H2hCupStep(1, H2hCupRound.semi),
            attempt: 1,
            day: DateTime.utc(2026, 11, 22),
            fixtureCount: 4,
            lockedAt: DateTime.utc(2026, 11, 22, 9),
            pairs: [_pair(1, 1, 3), _pair(2, 2, 4)],
            results: const <H2hCupResult>[],
          ),
        ],
        titles: const <H2hCupTitle>[],
      );
      final board = await _read({
        _november: november,
      }, now: DateTime.utc(2026, 11, 22, 12));

      expect([for (final path in board.paths) path.place], [1, 2]);
      for (final path in board.paths) {
        expect(
          [for (final stage in path.stages) stage.round],
          [H2hCupRound.semi, H2hCupRound.finale],
        );
      }
      expect(board.paths.first.stages.first.phase, MyH2hCupPhase.live);
      expect(board.paths.first.stages.first.pairs, hasLength(2));
    });
  });
}
