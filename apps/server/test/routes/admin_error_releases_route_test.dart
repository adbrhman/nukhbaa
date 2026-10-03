import 'dart:io';

import 'package:application/application.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/error-releases/index.dart' as route;
import 'competition_route_harness.dart';

final class _Reader implements ErrorReleaseReader {
  @override
  Future<Result<List<ErrorReleaseSummary>>> releases({
    required int limit,
  }) async => Result.ok([
    ErrorReleaseSummary(
      build: 'abc1235',
      errors: 3,
      critical: 1,
      occurrences: 120,
      firstSeenAt: DateTime.utc(2026, 10, 3, 9),
      lastSeenAt: DateTime.utc(2026, 10, 3, 10),
    ),
  ]);

  @override
  Future<Result<List<ErrorFileSummary>>> files({required int limit}) async =>
      const Result.ok([
        ErrorFileSummary(
          file: 'package:mobile/features/fixtures/card.dart',
          errors: 2,
          occurrences: 90,
        ),
      ]);
}

void main() {
  final root = CompositionRoot.forTesting(
    adminErrorReleases: AdminErrorReleases(reader: _Reader()),
  );

  test('GET /admin/error-releases answers builds and files', () async {
    final response = await route.onRequest(
      wireContext(
        root: root,
        principal: adminPrincipal(),
        method: HttpMethod.get,
      ),
    );

    expect(response.statusCode, HttpStatus.ok);
    final body = await decodeBody(response);
    final release =
        (body['releases']! as List<Object?>).single! as Map<String, Object?>;
    expect(release['build'], 'abc1235');
    expect(release['critical'], 1);
    final file =
        (body['files']! as List<Object?>).single! as Map<String, Object?>;
    expect(file['occurrences'], 90);
  });

  test('a player is refused', () async {
    final response = await route.onRequest(
      wireContext(
        root: root,
        principal: userPrincipal(),
        method: HttpMethod.get,
      ),
    );

    expect(response.statusCode, HttpStatus.unauthorized);
  });
}
