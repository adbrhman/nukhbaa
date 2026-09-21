import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _me = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';

const _principal = AuthenticatedUser(
  userId: UserId(_me),
  role: PlatformRole.user,
);

/// Scripted [PlayerBadgeReader]: one record, or one failure, and a log of
/// whose record was asked for.
final class _FakeReader implements PlayerBadgeReader {
  _FakeReader({this.record = PlayerBadgeRecord.none, this.failWith});

  final PlayerBadgeRecord record;
  final AppError? failWith;
  final List<UserId> asked = [];

  @override
  Future<Result<PlayerBadgeRecord>> recordOf(UserId userId) async {
    asked.add(userId);
    final failure = failWith;
    if (failure != null) {
      return Result.err(failure);
    }
    return Result.ok(record);
  }
}

List<MyBadge> _ok(Result<List<MyBadge>> result) =>
    (result as Ok<List<MyBadge>>).value;

void main() {
  group('GetMyBadges', () {
    test('lists the whole catalog, in order, for the caller only', () async {
      final reader = _FakeReader();

      final badges = _ok(
        await GetMyBadges(badges: reader)(principal: _principal),
      );

      expect([for (final b in badges) b.code], BadgeCode.values);
      expect(reader.asked, [const UserId(_me)]);
      expect(badges.every((b) => b.unlockedAt == null), isTrue);
      expect(badges.every((b) => b.current == 0), isTrue);
    });

    test('carries each grant moment and caps progress at the target', () async {
      final granted = DateTime.utc(2026, 9, 20, 8);
      final reader = _FakeReader(
        record: PlayerBadgeRecord(
          progress: const BadgeProgress(predictionsPlaced: 31, perfectDays: 3),
          unlockedAt: {
            BadgeCode.firstPrediction: granted,
            BadgeCode.predictions25: granted,
          },
        ),
      );

      final badges = _ok(
        await GetMyBadges(badges: reader)(principal: _principal),
      );
      MyBadge of(BadgeCode code) => badges.firstWhere((b) => b.code == code);

      expect(of(BadgeCode.firstPrediction).current, 1);
      expect(of(BadgeCode.firstPrediction).unlockedAt, granted);
      expect(of(BadgeCode.predictions25).current, 25);
      expect(of(BadgeCode.predictions25).target, 25);
      expect(of(BadgeCode.predictions100).current, 31);
      expect(of(BadgeCode.predictions100).target, 100);
      expect(of(BadgeCode.predictions100).unlockedAt, isNull);
      expect(of(BadgeCode.perfectDays7).current, 3);
    });

    test('an earned badge not yet granted is full but not held', () async {
      final reader = _FakeReader(
        record: const PlayerBadgeRecord(
          progress: BadgeProgress(predictionsPlaced: 1),
          unlockedAt: <BadgeCode, DateTime>{},
        ),
      );

      final badges = _ok(
        await GetMyBadges(badges: reader)(principal: _principal),
      );
      final first = badges.first;

      expect(first.code, BadgeCode.firstPrediction);
      expect(first.current, first.target);
      expect(first.unlockedAt, isNull);
    });

    test('a reader failure is returned, not swallowed', () async {
      final result = await GetMyBadges(
        badges: _FakeReader(
          failWith: const AppError.transient('db.down', 'down'),
        ),
      )(principal: _principal);

      expect((result as Err<List<MyBadge>>).error.code, 'db.down');
    });
  });
}
