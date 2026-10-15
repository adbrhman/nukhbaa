import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _participant = 'c8171000-0000-4000-8000-0000000000a1';
const _scored = 'c8171000-0000-4000-8000-0000000000f1';
const _waiting = 'c8171000-0000-4000-8000-0000000000f2';

final class _Reader implements MyFixtureScoreReader {
  _Reader(this.answer);

  final Result<List<MyFixtureScore>> answer;
  final List<UserId> asked = [];

  @override
  Future<Result<List<MyFixtureScore>>> listByUser(UserId userId) async {
    asked.add(userId);
    return answer;
  }
}

const _player = AuthenticatedUser(
  userId: UserId('11111111-2222-3333-4444-555555555555'),
  role: PlatformRole.user,
);

void main() {
  test("reads the caller's own rows, scored and waiting", () async {
    const rows = <MyFixtureScore>[
      MyFixtureScore(
        participantId: ParticipantId(_participant),
        fixture: FixtureRef(_scored),
        grade: FixtureScoreGrade.exactScoreline,
        points: 3,
        result: FixtureResult.fromStored(
          fixture: FixtureRef(_scored),
          homeGoals: 1,
          awayGoals: 0,
        ),
      ),
      MyFixtureScore(
        participantId: ParticipantId(_participant),
        fixture: FixtureRef(_waiting),
        result: FixtureResult.fromStored(
          fixture: FixtureRef(_waiting),
          homeGoals: 2,
          awayGoals: 1,
        ),
      ),
    ];
    final reader = _Reader(const Result.ok(rows));

    final result = await ListMyFixtureScores(reader: reader)(
      principal: _player,
    );

    expect((result as Ok<List<MyFixtureScore>>).value, rows);
    expect(reader.asked, [_player.userId]);
  });

  test('a failed read is returned as it came', () async {
    final reader = _Reader(
      const Result.err(
        AppError.transient('db.query_timeout', 'Database query timed out'),
      ),
    );

    final result = await ListMyFixtureScores(reader: reader)(
      principal: _player,
    );

    expect(
      (result as Err<List<MyFixtureScore>>).error.code,
      'db.query_timeout',
    );
  });

  test('rows compare by value', () {
    MyFixtureScore row(String fixture) => MyFixtureScore(
      participantId: const ParticipantId(_participant),
      fixture: FixtureRef(fixture),
      grade: FixtureScoreGrade.incorrect,
      points: 0,
    );

    expect(row(_scored), row(_scored));
    expect(row(_scored).hashCode, row(_scored).hashCode);
    expect(row(_scored), isNot(row(_waiting)));
  });
}
