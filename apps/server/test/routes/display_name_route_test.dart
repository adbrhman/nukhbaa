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

  @override
  Future<Result<User?>> findUser(UserId id) async => Result.ok(current);

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
        body: jsonEncode({'display_name': 'Ali'}),
      );

      final response = await route.onRequest(context);

      expect(response.statusCode, HttpStatus.ok);
      final user = (await _decode(response))['user']! as Map<Object?, Object?>;
      expect(user['display_name'], 'Ali');
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

    test('rejects non-PUT methods with 405', () async {
      final directory = _Directory(_user('n72914939'));
      final context = _wire(directory, method: HttpMethod.post);

      final response = await route.onRequest(context);

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
