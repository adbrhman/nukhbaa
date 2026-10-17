import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _u1 = 'aaaaaaaa-0000-0000-0000-000000000001';
const _u2 = 'aaaaaaaa-0000-0000-0000-000000000002';
const _token = 'fcm-token-of-one-phone';

const _down = Result<void>.err(AppError.transient('db.down', 'down'));

AuthenticatedUser _player(String id) =>
    AuthenticatedUser(userId: UserId(id), role: PlatformRole.user);

final class _CountingTokens implements DeviceTokenRepository {
  int upserts = 0;
  int removes = 0;
  final List<Result<void>> next = <Result<void>>[];

  @override
  Future<Result<void>> upsert({
    required UserId userId,
    required String token,
    required String platform,
  }) async {
    upserts++;
    return next.isEmpty ? const Result.ok(null) : next.removeAt(0);
  }

  @override
  Future<Result<void>> remove({
    required UserId userId,
    required String token,
  }) async {
    removes++;
    return const Result.ok(null);
  }
}

void main() {
  late _CountingTokens inner;
  late DateTime clock;
  late RegisterDeviceToken register;

  setUp(() {
    inner = _CountingTokens();
    clock = DateTime.utc(2026, 10, 17, 21);
    register = RegisterDeviceToken(
      deviceTokens: CachedDeviceTokenRepository(inner, now: () => clock),
    );
  });

  Future<Result<void>> open(String user, {String platform = 'android'}) =>
      register(principal: _player(user), token: _token, platform: platform);

  test('the same phone opening again is written once', () async {
    expect((await open(_u1)).isOk, isTrue);
    expect((await open(_u1)).isOk, isTrue);
    expect((await open(_u1)).isOk, isTrue);

    expect(inner.upserts, 1);
  });

  test('a web registration is always written', () async {
    await open(_u1, platform: 'web');
    await open(_u1, platform: 'web');

    expect(inner.upserts, 2);
  });

  test('the phone signed in as another player is written at once', () async {
    await open(_u1);
    await open(_u2);
    await open(_u1);

    expect(inner.upserts, 3);
  });

  test('a new platform for the same token is written', () async {
    await open(_u1);
    await open(_u1, platform: 'ios');

    expect(inner.upserts, 2);
  });

  test('a sign-out drops the token, the next start writes it', () async {
    await open(_u1);
    await register.unregister(principal: _player(_u1), token: _token);
    await open(_u1);

    expect(inner.removes, 1);
    expect(inner.upserts, 2);
  });

  test('a failed write is not remembered', () async {
    inner.next.add(_down);

    expect((await open(_u1)).isOk, isFalse);
    expect((await open(_u1)).isOk, isTrue);
    await open(_u1);

    expect(inner.upserts, 2);
  });

  test('the token is written again after the ttl', () async {
    await open(_u1);
    clock = clock.add(const Duration(hours: 7));
    await open(_u1);

    expect(inner.upserts, 2);
  });
}
