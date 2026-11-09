import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fakes.dart';

final class _Sightings implements DeviceSightings {
  @override
  Future<Result<void>> record({
    required String installId,
    required UserId userId,
  }) async => const Result.ok(null);

  @override
  Future<Result<List<SharedDeviceGroup>>> sharedDevices({
    required int limit,
  }) async => const Result.ok(<SharedDeviceGroup>[]);
}

/// Answers [answer] and keeps what it was asked.
final class _Gate implements InstallAccountGate {
  _Gate(this.answer);

  final Result<bool> answer;
  final List<(String, String, int)> asked = <(String, String, int)>[];

  @override
  Future<Result<bool>> admits({
    required String installId,
    required UserId userId,
    required int limit,
  }) async {
    asked.add((installId, userId.value, limit));
    return answer;
  }
}

/// Script 245: no more than two accounts on one phone.
void main() {
  const phone = '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
  const user = '11111111-1111-4111-8111-111111111111';

  RecordDeviceSighting use(InstallAccountGate? gate) =>
      RecordDeviceSighting(sightings: _Sightings(), gate: gate);

  test('the limit is two accounts', () {
    expect(RecordDeviceSighting.maxAccountsPerPhone, 2);
  });

  test('a phone with room, or with this account on it, admits', () async {
    final gate = _Gate(const Result.ok(true));

    final result = await use(
      gate,
    ).admit(principal: userPrincipal(user), installId: phone.toUpperCase());

    expect(result, isA<Ok<void>>());
    expect(gate.asked, [(phone, user, 2)]);
  });

  test('a third account is refused in Arabic, with its own code', () async {
    final result = await use(
      _Gate(const Result.ok(false)),
    ).admit(principal: userPrincipal(user), installId: phone);

    final error = (result as Err<void>).error;
    expect(error.kind, ErrorKind.invariant);
    expect(error.code, 'device.account_limit');
    expect(error.message, contains('حسابين'));
  });

  test('no id, a malformed id or no gate asks nothing and admits', () async {
    final gate = _Gate(const Result.ok(false));

    expect(
      await use(gate).admit(principal: userPrincipal(user), installId: null),
      isA<Ok<void>>(),
    );
    expect(
      await use(gate).admit(principal: userPrincipal(user), installId: 'x'),
      isA<Ok<void>>(),
    );
    expect(
      await use(null).admit(principal: userPrincipal(user), installId: phone),
      isA<Ok<void>>(),
    );
    expect(gate.asked, isEmpty);
  });

  test('a failed check never locks a player out', () async {
    final result = await use(
      _Gate(const Result.err(AppError.transient('db.down', 'down'))),
    ).admit(principal: userPrincipal(user), installId: phone);

    expect(result, isA<Ok<void>>());
  });
}
