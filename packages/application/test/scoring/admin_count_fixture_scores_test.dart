import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// The admin's counted fixtures in one read (batch 156).
final class _Counter implements FixtureScoreCounter {
  final List<List<FixtureRef>> asked = <List<FixtureRef>>[];

  @override
  Future<Result<Map<String, int>>> countByFixtures(
    List<FixtureRef> fixtures,
  ) async {
    asked.add(fixtures);
    return Result.ok(<String, int>{for (final f in fixtures) f.value: 4});
  }
}

const AuthenticatedUser _admin = AuthenticatedUser(
  userId: UserId('5e5e5e5e-0000-4000-8000-0000000001c1'),
  role: PlatformRole.admin,
);

const AuthenticatedUser _player = AuthenticatedUser(
  userId: UserId('5e5e5e5e-0000-4000-8000-0000000001c2'),
  role: PlatformRole.user,
);

const String _f1 = '00000000-0156-4000-8000-0000000000f1';
const String _f2 = '00000000-0156-4000-8000-0000000000f2';

void main() {
  test('one read for every fixture, a repeated id once', () async {
    final _Counter counter = _Counter();
    final result = await AdminCountFixtureScores(counter: counter)(
      principal: _admin,
      fixtureIds: const [_f1, _f2, _f1],
    );

    expect((result as Ok<Map<String, int>>).value, {_f1: 4, _f2: 4});
    expect(counter.asked.single.map((f) => f.value), [_f1, _f2]);
  });

  test('more than 200 is refused, nothing read', () async {
    final _Counter counter = _Counter();
    final List<String> many = <String>[
      for (var i = 0; i < 201; i++)
        '00000000-0156-4000-8000-${i.toString().padLeft(12, '0')}',
    ];
    final result = await AdminCountFixtureScores(counter: counter)(
      principal: _admin,
      fixtureIds: many,
    );

    expect(
      (result as Err<Map<String, int>>).error.code,
      'admin.too_many_fixtures',
    );
    expect(counter.asked, isEmpty);
  });

  test('an id that is not a fixture id is refused', () async {
    final result = await AdminCountFixtureScores(counter: _Counter())(
      principal: _admin,
      fixtureIds: const ['nope'],
    );

    expect((result as Err<Map<String, int>>).error.kind, ErrorKind.validation);
  });

  test('a player is refused', () async {
    final _Counter counter = _Counter();
    final result = await AdminCountFixtureScores(counter: counter)(
      principal: _player,
      fixtureIds: const [_f1],
    );

    expect(
      (result as Err<Map<String, int>>).error.kind,
      ErrorKind.authorization,
    );
    expect(counter.asked, isEmpty);
  });

  test('nothing asked, nothing read', () async {
    final _Counter counter = _Counter();
    final result = await AdminCountFixtureScores(counter: counter)(
      principal: _admin,
      fixtureIds: const [],
    );

    expect((result as Ok<Map<String, int>>).value, isEmpty);
    expect(counter.asked, isEmpty);
  });
}
