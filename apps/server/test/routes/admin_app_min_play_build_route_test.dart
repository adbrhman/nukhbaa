import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/app/min-play-build/index.dart' as route;
import 'competition_route_harness.dart';

/// The Play minimum the route stores.
final class _PlayPolicy implements AppUpdatePolicyStore {
  int? minimum;
  int writes = 0;

  @override
  Future<Result<int?>> minSupportedBuild() async => Result.ok(minimum);

  @override
  Future<Result<int?>> setMinSupportedBuild({
    required int? buildNumber,
    required UserId by,
  }) async {
    writes++;
    minimum = buildNumber;
    return Result.ok(buildNumber);
  }
}

CompositionRoot _root(_PlayPolicy policy) => CompositionRoot.forTesting(
  setMinSupportedPlayBuild: SetMinSupportedPlayBuild(policy),
);

Future<Response> _put(_PlayPolicy policy, Object? body, {bool admin = true}) =>
    route.onRequest(
      wireContext(
        root: _root(policy),
        principal: admin ? adminPrincipal() : userPrincipal(),
        method: HttpMethod.put,
        body: body,
      ),
    );

/// `PUT /admin/app/min-play-build` (script 253, migration 0206).
void main() {
  test('an admin stores the Play minimum he typed', () async {
    final _PlayPolicy policy = _PlayPolicy();
    final response = await _put(policy, const {'build_number': 845});

    expect(response.statusCode, HttpStatus.ok);
    expect((await decodeBody(response))['min_supported_play_build'], 845);
    expect(policy.minimum, 845);
  });

  test('and clears it with null', () async {
    final _PlayPolicy policy = _PlayPolicy()..minimum = 845;
    final response = await _put(policy, const {'build_number': null});

    expect(response.statusCode, HttpStatus.ok);
    expect((await decodeBody(response))['min_supported_play_build'], isNull);
    expect(policy.minimum, isNull);
    expect(policy.writes, 1);
  });

  test('a missing or non-integer number is 400, nothing stored', () async {
    for (final Object body in <Object>[
      const <String, Object?>{},
      const {'build_number': '845'},
      const {'build_number': 845.5},
    ]) {
      final _PlayPolicy policy = _PlayPolicy();
      final response = await _put(policy, body);

      expect(response.statusCode, HttpStatus.badRequest, reason: '$body');
      expect((await decodeBody(response))['code'], 'app.build_number_required');
      expect(policy.writes, 0);
    }
  });

  test('a number below 1 is 400, nothing stored', () async {
    final _PlayPolicy policy = _PlayPolicy();
    final response = await _put(policy, const {'build_number': 0});

    expect(response.statusCode, HttpStatus.badRequest);
    expect((await decodeBody(response))['code'], 'app.play_build_invalid');
    expect(policy.writes, 0);
  });

  test('a player is refused, nothing stored', () async {
    final _PlayPolicy policy = _PlayPolicy();
    final response = await _put(policy, const {
      'build_number': 845,
    }, admin: false);

    expect(response.statusCode, HttpStatus.unauthorized);
    expect(policy.writes, 0);
  });

  test('only PUT', () async {
    final response = await route.onRequest(
      wireContext(
        root: _root(_PlayPolicy()),
        principal: adminPrincipal(),
        method: HttpMethod.get,
      ),
    );

    expect(response.statusCode, HttpStatus.methodNotAllowed);
  });
}
