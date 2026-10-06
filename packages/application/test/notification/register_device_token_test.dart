import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _user = '11111111-1111-1111-1111-111111111111';

final class _Tokens implements DeviceTokenRepository {
  final List<(String, String)> saved = [];

  @override
  Future<Result<void>> upsert({
    required UserId userId,
    required String token,
    required String platform,
  }) async {
    saved.add((token, platform));
    return const Result.ok(null);
  }
}

AuthenticatedUser _principal() =>
    const AuthenticatedUser(userId: UserId(_user), role: PlatformRole.user);

/// A browser registers its push token like a phone (phase 3 of the plan:
/// the iPhone players use the web build); anything else is refused.
void main() {
  test('a browser token is kept as web', () async {
    final tokens = _Tokens();

    final result = await RegisterDeviceToken(deviceTokens: tokens)(
      principal: _principal(),
      token: 'web-token',
      platform: 'web',
    );

    expect(result.isOk, isTrue);
    expect(tokens.saved, [('web-token', 'web')]);
  });

  test('android and ios are kept as before', () async {
    final tokens = _Tokens();
    final useCase = RegisterDeviceToken(deviceTokens: tokens);

    await useCase(principal: _principal(), token: 'a', platform: 'android');
    await useCase(principal: _principal(), token: 'i', platform: 'ios');

    expect(tokens.saved, [('a', 'android'), ('i', 'ios')]);
  });

  test('an unknown platform is refused before any write', () async {
    final tokens = _Tokens();

    final result = await RegisterDeviceToken(deviceTokens: tokens)(
      principal: _principal(),
      token: 't',
      platform: 'windows',
    );

    expect(
      (result as Err<void>).error.code,
      'notification.device_token_platform_unsupported',
    );
    expect(tokens.saved, isEmpty);
  });
}
