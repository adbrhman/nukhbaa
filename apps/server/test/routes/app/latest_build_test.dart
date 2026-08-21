import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes live outside `lib/`, so they have no `package:` URI; a
// relative import is the only way to unit-test the handler in isolation
// (mirrors `test/routes/health_test.dart`).
// ignore: always_use_package_imports
import '../../../routes/app/latest-build/index.dart' as route;

/// In-memory fake of the build-info port (Coding Standards ADR, Section 6).
final class _FakeBuildInfoRepository implements BuildInfoRepository {
  _FakeBuildInfoRepository(this._response);

  final Result<LatestBuild> _response;

  @override
  Future<Result<LatestBuild>> fetchLatest() async => _response;
}

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

({_MockRequestContext context, Future<CompositionRoot> root}) _wire({
  required Result<LatestBuild> response,
  HttpMethod method = HttpMethod.get,
}) {
  final useCase = GetLatestBuild(_FakeBuildInfoRepository(response));
  final root = Future<CompositionRoot>.value(
    CompositionRoot.forTesting(getLatestBuild: useCase),
  );

  final request = _MockRequest();
  when(() => request.method).thenReturn(method);

  final context = _MockRequestContext();
  when(() => context.request).thenReturn(request);
  when(() => context.read<Future<CompositionRoot>>()).thenAnswer((_) => root);

  return (context: context, root: root);
}

Future<Map<String, Object?>> _decodeBody(Response response) async {
  final decoded = await response.json() as Map<Object?, Object?>;
  return decoded.cast<String, Object?>();
}

void main() {
  group('GET /app/latest-build route', () {
    test('returns 200 with the latest version and apk url', () async {
      final publishedAt = DateTime.utc(2026, 8, 20, 12);
      final wired = _wire(
        response: Result.ok(
          LatestBuild(
            publishedAt: publishedAt,
            apkUrl: 'https://example.com/a.apk',
          ),
        ),
      );

      final response = await route.onRequest(wired.context);

      expect(response.statusCode, HttpStatus.ok);
      final body = await _decodeBody(response);
      expect(body['published_at'], publishedAt.toIso8601String());
      expect(body['apk_url'], 'https://example.com/a.apk');
      expect(body['schema_version'], 2);
    });

    test('surfaces a transient error as 503', () async {
      final wired = _wire(
        response: const Result.err(
          AppError.transient(
            'app.latest_build_unavailable',
            'تعذّر جلب أحدث إصدار حالياً.',
          ),
        ),
      );

      final response = await route.onRequest(wired.context);

      expect(response.statusCode, HttpStatus.serviceUnavailable);
    });

    test(
      'rejects non-GET methods with 405 without touching the use-case',
      () async {
        final wired = _wire(
          response: Result.ok(
            LatestBuild(
              publishedAt: DateTime.utc(2026, 8, 20),
              apkUrl: 'https://example.com/a.apk',
            ),
          ),
          method: HttpMethod.post,
        );

        final response = await route.onRequest(wired.context);

        expect(response.statusCode, HttpStatus.methodNotAllowed);
        verifyNever(() => wired.context.read<Future<CompositionRoot>>());
      },
    );
  });
}
