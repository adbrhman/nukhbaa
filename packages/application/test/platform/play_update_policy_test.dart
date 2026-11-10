import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// The oldest supported Google Play build (script 253, migration 0206): the
/// release check carries it beside the APK minimum, each from its own
/// store; an admin types it or clears it, and a player cannot.
final class _Builds implements BuildInfoRepository {
  @override
  Future<Result<LatestBuild>> fetchLatest() async => Result.ok(
    LatestBuild(
      publishedAt: DateTime.utc(2026, 11, 10),
      apkUrl: 'https://example.com/a.apk',
      buildNumber: 870,
    ),
  );
}

final class _Policy implements AppUpdatePolicyStore {
  _Policy([this.minimum]);

  int? minimum;
  bool failRead = false;
  final List<UserId> writers = <UserId>[];

  @override
  Future<Result<int?>> minSupportedBuild() async => failRead
      ? const Result.err(AppError.transient('db.down', 'down'))
      : Result.ok(minimum);

  @override
  Future<Result<int?>> setMinSupportedBuild({
    required int? buildNumber,
    required UserId by,
  }) async {
    writers.add(by);
    minimum = buildNumber;
    return Result.ok(buildNumber);
  }
}

const AuthenticatedUser _admin = AuthenticatedUser(
  userId: UserId('5e5e5e5e-0000-4000-8000-000000000253'),
  role: PlatformRole.admin,
);

const AuthenticatedUser _player = AuthenticatedUser(
  userId: UserId('5e5e5e5e-0000-4000-8000-000000000254'),
  role: PlatformRole.user,
);

void main() {
  group('GetLatestBuild with a Play policy', () {
    test('carries each minimum from its own store', () async {
      final result = await GetLatestBuild(
        _Builds(),
        policy: _Policy(870),
        playPolicy: _Policy(845),
      )();

      final LatestBuild build = (result as Ok<LatestBuild>).value;
      expect(build.buildNumber, 870);
      expect(build.minSupportedBuild, 870);
      expect(build.minSupportedPlayBuild, 845);
    });

    test('a Play minimum that cannot be read leaves the rest', () async {
      final result = await GetLatestBuild(
        _Builds(),
        policy: _Policy(870),
        playPolicy: _Policy(845)..failRead = true,
      )();

      final LatestBuild build = (result as Ok<LatestBuild>).value;
      expect(build.minSupportedBuild, 870);
      expect(build.minSupportedPlayBuild, isNull);
    });

    test('without a Play policy nothing changes for the APK', () async {
      final result = await GetLatestBuild(_Builds(), policy: _Policy(870))();

      final LatestBuild build = (result as Ok<LatestBuild>).value;
      expect(build.minSupportedBuild, 870);
      expect(build.minSupportedPlayBuild, isNull);
    });

    test('the APK minimum keeps the Play one', () {
      final LatestBuild build = LatestBuild(
        publishedAt: DateTime.utc(2026, 11, 10),
        apkUrl: 'https://example.com/a.apk',
      ).withMinSupportedPlayBuild(845).withMinSupportedBuild(870);

      expect(build.minSupportedPlayBuild, 845);
      expect(build.minSupportedBuild, 870);
    });
  });

  group('SetMinSupportedPlayBuild', () {
    test('an admin stores the number he typed', () async {
      final _Policy policy = _Policy();
      final result = await SetMinSupportedPlayBuild(policy)(
        principal: _admin,
        buildNumber: 845,
      );

      expect((result as Ok<int?>).value, 845);
      expect(policy.minimum, 845);
      expect(policy.writers, <UserId>[_admin.userId]);
    });

    test('and clears it', () async {
      final _Policy policy = _Policy(845);
      final result = await SetMinSupportedPlayBuild(policy)(
        principal: _admin,
        buildNumber: null,
      );

      expect((result as Ok<int?>).value, isNull);
      expect(policy.minimum, isNull);
    });

    test('a number below 1 or above Play\'s ceiling is refused, nothing '
        'stored', () async {
      for (final int number in <int>[
        0,
        -3,
        SetMinSupportedPlayBuild.maxVersionCode + 1,
      ]) {
        final _Policy policy = _Policy();
        final result = await SetMinSupportedPlayBuild(policy)(
          principal: _admin,
          buildNumber: number,
        );

        expect(
          (result as Err<int?>).error.code,
          'app.play_build_invalid',
          reason: '$number',
        );
        expect(policy.writers, isEmpty);
      }
    });

    test('a player is refused, nothing stored', () async {
      final _Policy policy = _Policy();
      final result = await SetMinSupportedPlayBuild(policy)(
        principal: _player,
        buildNumber: 845,
      );

      expect((result as Err<int?>).error.kind, ErrorKind.authorization);
      expect(policy.writers, isEmpty);
    });
  });
}
