import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/app/min-build/index.dart' as route;
import 'competition_route_harness.dart';

/// The newest release, numbered or not.
final class _Builds implements BuildInfoRepository {
  _Builds({this.number});

  final int? number;

  @override
  Future<Result<LatestBuild>> fetchLatest() async => Result.ok(
    LatestBuild(
      publishedAt: DateTime.utc(2026, 10, 15),
      apkUrl: 'https://example.com/a.apk',
      buildNumber: number,
    ),
  );
}

final class _Policy implements AppUpdatePolicyStore {
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

CompositionRoot _root(_Policy policy, {int? latest = 214}) =>
    CompositionRoot.forTesting(
      setMinSupportedBuild: SetMinSupportedBuild(
        policy: policy,
        builds: _Builds(number: latest),
      ),
    );

/// `PUT /admin/app/min-build` (batch 147, migration 0113).
void main() {
  test('an admin makes the newest release the minimum', () async {
    final _Policy policy = _Policy();
    final response = await route.onRequest(
      wireContext(
        root: _root(policy),
        principal: adminPrincipal(),
        method: HttpMethod.put,
        body: const {'to_latest': true},
      ),
    );

    expect(response.statusCode, HttpStatus.ok);
    final body = await decodeBody(response);
    expect(body['latest_build'], 214);
    expect(body['min_supported_build'], 214);
    expect(policy.minimum, 214);
  });

  test('and clears it', () async {
    final _Policy policy = _Policy()..minimum = 214;
    final response = await route.onRequest(
      wireContext(
        root: _root(policy),
        principal: adminPrincipal(),
        method: HttpMethod.put,
        body: const {'to_latest': false},
      ),
    );

    expect(response.statusCode, HttpStatus.ok);
    expect((await decodeBody(response))['min_supported_build'], isNull);
    expect(policy.minimum, isNull);
  });

  test('a release without a number is 400, nothing stored', () async {
    final _Policy policy = _Policy();
    final response = await route.onRequest(
      wireContext(
        root: _root(policy, latest: null),
        principal: adminPrincipal(),
        method: HttpMethod.put,
        body: const {'to_latest': true},
      ),
    );

    expect(response.statusCode, HttpStatus.badRequest);
    expect((await decodeBody(response))['code'], 'app.build_number_unknown');
    expect(policy.writes, 0);
  });

  test('a body without a boolean is 400, nothing stored', () async {
    final _Policy policy = _Policy();
    final response = await route.onRequest(
      wireContext(
        root: _root(policy),
        principal: adminPrincipal(),
        method: HttpMethod.put,
        body: const {'to_latest': 'yes'},
      ),
    );

    expect(response.statusCode, HttpStatus.badRequest);
    expect(policy.writes, 0);
  });

  test('a player is refused, nothing stored', () async {
    final _Policy policy = _Policy();
    final response = await route.onRequest(
      wireContext(
        root: _root(policy),
        principal: userPrincipal(),
        method: HttpMethod.put,
        body: const {'to_latest': true},
      ),
    );

    expect(response.statusCode, HttpStatus.unauthorized);
    expect(policy.writes, 0);
  });

  test('only PUT', () async {
    final response = await route.onRequest(
      wireContext(
        root: _root(_Policy()),
        principal: adminPrincipal(),
        method: HttpMethod.get,
      ),
    );

    expect(response.statusCode, HttpStatus.methodNotAllowed);
  });
}
