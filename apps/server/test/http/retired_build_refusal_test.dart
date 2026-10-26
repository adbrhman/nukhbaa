/// Scripts 149-150: while `NUKHBA_REFUSE_RETIRED_BUILDS` is on, a player
/// whose app is older than the head-to-head tab -- a request naming no
/// build -- is answered with the update message; every other player and
/// every build that names itself is served, and the dashboard's minimum
/// plays no part. Through the real [bearerAuth] and a root wired as the
/// composition root wires it: [RefuseRetiredBuild] over a
/// [CachedRetiredBuildReader]; only the sessions are faked.
library;

import 'dart:convert';
import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/bearer_auth.dart';
import 'package:server/http/build_gate.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const String _retired = '00000000-0149-4000-8149-000000000001';
const String _other = '00000000-0149-4000-8149-000000000002';

final class _Verifier implements TokenVerifier {
  @override
  Future<Result<AuthenticatedUser>> verify(String bearerToken) async =>
      Result.ok(
        AuthenticatedUser(userId: UserId(bearerToken), role: PlatformRole.user),
      );
}

/// The sessions' verdict: [_retired] is on a build from before the tab.
final class _Sessions implements RetiredBuildReader {
  int reads = 0;

  @override
  Future<Result<Set<UserId>>> playersOnBuildsBefore(DateTime before) async {
    reads++;
    return Result.ok(<UserId>{const UserId(_retired)});
  }
}

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

Future<CompositionRoot> _root({required bool enabled, _Sessions? sessions}) =>
    Future<CompositionRoot>.value(
      CompositionRoot.forTesting(
        authenticateRequest: AuthenticateRequest(_Verifier()),
        refuseRetiredBuild: RefuseRetiredBuild(
          enabled: enabled,
          players: CachedRetiredBuildReader(sessions ?? _Sessions()),
        ),
      ),
    );

Future<Response> _call(
  Future<CompositionRoot> root,
  String user, [
  Map<String, String> extra = const {},
]) async {
  final request = _MockRequest();
  when(
    () => request.headers,
  ).thenReturn({HttpHeaders.authorizationHeader: 'Bearer $user', ...extra});
  when(() => request.method).thenReturn(HttpMethod.get);
  final downstream = _MockRequestContext();
  final context = _MockRequestContext();
  when(() => context.request).thenReturn(request);
  when(() => context.read<Future<CompositionRoot>>()).thenAnswer((_) => root);
  when(() => context.provide<AuthenticatedUser>(any())).thenReturn(downstream);
  return bearerAuth()((_) => Response(body: 'served'))(context);
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const AuthenticatedUser(userId: UserId(_other), role: PlatformRole.user),
    );
  });

  test('switched off: the retired build is served like every other, and the '
      'sessions are not read', () async {
    final sessions = _Sessions();
    final root = _root(enabled: false, sessions: sessions);

    expect((await _call(root, _retired)).statusCode, HttpStatus.ok);
    expect(sessions.reads, 0);
  });

  test('switched on: the player on a retired build reads the update message; '
      'another player with an old app is served', () async {
    final root = _root(enabled: true);

    final Response refused = await _call(root, _retired);
    expect(refused.statusCode, HttpStatus.conflict);
    final ErrorResponseDto body = ErrorResponseDto.fromJson(
      jsonDecode(await refused.body()) as Map<String, Object?>,
    );
    expect(body.code, 'app.update_required');
    expect(body.message, retiredBuildMessage);
    // The one way those builds have (script 151): the landing page and its
    // button; their sign-in screen has no update row.
    expect(body.message, contains('nukhbaa.app'));
    expect(body.message, contains('«حمّل التطبيق لأندرويد»'));
    expect(body.message, isNot(contains('تسجيل الدخول بحساب آخر')));
    expect(body.message, isNot(contains('يتوفر تحديث جديد')));

    expect((await _call(root, _other)).statusCode, HttpStatus.ok);
  });

  test('switched on: the same player on a build that names itself, or on the '
      'web, is served', () async {
    final root = _root(enabled: true);

    expect(
      (await _call(root, _retired, {appBuildHeader: '772'})).statusCode,
      HttpStatus.ok,
    );
    expect(
      (await _call(root, _retired, {
        'origin': 'https://nukhbaa.app',
      })).statusCode,
      HttpStatus.ok,
    );
  });

  test('the sessions are read once for many requests', () async {
    final sessions = _Sessions();
    final root = _root(enabled: true, sessions: sessions);

    for (var i = 0; i < 5; i++) {
      await _call(root, _retired);
      await _call(root, _other);
    }
    expect(sessions.reads, 1);
  });
}
