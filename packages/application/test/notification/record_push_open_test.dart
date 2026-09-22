import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _user = '11111111-2222-3333-4444-555555555555';

final class _FixedClock implements Clock {
  const _FixedClock(this.now);

  final DateTime now;

  @override
  DateTime nowUtc() => now;
}

final class _FakeOpens implements PushOpenRepository {
  final List<(String, String, DateTime)> rows = [];

  @override
  Future<Result<void>> record({
    required UserId userId,
    required String link,
    required DateTime openedAt,
  }) async {
    rows.add((userId.value, link, openedAt));
    return const Result.ok(null);
  }
}

const _principal = AuthenticatedUser(
  userId: UserId(_user),
  role: PlatformRole.user,
  email: 'a@example.com',
  displayName: 'Human',
);

void main() {
  final now = DateTime.utc(2026, 9, 23, 12);

  test('a known link is recorded against the caller', () async {
    final opens = _FakeOpens();

    final result = await RecordPushOpen(opens: opens, clock: _FixedClock(now))(
      principal: _principal,
      link: PushLink.league,
    );

    expect(result.isOk, isTrue);
    expect(opens.rows, [(_user, 'league', now)]);
  });

  test('an unknown link is refused and nothing is written', () async {
    final opens = _FakeOpens();

    final result = await RecordPushOpen(opens: opens, clock: _FixedClock(now))(
      principal: _principal,
      link: 'elsewhere',
    );

    expect((result as Err<void>).error.code, 'notification.unknown_link');
    expect(opens.rows, isEmpty);
  });
}
