// NK310_04
import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

final _november = DateTime.utc(2026, 11);

/// 2026-11-22 12:00 UTC: 15:00 in Riyadh, the 22nd.
final _now = DateTime.utc(2026, 11, 22, 12);

const _stageOne = H2hCupStageId('55555555-5555-4555-8555-555555555551');
const _stageTwo = H2hCupStageId('55555555-5555-4555-8555-555555555552');

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

/// The owners' reader: it holds every pick and hands them all over.
final class _OwnerPicks implements H2hCupOwnerPickReader {
  _OwnerPicks(this.byStage, {this.failure});

  final Map<H2hCupStageId, List<H2hCupStageFixture>> byStage;
  final AppError? failure;
  int calls = 0;
  List<H2hCupStage>? lastStages;

  @override
  Future<Result<Map<H2hCupStageId, List<H2hCupStageFixture>>>>
  fixturesOfUnmasked({required List<H2hCupStage> stages}) async {
    calls++;
    lastStages = stages;
    final error = failure;
    if (error != null) {
      return Result.err(error);
    }
    return Result.ok(byStage);
  }
}

/// A player's reader that, unlike the real adapter, leaks every pick.
final class _LeakyPlayerPicks implements H2hCupPickReader {
  _LeakyPlayerPicks(this.byStage);

  final Map<H2hCupStageId, List<H2hCupStageFixture>> byStage;

  @override
  Future<Result<Map<H2hCupStageId, List<H2hCupStageFixture>>>> fixturesOf({
    required List<H2hCupStage> stages,
    required UserId reader,
    required DateTime nowUtc,
  }) async => Result.ok(byStage);
}

H2hCupEntry _entry(int user, int place, int group) => H2hCupEntry(
  userId: userNo(user),
  place: place,
  groupNumber: group,
  leaguePoints: 40,
  pointsFor: 100,
  exactCount: 10,
);

/// Path 1's qualifiers are users 1-4 (groups 1-4); path 2's are 5-8.
List<H2hCupEntry> _entries() => [
  for (var g = 1; g <= 4; g++) _entry(g, 1, g),
  for (var g = 1; g <= 4; g++) _entry(4 + g, 2, g),
];

H2hCupStage _stage({
  required H2hCupStageId id,
  required List<H2hCupPair> pairs,
  int place = 1,
}) => H2hCupStage(
  id: id,
  monthStart: _november,
  step: H2hCupStep(place, H2hCupRound.semi),
  attempt: 1,
  day: DateTime.utc(2026, 11, 22),
  fixtureCount: 4,
  lockedAt: DateTime.utc(2026, 11, 22, 9),
  pairs: pairs,
  results: const <H2hCupResult>[],
);

H2hCupStage _pathOneSemi() => _stage(
  id: _stageOne,
  pairs: [
    H2hCupPair(slot: 1, home: userNo(1), away: userNo(3)),
    H2hCupPair(slot: 2, home: userNo(2), away: userNo(4)),
  ],
);

H2hCupStage _pathTwoSemi() => _stage(
  id: _stageTwo,
  place: 2,
  pairs: [
    H2hCupPair(slot: 1, home: userNo(5), away: userNo(7)),
    H2hCupPair(slot: 2, home: userNo(6), away: userNo(8)),
  ],
);

H2hCupState _state(List<H2hCupStage> stages) => H2hCupState(
  entries: _entries(),
  stages: stages,
  titles: const <H2hCupTitle>[],
);

H2hFixturePick _pick(int home, int away) => H2hFixturePick(
  homeGoals: home,
  awayGoals: away,
  isDouble: false,
  points: null,
  exact: false,
);

Map<UserId, H2hFixturePick> _everyone() => {
  for (var n = 1; n <= 8; n++) userNo(n): _pick(n, 0),
};

H2hCupStageFixture _fixture(
  String id, {
  DateTime? kickoffAt,
  bool counted = true,
  int? homeGoals,
  int? awayGoals,
  Map<UserId, H2hFixturePick>? picks,
}) => H2hCupStageFixture(
  fixtureId: id,
  homeTeam: 'Home $id',
  awayTeam: 'Away $id',
  homeTeamId: null,
  awayTeamId: null,
  kickoffAt: kickoffAt,
  counted: counted,
  homeGoals: homeGoals,
  awayGoals: awayGoals,
  picks: picks ?? _everyone(),
);

DateTime _in(Duration d) => _now.add(d);

Future<Result<H2hCupBoard>> _readAs(
  AuthenticatedUser who,
  H2hCupState state,
  _OwnerPicks picks, {
  DateTime? month,
}) => GetOwnerH2hCupPicks(
  cups: _Cups(state),
  picks: picks,
  profiles: NamingProfiles(),
  clock: AtClock(_now),
)(principal: who, month: month);

Future<H2hCupBoard> _read(
  H2hCupState state,
  _OwnerPicks picks, {
  DateTime? month,
}) async {
  final result = await _readAs(admin, state, picks, month: month);
  return (result as Ok<H2hCupBoard>).value;
}

H2hCupBoardPathView _path(H2hCupBoard board, int place) =>
    board.paths.singleWhere((p) => p.place == place);

List<H2hCupBoardFixtureView> _fixtures(H2hCupBoard board, {int pair = 0}) =>
    _path(board, 1).stages.first.pairs[pair].fixtures;

_OwnerPicks _onePathOne(List<H2hCupStageFixture> fixtures) =>
    _OwnerPicks({_stageOne: fixtures});

void main() {
  group('GetOwnerH2hCupPicks: nothing is withheld', () {
    test('before kickoff both picks show on both sides', () async {
      final board = await _read(
        _state([_pathOneSemi()]),
        _onePathOne([_fixture('f1', kickoffAt: _in(const Duration(hours: 2)))]),
      );

      final fixture = _fixtures(board).single;
      expect(fixture.state, H2hFixtureState.notStarted);
      expect(fixture.homeSide.revealed, isTrue);
      expect(fixture.homeSide.pick?.homeGoals, 1);
      expect(fixture.awaySide.revealed, isTrue);
      expect(fixture.awaySide.pick?.homeGoals, 3);
    });

    test('a fixture with no kickoff shows them too', () async {
      final board = await _read(
        _state([_pathOneSemi()]),
        _onePathOne([_fixture('f1')]),
      );

      final fixture = _fixtures(board).single;
      expect(fixture.state, H2hFixtureState.notStarted);
      expect(fixture.homeSide.pick?.homeGoals, 1);
      expect(fixture.awaySide.pick?.homeGoals, 3);
    });

    test('a player who did not predict reads as no pick', () async {
      final board = await _read(
        _state([_pathOneSemi()]),
        _onePathOne([
          _fixture(
            'f1',
            kickoffAt: _in(const Duration(hours: 2)),
            picks: {userNo(1): _pick(2, 2)},
          ),
        ]),
      );

      final fixture = _fixtures(board).single;
      expect(fixture.homeSide.pick?.awayGoals, 2);
      expect(fixture.awaySide.revealed, isTrue);
      expect(fixture.awaySide.pick, isNull);
    });

    test(
      'every fixture keeps its state: not started, live, finished, void',
      () async {
        final board = await _read(
          _state([_pathOneSemi()]),
          _onePathOne([
            _fixture('a', kickoffAt: _in(const Duration(hours: 1))),
            _fixture('b', kickoffAt: _in(const Duration(minutes: -30))),
            _fixture(
              'c',
              kickoffAt: _in(const Duration(hours: -3)),
              homeGoals: 2,
              awayGoals: 1,
            ),
            _fixture(
              'd',
              kickoffAt: _in(const Duration(hours: 4)),
              counted: false,
            ),
          ]),
        );

        final byId = {for (final f in _fixtures(board)) f.fixtureId: f.state};
        expect(byId, {
          'a': H2hFixtureState.notStarted,
          'b': H2hFixtureState.live,
          'c': H2hFixtureState.finished,
          'd': H2hFixtureState.voided,
        });
      },
    );

    test('every path of the month is on the board, none of them his', () async {
      final board = await _read(
        _state([_pathOneSemi(), _pathTwoSemi()]),
        _OwnerPicks({
          _stageOne: <H2hCupStageFixture>[],
          _stageTwo: [_fixture('f2', kickoffAt: _in(const Duration(hours: 2)))],
        }),
      );

      expect(board.paths.map((p) => p.place), [1, 2]);
      final two = _path(board, 2).stages.first.pairs.first.fixtures.single;
      expect(two.homeSide.pick?.homeGoals, 5);
      expect(two.awaySide.pick?.homeGoals, 7);
      for (final path in board.paths) {
        for (final pair in path.stages.first.pairs) {
          expect(pair.home.isMe, isFalse);
          expect(pair.away.isMe, isFalse);
        }
      }
    });
  });

  group('GetOwnerH2hCupPicks: the month', () {
    test('no month asked: the latest one that holds a cup', () async {
      final board = await _read(
        _state([_pathOneSemi()]),
        _onePathOne(<H2hCupStageFixture>[]),
      );

      expect(board.monthStart, _november);
      expect(board.paths.map((p) => p.place), [1, 2]);
    });

    test('the month asked is the one read', () async {
      final board = await _read(
        _state([_pathOneSemi()]),
        _onePathOne(<H2hCupStageFixture>[]),
        month: DateTime.utc(2026, 11, 17),
      );

      expect(board.monthStart, _november);
    });

    test('a month with no cup is an empty board and nothing is read', () async {
      final picks = _onePathOne(<H2hCupStageFixture>[]);
      final board = await _read(
        _state([_pathOneSemi()]),
        picks,
        month: DateTime.utc(2026, 10),
      );

      expect(board.monthStart, isNull);
      expect(board.paths, isEmpty);
      expect(picks.calls, 0);
    });

    test('no cup anywhere: an empty board and nothing is read', () async {
      final picks = _onePathOne(<H2hCupStageFixture>[]);
      final board = await _read(H2hCupState.empty, picks);

      expect(board.monthStart, isNull);
      expect(board.paths, isEmpty);
      expect(picks.calls, 0);
    });
  });

  group('GetOwnerH2hCupPicks: the locks and the reading', () {
    test('a player is refused and nothing is read', () async {
      final picks = _onePathOne(<H2hCupStageFixture>[]);
      final result = await _readAs(player, _state([_pathOneSemi()]), picks);

      expect(result, isA<Err<H2hCupBoard>>());
      expect((result as Err<H2hCupBoard>).error.kind, ErrorKind.authorization);
      expect(picks.calls, 0);
    });

    test('the reader is asked once, for the stages in order', () async {
      final picks = _OwnerPicks({
        _stageOne: <H2hCupStageFixture>[],
        _stageTwo: <H2hCupStageFixture>[],
      });
      await _read(_state([_pathOneSemi(), _pathTwoSemi()]), picks);

      expect(picks.calls, 1);
      expect(picks.lastStages?.map((s) => s.id), [_stageOne, _stageTwo]);
    });

    test('a failure of the reader is returned as it came', () async {
      final result = await _readAs(
        admin,
        _state([_pathOneSemi()]),
        _OwnerPicks(
          const <H2hCupStageId, List<H2hCupStageFixture>>{},
          failure: const AppError.transient('db.down', 'down'),
        ),
      );

      expect(result, isA<Err<H2hCupBoard>>());
      final error = (result as Err<H2hCupBoard>).error;
      expect(error.kind, ErrorKind.transient);
      expect(error.code, 'db.down');
    });
  });

  group('the player board over the same data', () {
    test('still withholds what the owners see', () async {
      final fixtures = <H2hCupStageFixture>[
        _fixture('f1', kickoffAt: _in(const Duration(hours: 2))),
      ];
      final result =
          await GetH2hCupBoard(
            cups: _Cups(_state([_pathOneSemi()])),
            picks: _LeakyPlayerPicks({_stageOne: fixtures}),
            profiles: NamingProfiles(),
            clock: AtClock(_now),
          )(
            principal: AuthenticatedUser(
              userId: userNo(1),
              role: PlatformRole.user,
            ),
          );

      final board = (result as Ok<H2hCupBoard>).value;
      final fixture = _fixtures(board).single;
      expect(fixture.homeSide.revealed, isTrue);
      expect(fixture.homeSide.pick?.homeGoals, 1);
      expect(fixture.awaySide.revealed, isFalse);
      expect(fixture.awaySide.pick, isNull);
    });
  });
}
