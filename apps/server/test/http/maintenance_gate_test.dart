import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server/http/maintenance_gate.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// `ops.app_mode` in memory.
final class _Store implements AppModeStore {
  AppMode mode = AppMode.normal;
  bool fails = false;
  int reads = 0;

  @override
  Future<Result<AppModeState>> read() async {
    reads++;
    if (fails) return const Result.err(AppError.transient('db.down', 'down'));
    return Result.ok(
      AppModeState(mode: mode, changedAt: DateTime.utc(2026, 11, 20)),
    );
  }

  @override
  Future<Result<void>> set({
    required AppMode mode,
    required String reason,
    required UserId by,
  }) async => const Result.ok(null);
}

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

const AuthenticatedUser _player = AuthenticatedUser(
  userId: UserId('11111111-2222-4333-8444-555555555555'),
  role: PlatformRole.user,
);
const AuthenticatedUser _admin = AuthenticatedUser(
  userId: UserId('66666666-7777-4888-8999-000000000000'),
  role: PlatformRole.admin,
);

// NK292_11
/// Script 292: the app's mode before every request, as the root middleware
/// runs it.
void main() {
  group('maintenanceRefusal', () {
    AppError? refusal(AppMode mode, String path, HttpMethod method) =>
        maintenanceRefusal(mode: mode, path: path, method: method);

    test('normal refuses nothing', () {
      expect(
        refusal(
          AppMode.normal,
          '/seasons/s/fixtures/f/prediction',
          HttpMethod.post,
        ),
        isNull,
      );
    });

    test('read only: reads pass, the players\' writes are refused', () {
      const String predict = '/seasons/s/fixtures/f/prediction';
      expect(refusal(AppMode.readOnly, predict, HttpMethod.get), isNull);
      expect(
        refusal(AppMode.readOnly, predict, HttpMethod.post)!.code,
        'app.read_only',
      );
      for (final String path in <String>[
        '/me/h2h-league/chat',
        '/groups',
        '/groups/g/members',
        '/me/display-name',
        '/me/avatar',
        '/me/favorite-teams',
      ]) {
        expect(
          refusal(AppMode.readOnly, path, HttpMethod.post),
          isNotNull,
          reason: path,
        );
      }
      for (final String path in <String>[
        '/auth/login',
        '/me/device-token',
        '/me/account',
        '/me/support/messages',
        '/notifications/n1/read',
        '/errors/report',
        '/admin/fixtures',
        '/owner/mode',
        '/health',
      ]) {
        expect(
          refusal(AppMode.readOnly, path, HttpMethod.post),
          isNull,
          reason: path,
        );
      }
      expect(
        refusal(AppMode.readOnly, '/me/account', HttpMethod.delete),
        isNull,
      );
    });

    test('closed: only signing in, deleting an account and the admins', () {
      expect(
        refusal(AppMode.closed, '/seasons/s/leaderboard', HttpMethod.get)!.code,
        'app.closed',
      );
      expect(refusal(AppMode.closed, '/me', HttpMethod.get), isNotNull);
      expect(refusal(AppMode.closed, '/auth/login', HttpMethod.post), isNull);
      expect(refusal(AppMode.closed, '/me/account', HttpMethod.delete), isNull);
      expect(refusal(AppMode.closed, '/admin/users', HttpMethod.get), isNull);
      expect(
        refusal(AppMode.closed, '/app/latest-build', HttpMethod.get),
        isNull,
      );
    });
  });

  group('AppModeCache', () {
    test('reads at most every ten seconds; forget reads again', () async {
      final _Store store = _Store();
      DateTime now = DateTime.utc(2026, 11, 20, 12);
      final AppModeCache cache = AppModeCache(store, now: () => now);

      expect(await cache.current(), AppMode.normal);
      store.mode = AppMode.closed;
      expect(await cache.current(), AppMode.normal, reason: 'kept');
      now = now.add(const Duration(seconds: 11));
      expect(await cache.current(), AppMode.closed);
      store.mode = AppMode.readOnly;
      cache.forget();
      expect(await cache.current(), AppMode.readOnly);
      expect(store.reads, 3);
    });

    test('a failed read counts as normal', () async {
      final _Store store = _Store()
        ..mode = AppMode.closed
        ..fails = true;

      expect(await AppModeCache(store).current(), AppMode.normal);
    });
  });

  group('maintenanceGate', () {
    late _Store store;
    late List<String> reached;

    setUp(() {
      store = _Store();
      reached = [];
    });

    Future<Response> call({
      required AuthenticatedUser? who,
      HttpMethod method = HttpMethod.post,
      String path = '/seasons/s/fixtures/f/prediction',
      bool wired = true,
    }) async {
      final request = _MockRequest();
      when(() => request.method).thenReturn(method);
      when(() => request.uri).thenReturn(Uri.parse('http://localhost$path'));
      when(
        () => request.headers,
      ).thenReturn({HttpHeaders.authorizationHeader: 'Bearer token'});
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(request);
      final Handler handler =
          maintenanceGate(
            cache: () async => wired ? AppModeCache(store) : null,
            authenticate: (header) async => who == null
                ? const Result.err(AppError.authorization('auth.x', 'no'))
                : Result.ok(who),
          )((_) {
            reached.add(path);
            return Response(body: 'route');
          });
      return handler(context);
    }

    test('normal: the route answers', () async {
      final Response response = await call(who: _player);

      expect(await response.body(), 'route');
    });

    test(
      'read only: a player reads the Arabic message, nothing reached',
      () async {
        store.mode = AppMode.readOnly;

        final Response response = await call(who: _player);

        expect(response.statusCode, HttpStatus.conflict);
        expect(await response.body(), contains(readOnlyMessage));
        expect(reached, isEmpty);
      },
    );

    test('closed: no token is refused too', () async {
      store.mode = AppMode.closed;

      final Response response = await call(
        who: null,
        method: HttpMethod.get,
        path: '/me',
      );

      expect(response.statusCode, HttpStatus.conflict);
      expect(await response.body(), contains('app.closed'));
    });

    test('an admin passes, to test', () async {
      store.mode = AppMode.closed;

      final Response response = await call(who: _admin);

      expect(await response.body(), 'route');
    });

    test('no mode wired refuses nothing', () async {
      store.mode = AppMode.closed;

      final Response response = await call(who: _player, wired: false);

      expect(await response.body(), 'route');
      expect(store.reads, 0);
    });
  });
}
