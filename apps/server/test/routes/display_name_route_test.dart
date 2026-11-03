import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/me/display-name/index.dart' as route;

const _id = UserId('aaaaaaaa-0000-0000-0000-000000000001');

User _user(String displayName) => User(
  id: _id,
  email: 'n72914939@gmail.com',
  role: PlatformRole.user,
  status: UserStatus.active,
  displayName: displayName,
);

final class _Directory implements UserDirectory {
  _Directory(this.current);

  User current;

  /// Set by a test: every read waits until this many reads have
  /// arrived, so concurrent requests all read the name before either
  /// writes (audit 33).
  int readersToWaitFor = 0;
  int _reads = 0;
  final Completer<void> _allRead = Completer<void>();

  @override
  Future<Result<User?>> findUser(UserId id) async {
    final User seen = current;
    _reads++;
    if (_reads >= readersToWaitFor && !_allRead.isCompleted) {
      _allRead.complete();
    }
    await _allRead.future;
    return Result.ok(seen);
  }

  @override
  Future<Result<User?>> replaceDisplayName(
    UserId userId, {
    required String expected,
    required String displayName,
  }) async {
    // As the conditional UPDATE: no row once the stored name moved on.
    if (current.displayName != expected) {
      return const Result.ok(null);
    }
    return updateDisplayName(userId, displayName);
  }

  @override
  Future<Result<User>> updateDisplayName(
    UserId userId,
    String displayName,
  ) async {
    current = _user(displayName);
    return Result.ok(current);
  }

  @override
  Future<Result<User>> ensureUser(AuthenticatedUser principal) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> updateUtcOffsetMinutes(UserId userId, int minutes) =>
      throw UnimplementedError();

  @override
  Future<Result<User>> setAvatar(UserId userId, List<int> bytes, String mime) =>
      throw UnimplementedError();

  @override
  Future<Result<User>> clearAvatar(UserId userId) => throw UnimplementedError();

  @override
  Future<Result<StoredAvatar?>> readAvatar(UserId userId) =>
      throw UnimplementedError();
}

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

_MockRequestContext _wire(
  _Directory directory, {
  HttpMethod method = HttpMethod.put,
  String body = '',
}) {
  final root = Future<CompositionRoot>.value(
    CompositionRoot.forTesting(
      updateDisplayName: UpdateDisplayName(userDirectory: directory),
    ),
  );
  final request = _MockRequest();
  when(() => request.method).thenReturn(method);
  when(request.body).thenAnswer((_) async => body);
  when(
    request.bytes,
  ).thenAnswer((_) => Stream<List<int>>.value(utf8.encode(body)));
  final context = _MockRequestContext();
  when(() => context.request).thenReturn(request);
  when(() => context.read<Future<CompositionRoot>>()).thenAnswer((_) => root);
  when(
    () => context.read<AuthenticatedUser>(),
  ).thenReturn(const AuthenticatedUser(userId: _id, role: PlatformRole.user));
  return context;
}

Future<Map<String, Object?>> _decode(Response response) async {
  final decoded = await response.json() as Map<Object?, Object?>;
  return decoded.cast<String, Object?>();
}

void main() {
  group('PUT /me/display-name', () {
    test('an account with the automatic name chooses its name', () async {
      final directory = _Directory(_user('n72914939'));
      final context = _wire(
        directory,
        body: jsonEncode({'display_name': 'Ali Hassan'}),
      );

      final response = await route.onRequest(context);

      expect(response.statusCode, HttpStatus.ok);
      final user = (await _decode(response))['user']! as Map<Object?, Object?>;
      expect(user['display_name'], 'Ali Hassan');
    });

    // Decided 2026-11-02: a new account's name is two-part.
    test('a one-word name is refused and the automatic name stays', () async {
      final directory = _Directory(_user('n72914939'));
      final context = _wire(
        directory,
        body: jsonEncode({'display_name': 'Ali'}),
      );

      final response = await route.onRequest(context);

      expect(response.statusCode, HttpStatus.badRequest);
      expect(
        (await _decode(response))['code'],
        'identity.display_name_not_two_part',
      );
      expect(directory.current.displayName, 'n72914939');
    });

    test('a chosen name cannot be changed', () async {
      final directory = _Directory(_user('Ali'));
      final context = _wire(
        directory,
        body: jsonEncode({'display_name': 'Omar'}),
      );

      final response = await route.onRequest(context);

      expect(response.statusCode, isNot(HttpStatus.ok));
      expect(
        (await _decode(response))['code'],
        'identity.display_name_immutable',
      );
      expect(directory.current.displayName, 'Ali');
    });

    // Audit 33: two requests that both read the automatic name. Only the
    // first choice is kept; the second is refused as immutable.
    test(
      'two choices at once: the first is kept, the second refused',
      () async {
        final directory = _Directory(_user('n72914939'))..readersToWaitFor = 2;

        final List<Response> responses = await Future.wait(<Future<Response>>[
          route.onRequest(
            _wire(directory, body: jsonEncode({'display_name': 'Ali Hassan'})),
          ),
          route.onRequest(
            _wire(directory, body: jsonEncode({'display_name': 'Omar Saleh'})),
          ),
        ]);

        final List<Response> kept = responses
            .where((Response r) => r.statusCode == HttpStatus.ok)
            .toList();
        final List<Response> refused = responses
            .where((Response r) => r.statusCode != HttpStatus.ok)
            .toList();
        expect(kept, hasLength(1));
        expect(refused, hasLength(1));
        expect(
          (await _decode(refused.single))['code'],
          'identity.display_name_immutable',
        );
        final user =
            (await _decode(kept.single))['user']! as Map<Object?, Object?>;
        expect(directory.current.displayName, user['display_name']);
      },
    );

    test('rejects non-PUT methods with 405', () async {
      final directory = _Directory(_user('n72914939'));
      final context = _wire(directory, method: HttpMethod.post);

      final response = await route.onRequest(context);

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
