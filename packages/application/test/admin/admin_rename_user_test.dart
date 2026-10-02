import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'fakes.dart';

/// A directory holding users by id. [taken] names belong to someone else:
/// writing one fails the way the database does (migration 0084).
final class _Directory implements UserDirectory {
  final Map<String, User> byId = {};
  final Set<String> taken = {};
  int writes = 0;

  @override
  Future<Result<User?>> findUser(UserId id) async => Result.ok(byId[id.value]);

  @override
  Future<Result<User>> updateDisplayName(
    UserId userId,
    String displayName,
  ) async {
    writes++;
    if (taken.contains(displayName)) {
      return const Result.err(
        AppError.validation(
          'identity.display_name_taken',
          'هذا الاسم مستخدم، اختر اسمًا آخر',
        ),
      );
    }
    final current = byId[userId.value]!;
    final next = User(
      id: current.id,
      email: current.email,
      role: current.role,
      status: current.status,
      displayName: displayName,
    );
    byId[userId.value] = next;
    return Result.ok(next);
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

void main() {
  late _Directory directory;
  late InMemoryAuditLogRepository auditLog;
  late AdminRenameUser rename;

  setUp(() {
    directory = _Directory();
    directory.byId[targetUuid] = storedUser(id: targetUuid);
    auditLog = InMemoryAuditLogRepository();
    rename = AdminRenameUser(
      userDirectory: directory,
      auditRecorder: auditRecorderOver(auditLog),
    );
  });

  final admin = principal(userId: adminUuid);

  test('renames the user, trims the name and audits old and new', () async {
    final result = await rename(
      principal: admin,
      targetUserId: targetUuid,
      displayName: '  أحمد الثاني ',
      reason: 'اسم مكرر',
    );

    expect((result as Ok<User>).value.displayName, 'أحمد الثاني');
    expect(directory.byId[targetUuid]!.displayName, 'أحمد الثاني');
    final entry = auditLog.rows.single;
    expect(entry.action, AuditAction.userRenamed);
    expect(entry.actorId.value, adminUuid);
    expect(entry.targetRef, targetUuid);
    expect(entry.reason, 'اسم مكرر | Human -> أحمد الثاني');
  });

  test(
    'a name another player holds is refused and nothing is audited',
    () async {
      directory.taken.add('خالد');

      final result = await rename(
        principal: admin,
        targetUserId: targetUuid,
        displayName: 'خالد',
        reason: 'اسم مكرر',
      );

      expect((result as Err<User>).error.code, 'identity.display_name_taken');
      expect(directory.byId[targetUuid]!.displayName, 'Human');
      expect(auditLog.rows, isEmpty);
    },
  );

  test('a player cannot rename anyone', () async {
    final result = await rename(
      principal: principal(userId: adminUuid, role: PlatformRole.user),
      targetUserId: targetUuid,
      displayName: 'خالد',
      reason: 'x',
    );

    expect((result as Err<User>).error.code, 'auth.insufficient_role');
    expect(directory.writes, 0);
  });

  test('a blank reason or a blank name is refused before any write', () async {
    final noReason = await rename(
      principal: admin,
      targetUserId: targetUuid,
      displayName: 'خالد',
      reason: '  ',
    );
    final noName = await rename(
      principal: admin,
      targetUserId: targetUuid,
      displayName: ' ',
      reason: 'اسم مكرر',
    );

    expect((noReason as Err<User>).error.code, 'admin.rename_reason_required');
    expect((noName as Err<User>).error.code, 'identity.display_name_empty');
    expect(directory.writes, 0);
    expect(auditLog.rows, isEmpty);
  });

  test('an unknown account is not found', () async {
    final result = await rename(
      principal: admin,
      targetUserId: participantUuid,
      displayName: 'خالد',
      reason: 'اسم مكرر',
    );

    expect((result as Err<User>).error.code, 'admin.user_not_found');
  });

  test('the same name again writes and audits nothing', () async {
    final result = await rename(
      principal: admin,
      targetUserId: targetUuid,
      displayName: 'Human',
      reason: 'اسم مكرر',
    );

    expect((result as Ok<User>).value.displayName, 'Human');
    expect(directory.writes, 0);
    expect(auditLog.rows, isEmpty);
  });
}
