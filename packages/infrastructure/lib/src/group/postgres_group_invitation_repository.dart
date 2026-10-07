import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:postgres/postgres.dart' show ServerException;
import 'package:shared/shared.dart';

/// Postgres adapter for [GroupInvitationRepository] over
/// `"group".group_invitations` (migration 0097).
///
/// One invitation per (league, player): a second invite conflicts on
/// `group_invitations_once` and inserts nothing. An answer moves a pending
/// invitation only. Push tokens arrive joined into one string so no array
/// is bound or decoded (an FCM token never contains a comma).
///
/// Total: never throws, binds every value through a `@named` parameter; a
/// malformed row is a transient `group.row_corrupt`.
final class PostgresGroupInvitationRepository
    implements GroupInvitationRepository {
  /// Creates the repository over [_connection].
  const PostgresGroupInvitationRepository(this._connection);

  final PostgresConnection _connection;

  static const String createSql = '''
INSERT INTO "group".group_invitations
  (id, group_id, inviter_user_id, invitee_user_id, status, created_at)
VALUES
  (@id::uuid, @group_id::uuid, @inviter::uuid, @invitee::uuid, 'pending',
   @created_at)
ON CONFLICT ON CONSTRAINT group_invitations_once DO NOTHING
RETURNING id
''';

  static const String _select = '''
SELECT i.id::text AS id,
       i.group_id::text AS group_id,
       g.name AS group_name,
       i.inviter_user_id::text AS inviter_user_id,
       coalesce(u.display_name, '') AS inviter_name,
       i.invitee_user_id::text AS invitee_user_id,
       i.status AS status,
       i.created_at AS created_at
FROM "group".group_invitations i
JOIN "group".groups g ON g.id = i.group_id
JOIN identity.users u ON u.id = i.inviter_user_id
''';

  static const String findSql =
      '${_select}WHERE i.id = @id::uuid AND i.invitee_user_id = @invitee::uuid';

  static const String listSql =
      '${_select}WHERE i.invitee_user_id = @invitee::uuid '
      'ORDER BY i.created_at DESC LIMIT @limit';

  static const String respondSql = '''
UPDATE "group".group_invitations
SET status = @status, responded_at = @at
WHERE id = @id::uuid
  AND invitee_user_id = @invitee::uuid
  AND status = 'pending'
RETURNING id
''';

  static const String pushTargetSql = '''
SELECT u.utc_offset_minutes AS utc_offset_minutes,
       coalesce((
         SELECT string_agg(dt.token, ',')
         FROM notification.device_tokens dt
         WHERE dt.user_id = u.id
       ), '') AS tokens
FROM identity.users u
WHERE u.id = @user::uuid
''';

  @override
  Future<Result<bool>> createIfAbsent({
    required String id,
    required GroupId groupId,
    required UserId inviter,
    required UserId invitee,
    required DateTime createdAt,
  }) async {
    final result = await _connection.query(
      createSql,
      parameters: {
        'id': id,
        'group_id': groupId.value,
        'inviter': inviter.value,
        'invitee': invitee.value,
        'created_at': createdAt.toUtc(),
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(
        _reclassify(error),
      ),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        value.isNotEmpty,
      ),
    };
  }

  /// An unknown league or player breaks a foreign key: a refusal, not an
  /// outage.
  static AppError _reclassify(AppError error) {
    final Object? cause = error.cause;
    if (cause is ServerException && cause.code == '23503') {
      return const AppError.invariant(
        'group.invitee_not_found',
        'No such player or league',
      );
    }
    return error;
  }

  @override
  Future<Result<GroupInvitation?>> findForInvitee({
    required String id,
    required UserId invitee,
  }) async {
    final result = await _connection.query(
      findSql,
      parameters: {'id': id, 'invitee': invitee.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty ? const Result.ok(null) : _map(value.first),
    };
  }

  @override
  Future<Result<bool>> respond({
    required String id,
    required UserId invitee,
    required GroupInvitationStatus status,
    required DateTime at,
  }) async {
    final result = await _connection.query(
      respondSql,
      parameters: {
        'id': id,
        'invitee': invitee.value,
        'status': status.wireValue,
        'at': at.toUtc(),
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        value.isNotEmpty,
      ),
    };
  }

  @override
  Future<Result<List<GroupInvitation>>> listForInvitee(
    UserId invitee, {
    required int limit,
  }) async {
    final result = await _connection.query(
      listSql,
      parameters: {'invitee': invitee.value, 'limit': limit},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final List<GroupInvitation> invitations = <GroupInvitation>[];
    for (final Map<String, dynamic> row
        in (result as Ok<List<Map<String, dynamic>>>).value) {
      final mapped = _map(row);
      if (mapped is Err<GroupInvitation?>) return Result.err(mapped.error);
      invitations.add((mapped as Ok<GroupInvitation?>).value!);
    }
    return Result.ok(List<GroupInvitation>.unmodifiable(invitations));
  }

  @override
  Future<Result<GroupInviteePush>> pushTargetOf(UserId user) async {
    final result = await _connection.query(
      pushTargetSql,
      parameters: {'user': user.value},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    if (rows.isEmpty) {
      return const Result.ok(GroupInviteePush(tokens: <String>[]));
    }
    final Object? tokens = rows.first['tokens'];
    final Object? offset = rows.first['utc_offset_minutes'];
    return Result.ok(
      GroupInviteePush(
        tokens: List<String>.unmodifiable(<String>[
          if (tokens is String)
            for (final String token in tokens.split(','))
              if (token.isNotEmpty) token,
        ]),
        utcOffsetMinutes: offset is int ? offset : null,
      ),
    );
  }

  Result<GroupInvitation?> _map(Map<String, dynamic> row) {
    final group = GroupId.tryParse(row['group_id']?.toString());
    if (group is Err<GroupId>) {
      return Result.err(_corrupt('group_id', group.error.message));
    }
    final inviter = UserId.tryParse(row['inviter_user_id']?.toString());
    if (inviter is Err<UserId>) {
      return Result.err(_corrupt('inviter_user_id', inviter.error.message));
    }
    final invitee = UserId.tryParse(row['invitee_user_id']?.toString());
    if (invitee is Err<UserId>) {
      return Result.err(_corrupt('invitee_user_id', invitee.error.message));
    }
    final Object? id = row['id'];
    final Object? groupName = row['group_name'];
    final Object? inviterName = row['inviter_name'];
    final GroupInvitationStatus? status = GroupInvitationStatus.tryParse(
      row['status']?.toString(),
    );
    final Object? createdAt = row['created_at'];
    if (id is! String ||
        groupName is! String ||
        inviterName is! String ||
        status == null ||
        createdAt is! DateTime) {
      return Result.err(_corrupt('row', 'missing or mistyped column'));
    }
    return Result.ok(
      GroupInvitation(
        id: id,
        groupId: (group as Ok<GroupId>).value,
        groupName: groupName,
        inviterUserId: (inviter as Ok<UserId>).value,
        inviterName: inviterName,
        inviteeUserId: (invitee as Ok<UserId>).value,
        status: status,
        createdAt: createdAt.toUtc(),
      ),
    );
  }

  static AppError _corrupt(String field, String detail) => AppError.transient(
    'group.row_corrupt',
    'Stored group invitation row has invalid $field: $detail',
  );
}
