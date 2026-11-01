import 'dart:convert';
import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/auth/password-reset/update/index.dart' as update_route;

/// The server's clock in every test.
final DateTime _now = DateTime.utc(2026, 11, 1, 18);

/// The `timestamp` of an `amr` entry proven [ago] before [_now].
int _at(Duration ago) => _now.subtract(ago).millisecondsSinceEpoch ~/ 1000;

/// A token shaped as GoTrue signs it, carrying [amr]. Its signature is never
/// checked here: GoTrue checks it on PUT /user, which is mocked.
String _token(List<Map<String, Object?>> amr) {
  String part(Object json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'ES256', 'typ': 'JWT'})}.'
      '${part({'sub': '11111111-1111-1111-1111-111111111111', 'amr': amr})}.'
      'c2lnbmF0dXJl';
}

AuthConfig _config() =>
    (AuthConfig.fromEnv({
              'NUKHBA_SUPABASE_PROJECT_REF': 'abcdefghijklmnop',
              'NUKHBA_SUPABASE_ANON_KEY': 'sb_publishable_abc123DEF456',
            })
            as Ok<AuthConfig>)
        .value;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

/// The route over the real use-case, gateway and client, GoTrue answering
/// 200 to whatever reaches it; [sent] holds every call that did.
({_MockRequestContext context, List<http.Request> sent}) _wire(String token) {
  final sent = <http.Request>[];
  final client = SupabaseAuthClient(
    config: _config(),
    httpClient: MockClient((request) async {
      sent.add(request);
      return http.Response(
        '{}',
        200,
        headers: const {'content-type': 'application/json'},
      );
    }),
    clock: () => _now,
  );
  final root = Future<CompositionRoot>.value(
    CompositionRoot.forTesting(
      updatePassword: UpdatePassword(SupabaseAuthGateway(client)),
    ),
  );
  final encoded = jsonEncode({'password': 'a-new-password-1'});
  final request = _MockRequest();
  when(() => request.method).thenReturn(HttpMethod.post);
  when(() => request.headers).thenReturn({'authorization': 'Bearer $token'});
  when(request.body).thenAnswer((_) async => encoded);
  when(
    request.bytes,
  ).thenAnswer((_) => Stream<List<int>>.value(utf8.encode(encoded)));
  final context = _MockRequestContext();
  when(() => context.request).thenReturn(request);
  when(() => context.read<Future<CompositionRoot>>()).thenAnswer((_) => root);
  return (context: context, sent: sent);
}

Future<Map<Object?, Object?>> _body(Response response) async =>
    await response.json() as Map<Object?, Object?>;

void main() {
  test('the session of a reset code (otp) sets the new password', () async {
    final token = _token([
      {'method': 'otp', 'timestamp': _at(const Duration(minutes: 2))},
    ]);
    final wired = _wire(token);

    final response = await update_route.onRequest(wired.context);

    expect(response.statusCode, HttpStatus.ok);
    final put = wired.sent.single;
    expect(put.method, 'PUT');
    expect(put.url.path, endsWith('/user'));
    expect(put.headers['authorization'], 'Bearer $token');
    expect(jsonDecode(put.body), {'password': 'a-new-password-1'});
  });

  test(
    'the session of a reset link (recovery) sets the new password',
    () async {
      final wired = _wire(
        _token([
          {'method': 'recovery', 'timestamp': _at(const Duration(minutes: 30))},
        ]),
      );

      final response = await update_route.onRequest(wired.context);

      expect(response.statusCode, HttpStatus.ok);
      expect(wired.sent, hasLength(1));
    },
  );

  test('a signed-in password session never sets a password', () async {
    final wired = _wire(
      _token([
        {'method': 'password', 'timestamp': _at(const Duration(minutes: 1))},
      ]),
    );

    final response = await update_route.onRequest(wired.context);

    expect(response.statusCode, HttpStatus.badRequest);
    expect((await _body(response))['code'], 'auth.recovery_required');
    expect(wired.sent, isEmpty, reason: 'nothing reaches GoTrue');
  });

  test('a Google session, refreshed, never sets a password', () async {
    final wired = _wire(
      _token([
        {'method': 'oauth', 'timestamp': _at(const Duration(days: 3))},
        {'method': 'token_refresh', 'timestamp': _at(Duration.zero)},
      ]),
    );

    final response = await update_route.onRequest(wired.context);

    expect(response.statusCode, HttpStatus.badRequest);
    expect((await _body(response))['code'], 'auth.recovery_required');
    expect(wired.sent, isEmpty);
  });

  test('a recovery proven more than an hour ago is refused', () async {
    final wired = _wire(
      _token([
        {'method': 'otp', 'timestamp': _at(const Duration(minutes: 61))},
      ]),
    );

    final response = await update_route.onRequest(wired.context);

    expect(response.statusCode, HttpStatus.badRequest);
    expect((await _body(response))['code'], 'auth.recovery_required');
    expect(wired.sent, isEmpty);
  });

  test('a token that is not a JWT never reaches GoTrue', () async {
    final wired = _wire('not-a-jwt');

    final response = await update_route.onRequest(wired.context);

    expect(response.statusCode, HttpStatus.badRequest);
    expect((await _body(response))['code'], 'auth.recovery_required');
    expect(wired.sent, isEmpty);
  });
}
