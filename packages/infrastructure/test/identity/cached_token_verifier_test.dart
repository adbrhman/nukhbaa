import 'package:application/application.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:domain/domain.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _secret = 'legacy-shared-secret-for-tests-only';
const _ref = 'abcdefghijklmnop';
const _issuer = 'https://$_ref.supabase.co/auth/v1';
const _u1 = '11111111-2222-3333-4444-555555555555';
const _u2 = '66666666-7777-8888-9999-000000000000';

AuthConfig _config() {
  final result = AuthConfig.fromEnv({
    'NUKHBA_SUPABASE_PROJECT_REF': _ref,
    'NUKHBA_SUPABASE_JWT_AUD': 'authenticated',
    'NUKHBA_SUPABASE_JWT_SECRET': _secret,
  });
  return (result as Ok<AuthConfig>).value;
}

String _sign({
  String subject = _u1,
  Duration? expiresIn = const Duration(minutes: 5),
  String secret = _secret,
}) {
  final jwt = JWT(
    {'sub': subject, 'role': 'authenticated', 'email': 'a@example.com'},
    issuer: _issuer,
    audience: Audience.one('authenticated'),
    subject: subject,
  );
  return jwt.sign(
    SecretKey(secret),
    algorithm: JWTAlgorithm.HS256,
    expiresIn: expiresIn,
  );
}

/// The real verifier the composition root wraps, counted.
final class _CountingVerifier implements TokenVerifier {
  _CountingVerifier()
    : _inner = SupabaseJwtVerifier(
        _config(),
        JwksClient(
          Uri.parse('https://$_ref.supabase.co/auth/v1/jwks'),
          httpClient: MockClient(
            (_) async => http.Response('should not be called', 500),
          ),
        ),
      );

  final TokenVerifier _inner;
  int calls = 0;

  @override
  Future<Result<AuthenticatedUser>> verify(String bearerToken) {
    calls++;
    return _inner.verify(bearerToken);
  }
}

void main() {
  late _CountingVerifier inner;
  late DateTime clock;
  late AuthenticateRequest authenticate;

  void wire({Duration maxAge = const Duration(minutes: 5)}) {
    authenticate = AuthenticateRequest(
      CachedTokenVerifier(inner, maxAge: maxAge, now: () => clock),
    );
  }

  setUp(() {
    inner = _CountingVerifier();
    clock = DateTime.now();
    wire();
  });

  String idOf(Result<AuthenticatedUser> result) =>
      (result as Ok<AuthenticatedUser>).value.userId.value;

  String codeOf(Result<AuthenticatedUser> result) =>
      (result as Err<AuthenticatedUser>).error.code;

  test('a repeat of the same token is verified once', () async {
    final token = _sign();

    final first = await authenticate('Bearer $token');
    final second = await authenticate('Bearer $token');

    expect(idOf(first), _u1);
    expect(idOf(second), _u1);
    expect(inner.calls, 1);
  });

  test('a held token is never answered from memory from its exp on', () async {
    wire(maxAge: const Duration(hours: 1));
    final token = _sign(expiresIn: const Duration(minutes: 2));

    await authenticate('Bearer $token');
    clock = clock.add(const Duration(minutes: 3));
    await authenticate('Bearer $token');

    expect(inner.calls, 2);
  });

  test('a long-lived token is verified again after maxAge', () async {
    final token = _sign(expiresIn: const Duration(hours: 1));

    await authenticate('Bearer $token');
    clock = clock.add(const Duration(minutes: 6));
    final again = await authenticate('Bearer $token');

    expect(idOf(again), _u1);
    expect(inner.calls, 2);
  });

  test('an expired token is refused every time, never held', () async {
    final token = _sign(expiresIn: const Duration(seconds: -1));

    final first = await authenticate('Bearer $token');
    final second = await authenticate('Bearer $token');

    expect(codeOf(first), 'auth.token_expired');
    expect(codeOf(second), 'auth.token_expired');
    expect(inner.calls, 2);
  });

  test('a forged token is refused every time, never held', () async {
    final token = _sign(secret: 'not-the-project-secret-at-all-xxxxx');

    final first = await authenticate('Bearer $token');
    final second = await authenticate('Bearer $token');

    expect(codeOf(first), 'auth.token_invalid');
    expect(codeOf(second), 'auth.token_invalid');
    expect(inner.calls, 2);
  });

  test('a token without exp is never held', () async {
    final token = _sign(expiresIn: null);

    await authenticate('Bearer $token');
    await authenticate('Bearer $token');

    expect(inner.calls, 2);
  });

  test('two players keep their own principals', () async {
    final one = _sign();
    final two = _sign(subject: _u2);

    await authenticate('Bearer $one');
    await authenticate('Bearer $two');
    final oneAgain = await authenticate('Bearer $one');
    final twoAgain = await authenticate('Bearer $two');

    expect(idOf(oneAgain), _u1);
    expect(idOf(twoAgain), _u2);
    expect(inner.calls, 2);
  });
}
