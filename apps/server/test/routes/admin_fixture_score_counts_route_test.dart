import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/fixture-score-counts/index.dart' as route;
import 'competition_route_harness.dart';

final class _Counter implements FixtureScoreCounter {
  final List<List<FixtureRef>> asked = <List<FixtureRef>>[];

  @override
  Future<Result<Map<String, int>>> countByFixtures(
    List<FixtureRef> fixtures,
  ) async {
    asked.add(fixtures);
    return Result.ok(<String, int>{fixtures.first.value: 7});
  }
}

const String _f1 = '00000000-0156-4000-8000-0000000000f1';
const String _f2 = '00000000-0156-4000-8000-0000000000f2';

CompositionRoot _root(_Counter counter) => CompositionRoot.forTesting(
  adminCountFixtureScores: AdminCountFixtureScores(counter: counter),
);

/// `GET /admin/fixture-score-counts` (batch 156).
void main() {
  test('an admin gets every count in one read', () async {
    final _Counter counter = _Counter();
    final response = await route.onRequest(
      wireContext(
        root: _root(counter),
        principal: adminPrincipal(),
        method: HttpMethod.get,
        queryParameters: const {'fixtures': '$_f1, $_f2,'},
      ),
    );

    expect(response.statusCode, HttpStatus.ok);
    expect((await decodeBody(response))['counts'], {_f1: 7});
    expect(counter.asked.single.map((f) => f.value), [_f1, _f2]);
  });

  test('a player is refused, nothing read', () async {
    final _Counter counter = _Counter();
    final response = await route.onRequest(
      wireContext(
        root: _root(counter),
        principal: userPrincipal(),
        method: HttpMethod.get,
        queryParameters: const {'fixtures': _f1},
      ),
    );

    expect(response.statusCode, HttpStatus.unauthorized);
    expect(counter.asked, isEmpty);
  });

  test('a malformed id is 400', () async {
    final response = await route.onRequest(
      wireContext(
        root: _root(_Counter()),
        principal: adminPrincipal(),
        method: HttpMethod.get,
        queryParameters: const {'fixtures': 'nope'},
      ),
    );

    expect(response.statusCode, HttpStatus.badRequest);
  });
}
