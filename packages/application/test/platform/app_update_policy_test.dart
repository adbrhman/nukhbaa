import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// The oldest supported Android build (batch 147): the release check
/// carries it, an admin sets it to the newest release or clears it, and a
/// player cannot.
final class _Builds implements BuildInfoRepository {
  _Builds(this.response);

  Result<LatestBuild> response;

  @override
  Future<Result<LatestBuild>> fetchLatest() async => response;
}

final class _Policy implements AppUpdatePolicyStore {
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

LatestBuild _release({int? number}) => LatestBuild(
  publishedAt: DateTime.utc(2026, 10, 15),
  apkUrl: 'https://example.com/a.apk',
  buildNumber: number,
);

const AuthenticatedUser _admin = AuthenticatedUser(
  userId: UserId('5e5e5e5e-0000-4000-8000-0000000001b1'),
  role: PlatformRole.admin,
);

const AuthenticatedUser _player = AuthenticatedUser(
  userId: UserId('5e5e5e5e-0000-4000-8000-0000000001b2'),
  role: PlatformRole.user,
);

void main() {
  group('GetLatestBuild with a policy', () {
    test('carries the minimum an admin set', () async {
      final _Policy policy = _Policy()..minimum = 210;
      final result = await GetLatestBuild(
        _Builds(Result.ok(_release(number: 214))),
        policy: policy,
      )();

      final LatestBuild build = (result as Ok<LatestBuild>).value;
      expect(build.buildNumber, 214);
      expect(build.minSupportedBuild, 210);
    });

    test('a minimum that cannot be read leaves only the release', () async {
      final _Policy policy = _Policy()
        ..minimum = 210
        ..failRead = true;
      final result = await GetLatestBuild(
        _Builds(Result.ok(_release(number: 214))),
        policy: policy,
      )();

      expect((result as Ok<LatestBuild>).value.minSupportedBuild, isNull);
    });
  });

  group('SetMinSupportedBuild', () {
    test('an admin makes the newest release the minimum', () async {
      final _Policy policy = _Policy();
      final result = await SetMinSupportedBuild(
        policy: policy,
        builds: _Builds(Result.ok(_release(number: 214))),
      )(principal: _admin, toLatest: true);

      final AppUpdatePolicy stored = (result as Ok<AppUpdatePolicy>).value;
      expect(stored.minSupportedBuild, 214);
      expect(stored.latestBuild, 214);
      expect(policy.minimum, 214);
      expect(policy.writers, <UserId>[_admin.userId]);
    });

    test('and clears it', () async {
      final _Policy policy = _Policy()..minimum = 214;
      final result = await SetMinSupportedBuild(
        policy: policy,
        builds: _Builds(Result.ok(_release(number: 214))),
      )(principal: _admin, toLatest: false);

      expect((result as Ok<AppUpdatePolicy>).value.minSupportedBuild, isNull);
      expect(policy.minimum, isNull);
    });

    test('a newest release without a number is refused, nothing '
        'stored', () async {
      final _Policy policy = _Policy();
      final result = await SetMinSupportedBuild(
        policy: policy,
        builds: _Builds(Result.ok(_release())),
      )(principal: _admin, toLatest: true);

      expect(
        (result as Err<AppUpdatePolicy>).error.code,
        'app.build_number_unknown',
      );
      expect(policy.writers, isEmpty);
    });

    test('a player is refused, nothing stored', () async {
      final _Policy policy = _Policy();
      final result = await SetMinSupportedBuild(
        policy: policy,
        builds: _Builds(Result.ok(_release(number: 214))),
      )(principal: _player, toLatest: true);

      expect(
        (result as Err<AppUpdatePolicy>).error.kind,
        ErrorKind.authorization,
      );
      expect(policy.writers, isEmpty);
    });
  });
}
