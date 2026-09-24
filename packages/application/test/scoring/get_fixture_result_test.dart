import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _fixture = '66666666-6666-6666-6666-666666666666';

final class _Results implements FixtureResultRepository {
  _Results(this.stored);

  final FixtureResult? stored;
  FixtureRef? asked;

  @override
  Future<Result<FixtureResult?>> findByFixture(FixtureRef fixture) async {
    asked = fixture;
    return Result.ok(stored);
  }

  @override
  Future<Result<List<FixtureResult>>> findByFixtures(
    List<FixtureRef> fixtures,
  ) async => const Result.ok([]);

  @override
  Future<Result<void>> upsert(FixtureResult result, DateTime recordedAt) =>
      throw StateError('a read never writes');
}

const _player = AuthenticatedUser(
  userId: UserId('11111111-2222-3333-4444-555555555555'),
  role: PlatformRole.user,
);

void main() {
  test('reads the recorded result of the fixture', () async {
    final results = _Results(
      const FixtureResult.fromStored(
        fixture: FixtureRef(_fixture),
        homeGoals: 1,
        awayGoals: 1,
      ),
    );

    final result = await GetFixtureResult(results: results)(
      principal: _player,
      fixtureId: _fixture,
    );

    final value = (result as Ok<FixtureResult?>).value!;
    expect(value.homeGoals, 1);
    expect(value.awayGoals, 1);
    expect(results.asked, const FixtureRef(_fixture));
  });

  test('no result recorded yet is Ok(null), not an error', () async {
    final result = await GetFixtureResult(results: _Results(null))(
      principal: _player,
      fixtureId: _fixture,
    );

    expect((result as Ok<FixtureResult?>).value, isNull);
  });

  test('a malformed fixture id is refused before any read', () async {
    final results = _Results(null);

    final result = await GetFixtureResult(results: results)(
      principal: _player,
      fixtureId: 'not-a-uuid',
    );

    expect(result.isErr, isTrue);
    expect(results.asked, isNull);
  });
}
