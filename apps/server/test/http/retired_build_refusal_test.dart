/// Script 149: while an admin holds a minimum, a player whose app is older
/// than the head-to-head tab -- a request naming no build -- is answered
/// with the update message; every other player and every build that names
/// itself is served. Through the real [bearerAuth] and a root wired as the
/// composition root wires it: one [CachedAppUpdatePolicyStore] behind the
/// admin's [SetMinSupportedBuild] and [RefuseRetiredBuild], over a
/// [CachedRetiredBuildReader]; only the database rows are faked.
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

/// The one row of `ops.app_update_policy`.
final class _PolicyRow implements AppUpdatePolicyStore {
  int? value;

  @override
  Future<Result<int?>> minSupportedBuild() async => Result.ok(value);

  @override
  Future<Result<int?>> setMinSupportedBuild({
    required int? buildNumber,
    required UserId by,
  }) async {
    value = buildNumber;
    return Result.ok(value);
  }
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

final class _Releases implements BuildInfoRepository {
  @override
  Future<Result<LatestBuild>> fetchLatest() async => Result.ok(
    LatestBuild(
      publishedAt: DateTime.utc(2026, 10, 26),
      apkUrl: 'https://github.com/x/y/releases/download/build-abc/a.apk',
      buildNumber: 800,
    ),
  );
}

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

const AuthenticatedUser _admin = AuthenticatedUser(
  userId: UserId('00000000-0000-4000-8000-0000000000ad'),
  role: PlatformRole.admin,
);

void main() {
  setUpAll(() {
    registerFallbackValue(_admin);
  });

  late SetMinSupportedBuild setMinimum;
  late _Sessions sessions;
  late Future<CompositionRoot> root;

  setUp(() {
    final store = CachedAppUpdatePolicyStore(_PolicyRow());
    sessions = _Sessions();
    setMinimum = SetMinSupportedBuild(policy: store, builds: _Releases());
    root = Future<CompositionRoot>.value(
      CompositionRoot.forTesting(
        authenticateRequest: AuthenticateRequest(_Verifier()),
        refuseRetiredBuild: RefuseRetiredBuild(
          policy: store,
          players: CachedRetiredBuildReader(sessions),
        ),
      ),
    );
  });

  Future<Response> call(String user, [Map<String, String> extra = const {}]) {
    final request = _MockRequest();
    when(
      () => request.headers,
    ).thenReturn({HttpHeaders.authorizationHeader: 'Bearer $user', ...extra});
    when(() => request.method).thenReturn(HttpMethod.get);
    final downstream = _MockRequestContext();
    final context = _MockRequestContext();
    when(() => context.request).thenReturn(request);
    when(() => context.read<Future<CompositionRoot>>()).thenAnswer((_) => root);
    when(
      () => context.provide<AuthenticatedUser>(any()),
    ).thenReturn(downstream);
    return Future<Response>.value(
      bearerAuth()((_) => Response(body: 'served'))(context),
    );
  }

  test('no minimum: the retired build is served like every other', () async {
    expect((await call(_retired)).statusCode, HttpStatus.ok);
    expect(sessions.reads, 0);
  });

  test('a minimum held: the player on a retired build reads the update '
      'message; another player with an old app is served', () async {
    await setMinimum(principal: _admin, toLatest: true);

    final Response refused = await call(_retired);
    expect(refused.statusCode, HttpStatus.conflict);
    final ErrorResponseDto body = ErrorResponseDto.fromJson(
      jsonDecode(await refused.body()) as Map<String, Object?>,
    );
    expect(body.code, 'app.update_required');
    expect(body.message, oldBuildMessage);

    expect((await call(_other)).statusCode, HttpStatus.ok);
  });

  test('the same player on a build that names itself, or on the web, is '
      'served', () async {
    await setMinimum(principal: _admin, toLatest: true);

    expect(
      (await call(_retired, {appBuildHeader: '772'})).statusCode,
      HttpStatus.ok,
    );
    expect(
      (await call(_retired, {'origin': 'https://nukhbaa.app'})).statusCode,
      HttpStatus.ok,
    );
  });

  test('clearing the minimum serves the retired build again', () async {
    await setMinimum(principal: _admin, toLatest: true);
    expect((await call(_retired)).statusCode, HttpStatus.conflict);

    await setMinimum(principal: _admin, toLatest: false);
    expect((await call(_retired)).statusCode, HttpStatus.ok);
  });
}
