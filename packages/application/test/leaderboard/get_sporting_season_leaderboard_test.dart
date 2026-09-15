import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fakes.dart' show FixedClock;
import 'fakes.dart' show principalUser;

const _viewer = 'aaaaaaaa-0000-0000-0000-000000000001';
const _u1 = '00000000-0000-0000-0000-000000000001';
const _u2 = '00000000-0000-0000-0000-000000000002';

final class _ScriptedReader implements SportingSeasonStandingsReader {
  _ScriptedReader(this._result);

  final Result<List<SportingSeasonStanding>> _result;
  final List<SportingSeason> asked = <SportingSeason>[];

  @override
  Future<Result<List<SportingSeasonStanding>>> standings(
    SportingSeason season,
  ) async {
    asked.add(season);
    return _result;
  }
}

SportingSeasonStanding _line(String id, int points) =>
    (SportingSeasonStanding.projected(
              userId: UserId(id),
              displayName: id,
              totalPoints: points,
              fixturesScored: 2,
              exactCount: 0,
              decidedCount: 2,
              monthsPlayed: 1,
            )
            as Ok<SportingSeasonStanding>)
        .value;

void main() {
  test('reads the season containing now and ranks most points first', () async {
    final reader = _ScriptedReader(Result.ok([_line(_u1, 4), _line(_u2, 9)]));
    final useCase = GetSportingSeasonLeaderboard(
      reader: reader,
      clock: FixedClock(DateTime.utc(2027, 2, 10)),
    );

    final result = await useCase.call(
      principal: principalUser(userId: _viewer),
    );

    final board = (result as Ok<SportingSeasonLeaderboard>).value;
    expect(reader.asked.single.startYear, 2026);
    expect(board.season.label, '2026/2027');
    expect(board.entries.map((e) => e.userId.value), [_u2, _u1]);
    expect(board.entries.map((e) => e.rank), [1, 2]);
  });

  test('a reader failure is returned unchanged', () async {
    const failure = AppError.transient('db.down', 'down');
    final useCase = GetSportingSeasonLeaderboard(
      reader: _ScriptedReader(const Result.err(failure)),
      clock: FixedClock(DateTime.utc(2026, 9, 20)),
    );

    final result = await useCase.call(
      principal: principalUser(userId: _viewer),
    );

    expect((result as Err<SportingSeasonLeaderboard>).error, failure);
  });
}
