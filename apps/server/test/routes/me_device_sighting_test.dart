import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/me/index.dart' as route;

const _uuid = '11111111-2222-3333-4444-555555555555';
const _phone = '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';

final class _Directory implements UserDirectory {
  _Directory(this._response);
  final Result<User> _response;

  @override
  Future<Result<User>> ensureUser(AuthenticatedUser principal) async =>
      _response;

  @override
  Future<Result<User>> updateDisplayName(UserId userId, String displayName) =>
      throw UnimplementedError();

  @override
  Future<Result<User>> setAvatar(UserId userId, List<int> bytes, String mime) =>
      throw UnimplementedError();

  @override
  Future<Result<User>> clearAvatar(UserId userId) => throw UnimplementedError();

  @override
  Future<Result<StoredAvatar?>> readAvatar(UserId userId) =>
      throw UnimplementedError();

  @override
  Future<Result<void>> updateUtcOffsetMinutes(UserId userId, int minutes) =>
      throw UnimplementedError();

  @override
  Future<Result<User?>> findUser(UserId id) async =>
      throw StateError('findUser not wired in this test fake');
}

final class _Sightings implements DeviceSightings {
  _Sightings({this.fail = false});

  final bool fail;
  final List<(String, String)> recorded = <(String, String)>[];

  @override
  Future<Result<void>> record({
    required String installId,
    required UserId userId,
  }) async {
    if (fail) {
      return const Result.err(AppError.transient('db.unavailable', 'down'));
    }
    recorded.add((installId, userId.value));
    return const Result.ok(null);
  }

  @override
  Future<Result<List<SharedDeviceGroup>>> sharedDevices({required int limit}) =>
      throw UnimplementedError();
}

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

const User _user = User(
  id: UserId(_uuid),
  email: 'a@example.com',
  displayName: 'Human',
  role: PlatformRole.user,
  status: UserStatus.active,
);

_MockRequestContext _wire({
  required _Sightings sightings,
  required Map<String, String> headers,
  Result<User> directory = const Result.ok(_user),
}) {
  final root = Future<CompositionRoot>.value(
    CompositionRoot.forTesting(
      getCurrentUser: GetCurrentUser(_Directory(directory)),
      recordDeviceSighting: RecordDeviceSighting(sightings: sightings),
    ),
  );
  final request = _MockRequest();
  when(() => request.method).thenReturn(HttpMethod.get);
  when(() => request.headers).thenReturn(headers);
  final context = _MockRequestContext();
  when(() => context.request).thenReturn(request);
  when(() => context.read<Future<CompositionRoot>>()).thenAnswer((_) => root);
  when(() => context.read<AuthenticatedUser>()).thenReturn(
    const AuthenticatedUser(userId: UserId(_uuid), role: PlatformRole.user),
  );
  return context;
}

/// Script 200: opening the app (`GET /me`) records the account on the
/// phone's install, so the admin sees which accounts share a phone.
void main() {
  test('the install id in the header is recorded for the caller', () async {
    final sightings = _Sightings();

    final response = await route.onRequest(
      _wire(sightings: sightings, headers: {appInstallHeader: _phone}),
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(sightings.recorded, [(_phone, _uuid)]);
  });

  test('no header records nothing and answers as before', () async {
    final sightings = _Sightings();

    final response = await route.onRequest(
      _wire(sightings: sightings, headers: const {}),
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(sightings.recorded, isEmpty);
  });

  test('a failed write never fails the answer', () async {
    final response = await route.onRequest(
      _wire(
        sightings: _Sightings(fail: true),
        headers: {appInstallHeader: _phone},
      ),
    );

    expect(response.statusCode, HttpStatus.ok);
  });

  test('a failed identity read records nothing', () async {
    final sightings = _Sightings();

    final response = await route.onRequest(
      _wire(
        sightings: sightings,
        headers: {appInstallHeader: _phone},
        directory: const Result.err(
          AppError.transient('identity.upsert_no_row', 'no row'),
        ),
      ),
    );

    expect(response.statusCode, HttpStatus.serviceUnavailable);
    expect(sightings.recorded, isEmpty);
  });
}
