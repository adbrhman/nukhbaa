import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'fakes.dart';

final class _Reader implements PlayerPointsReader {
  _Reader(this.month);

  final PlayerMonthPoints month;
  final List<(String, String)> asked = <(String, String)>[];

  @override
  Future<Result<PlayerMonthPoints>> pointsOf({
    required UserId user,
    required SeasonId season,
  }) async {
    asked.add((user.value, season.value));
    return Result.ok(month);
  }
}

PlayerPointEntry _entry(String kind, int amount) => PlayerPointEntry(
  id: 'e-$kind',
  fixtureId: 'f-1',
  homeTeam: 'Arsenal',
  awayTeam: 'Chelsea',
  kind: kind,
  amount: amount,
  occurredAt: DateTime.utc(2026, 10, 10, 21),
);

/// An admin reads one player's points in one month by name and month,
/// from the fixture ledger, audited before it is served (batch 146b,
/// audit C-01 and L-14).
void main() {
  late InMemoryAuditLogRepository auditLog;

  setUp(() => auditLog = InMemoryAuditLogRepository());

  AdminViewPlayerPoints useCase(_Reader reader) => AdminViewPlayerPoints(
    reader: reader,
    auditRecorder: auditRecorderOver(auditLog),
  );

  test('the month is read and the read is audited against the player\'s '
      'participation', () async {
    final _Reader reader = _Reader(
      PlayerMonthPoints(
        participantId: participantUuid,
        entries: [_entry('fixture_score', 3), _entry('streak_bonus', 2)],
      ),
    );

    final Result<PlayerMonthPoints> result = await useCase(reader).call(
      principal: principal(userId: adminUuid),
      userId: targetUuid,
      seasonId: seasonUuid,
    );

    final PlayerMonthPoints month = (result as Ok<PlayerMonthPoints>).value;
    expect(month.monthPoints, 3);
    expect(month.streakBonus, 2);
    expect(reader.asked, [(targetUuid, seasonUuid)]);
    expect(auditLog.rows.single.action, AuditAction.participantLedgerViewed);
    expect(auditLog.rows.single.targetRef, participantUuid);
  });

  test(
    'a month he never played is empty, audited against the player',
    () async {
      final _Reader reader = _Reader(
        const PlayerMonthPoints(participantId: null, entries: []),
      );

      final Result<PlayerMonthPoints> result = await useCase(reader).call(
        principal: principal(userId: adminUuid),
        userId: targetUuid,
        seasonId: seasonUuid,
      );

      expect((result as Ok<PlayerMonthPoints>).value.entries, isEmpty);
      expect(auditLog.rows.single.targetRef, targetUuid);
    },
  );

  test('a non-admin reads nothing and leaves no trace', () async {
    final _Reader reader = _Reader(
      const PlayerMonthPoints(participantId: null, entries: []),
    );

    final Result<PlayerMonthPoints> result = await useCase(reader).call(
      principal: principal(userId: adminUuid, role: PlatformRole.user),
      userId: targetUuid,
      seasonId: seasonUuid,
    );

    expect(result, isA<Err<PlayerMonthPoints>>());
    expect(reader.asked, isEmpty);
    expect(auditLog.rows, isEmpty);
  });

  test('an id that is not one is refused before any read', () async {
    final _Reader reader = _Reader(
      const PlayerMonthPoints(participantId: null, entries: []),
    );

    final Result<PlayerMonthPoints> result = await useCase(reader).call(
      principal: principal(userId: adminUuid),
      userId: 'not-a-uuid',
      seasonId: seasonUuid,
    );

    expect(result, isA<Err<PlayerMonthPoints>>());
    expect(reader.asked, isEmpty);
  });

  test('a failed audit refuses the read', () async {
    final _Reader reader = _Reader(
      const PlayerMonthPoints(participantId: null, entries: []),
    );
    auditLog.failNextWith(const AppError.transient('db.down', 'down'));

    final Result<PlayerMonthPoints> result = await useCase(reader).call(
      principal: principal(userId: adminUuid),
      userId: targetUuid,
      seasonId: seasonUuid,
    );

    expect(result, isA<Err<PlayerMonthPoints>>());
  });
}
