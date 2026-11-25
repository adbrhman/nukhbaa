// NK309_05
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

/// The caller of most tests: user 1, a qualifier of path 1.
final _me = AuthenticatedUser(userId: userNo(1), role: PlatformRole.user);

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

/// A reader that hands over every pick it holds, whatever the kickoff: the
/// use-case must withhold what the adapter would have withheld already.
final class _Picks implements H2hCupPickReader {
  _Picks(this.byStage, {this.failure});

  final Map<H2hCupStageId, List<H2hCupStageFixture>> byStage;
  final AppError? failure;
  int calls = 0;
  List<H2hCupStage>? lastStages;
  UserId? lastReader;
  DateTime? lastNow;

  @override
  Future<Result<Map<H2hCupStageId, List<H2hCupStageFixture>>>> fixturesOf({
    required List<H2hCupStage> stages,
    required UserId reader,
    required DateTime nowUtc,
  }) async {
    calls++;
    lastStages = stages;
    lastReader = reader;
    lastNow = nowUtc;
    final error = failure;
    if (error != null) {
      return Result.err(error);
    }
    return Result.ok(byStage);
  }
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
List<H2hCupEntry> _entries({int pathOne = 4}) => [
  for (var g = 1; g <= pathOne; g++) _entry(g, 1, g),
  for (var g = 1; g <= 4; g++) _entry(4 + g, 2, g),
];

H2hCupStage _stage({
  required H2hCupStageId id,
  required H2hCupRound round,
  required List<H2hCupPair> pairs,
  List<H2hCupResult> results = const <H2hCupResult>[],
  int place = 1,
}) => H2hCupStage(
  id: id,
  monthStart: _november,
  step: H2hCupStep(place, round),
  attempt: 1,
  day: DateTime.utc(2026, 11, 22),
  fixtureCount: 4,
  lockedAt: DateTime.utc(2026, 11, 22, 9),
  pairs: pairs,
  results: results,
);

/// Path 1's semi-finals: 1 against 3 and 2 against 4.
H2hCupStage _pathOneSemi({
  List<H2hCupResult> results = const <H2hCupResult>[],
}) => _stage(
  id: _stageOne,
  round: H2hCupRound.semi,
  results: results,
  pairs: [
    H2hCupPair(slot: 1, home: userNo(1), away: userNo(3)),
    H2hCupPair(slot: 2, home: userNo(2), away: userNo(4)),
  ],
);

/// Path 2's semi-finals: 5 against 7 and 6 against 8.
H2hCupStage _pathTwoSemi() => _stage(
  id: _stageTwo,
  round: H2hCupRound.semi,
  place: 2,
  pairs: [
    H2hCupPair(slot: 1, home: userNo(5), away: userNo(7)),
    H2hCupPair(slot: 2, home: userNo(6), away: userNo(8)),
  ],
);

H2hCupState _state(List<H2hCupStage> stages, {int pathOne = 4}) => H2hCupState(
  entries: _entries(pathOne: pathOne),
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

/// Everybody's pick of the stage's players, as a leaky reader holds them.
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

// NK330_04
/// A pick with the points a stored score gave it (null while none is stored).
H2hFixturePick _scored(int home, int away, int? points) => H2hFixturePick(
  homeGoals: home,
  awayGoals: away,
  isDouble: false,
  points: points,
  exact: false,
);

Future<H2hCupBoard> _read(
  H2hCupState state,
  _Picks picks, {
  AuthenticatedUser? who,
}) async {
  final result = await GetH2hCupBoard(
    cups: _Cups(state),
    picks: picks,
    profiles: NamingProfiles(),
    clock: AtClock(_now),
  )(principal: who ?? _me);
  return (result as Ok<H2hCupBoard>).value;
}

H2hCupBoardPathView _path(H2hCupBoard board, int place) =>
    board.paths.singleWhere((p) => p.place == place);

/// The fixtures of path 1's semi-finals, pair [pair] (0 or 1).
List<H2hCupBoardFixtureView> _fixtures(H2hCupBoard board, {int pair = 0}) =>
    _path(board, 1).stages.first.pairs[pair].fixtures;

void main() {
  group('GetH2hCupBoard: what a side may show', () {
    test('before kickoff: his own pick, the opponent withheld', () async {
      final board = await _read(
        _state([_pathOneSemi()]),
        _Picks({
          _stageOne: [_fixture('f1', kickoffAt: _in(const Duration(hours: 2)))],
        }),
      );

      final mine = _fixtures(board).single;
      expect(mine.state, H2hFixtureState.notStarted);
      expect(mine.homeSide.revealed, isTrue);
      expect(mine.homeSide.pick?.homeGoals, 1);
      expect(mine.awaySide.revealed, isFalse);
      expect(mine.awaySide.pick, isNull);

      final other = _fixtures(board, pair: 1).single;
      expect(other.homeSide.revealed, isFalse);
      expect(other.homeSide.pick, isNull);
      expect(other.awaySide.revealed, isFalse);
      expect(other.awaySide.pick, isNull);
    });

    test('a withheld side is the same whether he predicted or not', () async {
      final kickoff = _in(const Duration(hours: 2));
      final predicted = await _read(
        _state([_pathOneSemi()]),
        _Picks({
          _stageOne: [_fixture('f1', kickoffAt: kickoff)],
        }),
      );
      final silent = await _read(
        _state([_pathOneSemi()]),
        _Picks({
          _stageOne: [
            _fixture('f1', kickoffAt: kickoff, picks: {userNo(1): _pick(2, 2)}),
          ],
        }),
      );

      final a = _fixtures(predicted).single.awaySide;
      final b = _fixtures(silent).single.awaySide;
      expect(a.revealed, b.revealed);
      expect(a.revealed, isFalse);
      expect(a.pick, isNull);
      expect(b.pick, isNull);
    });

    test('his own side shows no pick when he made none', () async {
      final board = await _read(
        _state([_pathOneSemi()]),
        _Picks({
          _stageOne: [
            _fixture(
              'f1',
              kickoffAt: _in(const Duration(hours: 2)),
              picks: {userNo(3): _pick(1, 1)},
            ),
          ],
        }),
      );

      final fixture = _fixtures(board).single;
      expect(fixture.homeSide.revealed, isTrue);
      expect(fixture.homeSide.pick, isNull);
      expect(fixture.awaySide.revealed, isFalse);
    });

    test('at the instant of kickoff both picks show, a second before '
        'they do not', () async {
      final board = await _read(
        _state([_pathOneSemi()]),
        _Picks({
          _stageOne: [
            _fixture('f2', kickoffAt: _in(const Duration(seconds: 1))),
            _fixture('f1', kickoffAt: _now),
          ],
        }),
      );

      final fixtures = _fixtures(board);
      expect(fixtures.map((f) => f.fixtureId), ['f1', 'f2']);
      expect(fixtures.first.awaySide.revealed, isTrue);
      expect(fixtures.first.awaySide.pick?.homeGoals, 3);
      expect(fixtures.last.awaySide.revealed, isFalse);
      expect(fixtures.last.awaySide.pick, isNull);
    });

    test('after kickoff both sides show; one who did not predict shows '
        'no pick', () async {
      final board = await _read(
        _state([_pathOneSemi()]),
        _Picks({
          _stageOne: [
            _fixture(
              'f1',
              kickoffAt: _in(const Duration(hours: -1)),
              picks: {userNo(1): _pick(2, 0)},
            ),
          ],
        }),
      );

      final fixture = _fixtures(board).single;
      expect(fixture.state, H2hFixtureState.live);
      expect(fixture.homeSide.pick?.homeGoals, 2);
      expect(fixture.awaySide.revealed, isTrue);
      expect(fixture.awaySide.pick, isNull);
    });

    test('a fixture with no kickoff counts as not started', () async {
      final board = await _read(
        _state([_pathOneSemi()]),
        _Picks({
          _stageOne: [_fixture('f1')],
        }),
      );

      final fixture = _fixtures(board).single;
      expect(fixture.state, H2hFixtureState.notStarted);
      expect(fixture.kickoffAt, isNull);
      expect(fixture.homeSide.revealed, isTrue);
      expect(fixture.homeSide.pick, isNotNull);
      expect(fixture.awaySide.revealed, isFalse);
      expect(fixture.awaySide.pick, isNull);
    });

    test('a watcher sees every side withheld before kickoff and every '
        'side after', () async {
      final board = await _read(
        _state([_pathOneSemi(), _pathTwoSemi()]),
        _Picks({
          _stageOne: [
            _fixture('f1', kickoffAt: _in(const Duration(hours: 2))),
            _fixture('f2', kickoffAt: _in(const Duration(hours: -2))),
          ],
          _stageTwo: [
            _fixture('f3', kickoffAt: _in(const Duration(hours: 3))),
            _fixture('f4', kickoffAt: null),
          ],
        }),
        who: AuthenticatedUser(userId: userNo(99), role: PlatformRole.user),
      );

      expect(board.paths.map((p) => p.place), [1, 2]);
      var sides = 0;
      for (final path in board.paths) {
        for (final stage in path.stages) {
          for (final pair in stage.pairs) {
            for (final fixture in pair.fixtures) {
              final started = fixture.fixtureId == 'f2';
              for (final side in [fixture.homeSide, fixture.awaySide]) {
                sides++;
                expect(side.revealed, started, reason: fixture.fixtureId);
                expect(side.pick != null, started, reason: fixture.fixtureId);
              }
            }
          }
        }
      }
      expect(sides, 16);
    });

    test('an admin is read like a player', () async {
      final board = await _read(
        _state([_pathOneSemi()]),
        _Picks({
          _stageOne: [_fixture('f1', kickoffAt: _in(const Duration(hours: 2)))],
        }),
        who: admin,
      );

      for (final pair in _path(board, 1).stages.first.pairs) {
        for (final fixture in pair.fixtures) {
          expect(fixture.homeSide.revealed, isFalse);
          expect(fixture.homeSide.pick, isNull);
          expect(fixture.awaySide.revealed, isFalse);
          expect(fixture.awaySide.pick, isNull);
        }
      }
    });
  });

  group('GetH2hCupBoard: the board itself', () {
    test('a fixture is not started, live, finished or void', () async {
      final board = await _read(
        _state([_pathOneSemi()]),
        _Picks({
          _stageOne: [
            _fixture(
              'void',
              counted: false,
              kickoffAt: _in(const Duration(hours: 5)),
            ),
            _fixture('soon', kickoffAt: _in(const Duration(hours: 4))),
            _fixture('live', kickoffAt: _in(const Duration(hours: -1))),
            _fixture(
              'done',
              kickoffAt: _in(const Duration(hours: -3)),
              homeGoals: 2,
              awayGoals: 1,
            ),
          ],
        }),
      );

      final byId = {for (final f in _fixtures(board)) f.fixtureId: f};
      expect(byId['done']?.state, H2hFixtureState.finished);
      expect(byId['done']?.homeGoals, 2);
      expect(byId['done']?.awayGoals, 1);
      expect(byId['live']?.state, H2hFixtureState.live);
      expect(byId['soon']?.state, H2hFixtureState.notStarted);
      expect(byId['void']?.state, H2hFixtureState.voided);
    });

    test('fixtures come by kickoff, those with none last', () async {
      final board = await _read(
        _state([_pathOneSemi()]),
        _Picks({
          _stageOne: [
            _fixture('c'),
            _fixture('b', kickoffAt: _in(const Duration(hours: 3))),
            _fixture('a', kickoffAt: _in(const Duration(hours: 1))),
          ],
        }),
      );

      expect(_fixtures(board).map((f) => f.fixtureId), ['a', 'b', 'c']);
    });

    test('both pairs of a stage list the same fixtures', () async {
      final board = await _read(
        _state([_pathOneSemi()]),
        _Picks({
          _stageOne: [
            _fixture('f1', kickoffAt: _in(const Duration(hours: 1))),
            _fixture('f2', kickoffAt: _in(const Duration(hours: 2))),
          ],
        }),
      );

      expect(_fixtures(board).map((f) => f.fixtureId), ['f1', 'f2']);
      expect(_fixtures(board, pair: 1).map((f) => f.fixtureId), ['f1', 'f2']);
    });

    test('names, groups and the caller come with the pair', () async {
      final board = await _read(
        _state([_pathOneSemi()]),
        _Picks({_stageOne: <H2hCupStageFixture>[]}),
      );

      final stage = _path(board, 1).stages.first;
      expect(board.monthStart, _november);
      expect(stage.round, H2hCupRound.semi);
      expect(stage.cupDay, 1);
      expect(stage.phase, MyH2hCupPhase.live);
      expect(stage.attempt, 1);
      expect(stage.day, DateTime.utc(2026, 11, 22));
      final pair = stage.pairs.first;
      expect(pair.slot, 1);
      expect(pair.home.isMe, isTrue);
      expect(pair.home.groupNumber, 1);
      expect(pair.away.userId, userNo(3));
      expect(pair.away.isMe, isFalse);
      expect(pair.away.displayName, 'name ${userNo(3).value}');
      expect(pair.decided, isFalse);
      expect(pair.winner, isNull);
      expect(pair.fixtures, isEmpty);
      final finale = _path(board, 1).stages.last;
      expect(finale.round, H2hCupRound.finale);
      expect(finale.phase, MyH2hCupPhase.waiting);
      expect(finale.pairs, isEmpty);
    });

    test('a decided pair names its winner', () async {
      final board = await _read(
        _state([
          _pathOneSemi(
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
        ]),
        _Picks({_stageOne: <H2hCupStageFixture>[]}),
      );

      final pairs = _path(board, 1).stages.first.pairs;
      expect(pairs.first.decided, isTrue);
      expect(pairs.first.winner, userNo(3));
      expect(pairs.last.decided, isFalse);
      expect(pairs.last.winner, isNull);
    });

    test('three qualifiers: the one without a pair has a bye', () async {
      final board = await _read(
        _state([
          _stage(
            id: _stageOne,
            round: H2hCupRound.semi,
            pairs: [H2hCupPair(slot: 1, home: userNo(1), away: userNo(2))],
          ),
        ], pathOne: 3),
        _Picks({_stageOne: <H2hCupStageFixture>[]}),
        who: AuthenticatedUser(userId: userNo(3), role: PlatformRole.user),
      );

      final semi = _path(board, 1).stages.first;
      expect(semi.bye?.userId, userNo(3));
      expect(semi.bye?.isMe, isTrue);
    });

    test('the title of a path arrives with the champion named', () async {
      final board = await _read(
        H2hCupState(
          entries: _entries(),
          stages: [_pathOneSemi()],
          titles: [
            H2hCupTitle(
              place: 1,
              champion: userNo(1),
              runnerUp: userNo(2),
              how: 'final',
            ),
          ],
        ),
        _Picks({_stageOne: <H2hCupStageFixture>[]}),
      );

      final title = _path(board, 1).title;
      expect(title?.how, 'final');
      expect(title?.champion?.isMe, isTrue);
      expect(title?.runnerUp?.userId, userNo(2));
      expect(_path(board, 2).title, isNull);
    });

    test('every path of the month is on the board, not only his', () async {
      final board = await _read(
        _state([_pathOneSemi(), _pathTwoSemi()]),
        _Picks({
          _stageOne: <H2hCupStageFixture>[],
          _stageTwo: <H2hCupStageFixture>[],
        }),
      );

      expect(board.paths.map((p) => p.place), [1, 2]);
      expect(_path(board, 2).stages.first.pairs, hasLength(2));
      expect(
        _path(board, 2).stages.first.pairs.any((p) => p.home.isMe),
        isFalse,
      );
    });
  });

  group('GetH2hCupBoard: reading', () {
    test('no cup stands: an empty board and nothing read', () async {
      final picks = _Picks(const <H2hCupStageId, List<H2hCupStageFixture>>{});
      final board = await _read(H2hCupState.empty, picks);

      expect(board.monthStart, isNull);
      expect(board.paths, isEmpty);
      expect(picks.calls, 0);
    });

    test('a cup with no stage yet reads no fixtures', () async {
      final picks = _Picks(const <H2hCupStageId, List<H2hCupStageFixture>>{});
      final board = await _read(_state(const <H2hCupStage>[]), picks);

      expect(picks.calls, 0);
      expect(board.paths.map((p) => p.place), [1, 2]);
      expect(_path(board, 1).stages.first.phase, MyH2hCupPhase.waiting);
    });

    test('the reader is asked once, for the month, as the caller, at the '
        'server clock', () async {
      final picks = _Picks({
        _stageOne: <H2hCupStageFixture>[],
        _stageTwo: <H2hCupStageFixture>[],
      });
      await _read(_state([_pathOneSemi(), _pathTwoSemi()]), picks);

      expect(picks.calls, 1);
      expect(picks.lastReader, userNo(1));
      expect(picks.lastNow, _now);
      expect(picks.lastStages?.map((s) => s.id), [_stageOne, _stageTwo]);
    });

    test('a failure of the reader is returned as it came', () async {
      final result = await GetH2hCupBoard(
        cups: _Cups(_state([_pathOneSemi()])),
        picks: _Picks(
          const <H2hCupStageId, List<H2hCupStageFixture>>{},
          failure: const AppError.transient('db.down', 'down'),
        ),
        profiles: NamingProfiles(),
        clock: AtClock(_now),
      )(principal: _me);

      expect(result, isA<Err<H2hCupBoard>>());
      final error = (result as Err<H2hCupBoard>).error;
      expect(error.kind, ErrorKind.transient);
      expect(error.code, 'db.down');
    });
  });

  // NK330_05
  group('GetH2hCupBoard: the points of a pair', () {
    final past = _in(const Duration(hours: -3));

    H2hCupBoardPairView firstPair(H2hCupBoard board) =>
        _path(board, 1).stages.first.pairs.first;

    test('an undecided pair adds the points of the counted fixtures it '
        'shows, and a voided fixture adds none', () async {
      final board = await _read(
        _state([_pathOneSemi()]),
        _Picks({
          _stageOne: [
            _fixture(
              'f1',
              kickoffAt: past,
              homeGoals: 2,
              awayGoals: 1,
              picks: {userNo(1): _scored(2, 1, 5), userNo(3): _scored(1, 0, 3)},
            ),
            _fixture(
              'f2',
              kickoffAt: past,
              homeGoals: 0,
              awayGoals: 0,
              picks: {
                userNo(1): _scored(0, 0, 2),
                userNo(3): _scored(1, 1, null),
              },
            ),
            _fixture(
              'f3',
              kickoffAt: past,
              counted: false,
              homeGoals: 1,
              awayGoals: 1,
              picks: {userNo(1): _scored(1, 1, 9), userNo(3): _scored(1, 1, 9)},
            ),
          ],
        }),
      );

      final pair = firstPair(board);
      expect(pair.decided, isFalse);
      expect(pair.homePoints, 7);
      expect(pair.awayPoints, 3);

      final other = _path(board, 1).stages.first.pairs.last;
      expect(other.homePoints, 0);
      expect(other.awayPoints, 0);
    });

    test('a side that is withheld adds nothing, whatever the reader '
        'handed over', () async {
      final board = await _read(
        _state([_pathOneSemi()]),
        _Picks({
          _stageOne: [
            _fixture(
              'f1',
              kickoffAt: _in(const Duration(hours: 2)),
              picks: {
                userNo(1): _scored(1, 0, null),
                userNo(3): _scored(2, 2, 99),
              },
            ),
          ],
        }),
      );

      expect(_fixtures(board).single.awaySide.revealed, isFalse);
      final pair = firstPair(board);
      expect(pair.homePoints, 0);
      expect(pair.awayPoints, 0);
    });

    test(
      'a watcher reads both sides once the fixture has kicked off',
      () async {
        final board = await _read(
          _state([_pathOneSemi()]),
          _Picks({
            _stageOne: [
              _fixture(
                'f1',
                kickoffAt: past,
                homeGoals: 1,
                awayGoals: 0,
                picks: {
                  userNo(1): _scored(1, 0, 4),
                  userNo(3): _scored(0, 1, 6),
                },
              ),
              _fixture(
                'f2',
                kickoffAt: _in(const Duration(hours: 2)),
                picks: {
                  userNo(1): _scored(1, 0, 8),
                  userNo(3): _scored(0, 1, 8),
                },
              ),
            ],
          }),
          who: AuthenticatedUser(userId: userNo(99), role: PlatformRole.user),
        );

        final pair = firstPair(board);
        expect(pair.homePoints, 4);
        expect(pair.awayPoints, 6);
      },
    );

    test(
      'a decided pair carries the figures the cup decided it with',
      () async {
        final board = await _read(
          _state([
            _pathOneSemi(
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
          ]),
          _Picks({
            _stageOne: [
              _fixture(
                'f1',
                kickoffAt: past,
                homeGoals: 1,
                awayGoals: 0,
                picks: {
                  userNo(1): _scored(1, 0, 1),
                  userNo(3): _scored(0, 1, 1),
                },
              ),
            ],
          }),
        );

        final pair = firstPair(board);
        expect(pair.decided, isTrue);
        expect(pair.homePoints, 7);
        expect(pair.awayPoints, 9);
      },
    );

    test('a pair with no fixture reads 0 and 0', () async {
      final board = await _read(
        _state([_pathOneSemi()]),
        _Picks({_stageOne: <H2hCupStageFixture>[]}),
      );

      final pair = firstPair(board);
      expect(pair.homePoints, 0);
      expect(pair.awayPoints, 0);
    });
  });
}
