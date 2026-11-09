import 'dart:convert';
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

const User _user = User(
  id: UserId(_uuid),
  email: 'a@example.com',
  displayName: 'Human',
  role: PlatformRole.user,
  status: UserStatus.active,
);

/// Creates the account row on first sight; counts how often it was asked,
/// because a refused third account must not reach it.
final class _Directory implements UserDirectory {
  int ensured = 0;

  @override
  Future<Result<User>> ensureUser(AuthenticatedUser principal) async {
    ensured++;
    return const Result.ok(_user);
  }

  @override
  Future<Result<User?>> replaceDisplayName(
    UserId userId, {
    required String expected,
    required String displayName,
  }) => throw UnimplementedError();

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
  final List<(String, String)> recorded = <(String, String)>[];

  @override
  Future<Result<void>> record({
    required String installId,
    required UserId userId,
  }) async {
    recorded.add((installId, userId.value));
    return const Result.ok(null);
  }

  @override
  Future<Result<List<SharedDeviceGroup>>> sharedDevices({required int limit}) =>
      throw UnimplementedError();
}

final class _Gate implements InstallAccountGate {
  _Gate(this.answer);

  final Result<bool> answer;
  int asked = 0;

  @override
  Future<Result<bool>> admits({
    required String installId,
    required UserId userId,
    required int limit,
  }) async {
    asked++;
    return answer;
  }
}

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

_MockRequestContext _wire({
  required _Directory directory,
  required _Sightings sightings,
  required _Gate gate,
  required Map<String, String> headers,
}) {
  final root = Future<CompositionRoot>.value(
    CompositionRoot.forTesting(
      getCurrentUser: GetCurrentUser(directory),
      recordDeviceSighting: RecordDeviceSighting(
        sightings: sightings,
        gate: gate,
      ),
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

/// Script 245: a third account on one phone is refused at `GET /me`, before
/// its row, its enrolment or its sighting is written.
void main() {
  test('a third account is refused and nothing is written for it', () async {
    final directory = _Directory();
    final sightings = _Sightings();

    final response = await route.onRequest(
      _wire(
        directory: directory,
        sightings: sightings,
        gate: _Gate(const Result.ok(false)),
        headers: {appInstallHeader: _phone},
      ),
    );

    expect(response.statusCode, HttpStatus.conflict);
    final body = jsonDecode(await response.body()) as Map<String, Object?>;
    expect(body['code'], 'device.account_limit');
    expect(directory.ensured, 0);
    expect(sightings.recorded, isEmpty);
  });

  test('an account that is admitted is answered and recorded', () async {
    final directory = _Directory();
    final sightings = _Sightings();

    final response = await route.onRequest(
      _wire(
        directory: directory,
        sightings: sightings,
        gate: _Gate(const Result.ok(true)),
        headers: {appInstallHeader: _phone},
      ),
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(sightings.recorded, [(_phone, _uuid)]);
  });

  test('no install header asks nothing and answers as before', () async {
    final gate = _Gate(const Result.ok(false));

    final response = await route.onRequest(
      _wire(
        directory: _Directory(),
        sightings: _Sightings(),
        gate: gate,
        headers: const {},
      ),
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(gate.asked, 0);
  });

  test('a failed check never refuses a player', () async {
    final response = await route.onRequest(
      _wire(
        directory: _Directory(),
        sightings: _Sightings(),
        gate: _Gate(const Result.err(AppError.transient('db.down', 'down'))),
        headers: {appInstallHeader: _phone},
      ),
    );

    expect(response.statusCode, HttpStatus.ok);
  });
}
