import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// In-memory fake of the port (Coding Standards ADR, Section 6: use-cases are
/// tested against in-memory fakes, no infrastructure).
final class _FakeBuildInfoRepository implements BuildInfoRepository {
  _FakeBuildInfoRepository(this._response);
  final Result<LatestBuild> _response;

  @override
  Future<Result<LatestBuild>> fetchLatest() async => _response;
}

void main() {
  group('GetLatestBuild', () {
    test('passes through a successful repository read', () async {
      final build = LatestBuild(
        publishedAt: DateTime.utc(2026, 8, 20),
        apkUrl: 'https://example.com/a.apk',
      );
      final useCase = GetLatestBuild(
        _FakeBuildInfoRepository(Result.ok(build)),
      );

      final result = await useCase();

      expect(result.isOk, isTrue);
      expect((result as Ok<LatestBuild>).value, build);
    });

    test('passes through a transient repository failure', () async {
      final useCase = GetLatestBuild(
        _FakeBuildInfoRepository(
          const Result.err(
            AppError.transient('app.latest_build_unavailable', 'unreachable'),
          ),
        ),
      );

      final result = await useCase();

      expect(result.isErr, isTrue);
      expect((result as Err<LatestBuild>).error.kind, ErrorKind.transient);
    });
  });
}
