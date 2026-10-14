import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
// `postgres` exports its own `Result`; we only need its exception hierarchy here
// (to read the SQLSTATE `code`/`constraintName` off a `ServerException`), so
// hide `Result` to keep `Result<T>` unambiguously our `shared` union.
import 'package:postgres/postgres.dart' hide Result;
import 'package:shared/shared.dart';

/// Postgres-backed [GroupRepository] + [GroupStandingsReader] over the
/// `group.groups` / `group.group_memberships` tables and the reused
/// `leaderboard.season_standings` VIEW (Database ADR; migration
/// `0007_group.sql`).
///
/// A Group is an orthogonal social container (Groups decision #1): this adapter
/// writes/reads only the group + membership tables, and the group leaderboard is
/// the ratified season-standings projection INTERSECTED with the group's
/// membership (decision #4 — NO new points source, NO new ranking logic; ranking
/// is the pure domain's job in the use-case).
///
/// The adapter is *total* (Application ADR §2): it never throws. It speaks only
/// in the domain [Group]/[GroupMembership] aggregates, the [GroupStandingEntry]
/// pairing, and typed ids; SQL and rows never leak. A driver failure surfaces as
/// [ErrorKind.transient]; a storage-integrity conflict it can only detect at the
/// storage layer (a unique/FK violation) is reclassified to a typed
/// [ErrorKind.invariant] by the EXPLICITLY-named constraints in `0007_group.sql`
/// (`groups_invite_code_key` → `group.invite_code_conflict`,
/// `group_memberships_group_user_uniq` → `group.already_member`,
/// `group_memberships_group_id_fkey` → `group.not_found`,
/// `group_memberships_user_id_fkey`/`groups_owner_id_fkey` →
/// `group.user_not_found`). A malformed row maps to transient
/// `group.row_corrupt`. All queries bind through `@named` parameters
/// (Security ADR §2).
///
/// **Atomicity** (decision #2): [createGroupWithOwner] writes the group row and
/// its owner membership inside a single [PostgresConnection.runInTransaction],
/// so a group can never exist without its owner row (a mid-write failure rolls
/// both back).
///
/// It is also the [GroupRosterStore] (audit M-26, L-40): leaving, removal
/// and deletion are single statements, and a full league's join
/// (`group_memberships_capacity`, migration 0111) maps to `group.full`.
final class PostgresGroupRepository
    implements GroupRepository, GroupStandingsReader, GroupRosterStore {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresGroupRepository(this._connection);

  final PostgresConnection _connection;

  // --------------------------------------------------------------------------
  // createGroupWithOwner — atomic group + owner membership
  // --------------------------------------------------------------------------

  static const String _insertGroupSql = '''
INSERT INTO "group".groups (id, owner_id, name, invite_code)
VALUES (@id, @owner_id, @name, @invite_code)
''';

  static const String _insertMembershipSql = '''
INSERT INTO "group".group_memberships (id, group_id, user_id, role, joined_at)
VALUES (@id, @group_id, @user_id, @role, @joined_at)
''';

  @override
  Future<Result<void>> createGroupWithOwner(
    Group group,
    GroupMembership ownerMembership,
  ) {
    return _connection.runInTransaction((tx) async {
      final insertedGroup = await tx.query(
        _insertGroupSql,
        parameters: {
          'id': group.id.value,
          'owner_id': group.ownerId.value,
          'name': group.name,
          'invite_code': group.inviteCode.value,
        },
      );
      if (insertedGroup is Err<List<Map<String, dynamic>>>) {
        return Result<void>.err(_reclassify(insertedGroup.error));
      }

      final insertedMembership = await tx.query(
        _insertMembershipSql,
        parameters: {
          'id': ownerMembership.id.value,
          'group_id': ownerMembership.groupId.value,
          'user_id': ownerMembership.userId.value,
          'role': ownerMembership.role.wireValue,
          'joined_at': ownerMembership.joinedAt.toUtc(),
        },
      );
      if (insertedMembership is Err<List<Map<String, dynamic>>>) {
        return Result<void>.err(_reclassify(insertedMembership.error));
      }

      return const Result<void>.ok(null);
    });
  }

  // --------------------------------------------------------------------------
  // findGroup / findByInviteCode
  // --------------------------------------------------------------------------

  static const String _selectGroupByIdSql = '''
SELECT id, owner_id, name, invite_code, created_at
FROM "group".groups
WHERE id = @id
''';

  static const String _selectGroupByInviteSql = '''
SELECT id, owner_id, name, invite_code, created_at
FROM "group".groups
WHERE invite_code = @invite_code
''';

  @override
  Future<Result<Group?>> findGroup(GroupId id) async {
    final result = await _connection.query(
      _selectGroupByIdSql,
      parameters: {'id': id.value},
    );
    return _firstGroupOrNull(result);
  }

  @override
  Future<Result<Group?>> findByInviteCode(InviteCode inviteCode) async {
    final result = await _connection.query(
      _selectGroupByInviteSql,
      parameters: {'invite_code': inviteCode.value},
    );
    return _firstGroupOrNull(result);
  }

  Result<Group?> _firstGroupOrNull(Result<List<Map<String, dynamic>>> result) {
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty ? const Result.ok(null) : _mapGroup(value.first),
    };
  }

  // --------------------------------------------------------------------------
  // updateGroup — rename / invite rotation
  // --------------------------------------------------------------------------

  static const String _updateGroupSql = '''
UPDATE "group".groups
SET name = @name, invite_code = @invite_code
WHERE id = @id
''';

  @override
  Future<Result<void>> updateGroup(Group group) async {
    final result = await _connection.query(
      _updateGroupSql,
      parameters: {
        'id': group.id.value,
        'name': group.name,
        'invite_code': group.inviteCode.value,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(
        _reclassify(error),
      ),
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
    };
  }

  // --------------------------------------------------------------------------
  // saveMembership — a member joining
  // --------------------------------------------------------------------------

  @override
  Future<Result<void>> saveMembership(GroupMembership membership) async {
    final result = await _connection.query(
      _insertMembershipSql,
      parameters: {
        'id': membership.id.value,
        'group_id': membership.groupId.value,
        'user_id': membership.userId.value,
        'role': membership.role.wireValue,
        'joined_at': membership.joinedAt.toUtc(),
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(
        _reclassify(error),
      ),
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
    };
  }

  // --------------------------------------------------------------------------
  // findMembership / listMemberships
  // --------------------------------------------------------------------------

  static const String _selectMembershipSql = '''
SELECT id, group_id, user_id, role::text, joined_at
FROM "group".group_memberships
WHERE group_id = @group_id AND user_id = @user_id
''';

  static const String _listMembershipsSql = '''
SELECT id, group_id, user_id, role::text, joined_at
FROM "group".group_memberships
WHERE group_id = @group_id
ORDER BY joined_at ASC, id ASC
''';

  // "My Groups": one round trip joining the caller's own membership rows to
  // their groups, with the member count computed inline via a correlated
  // subquery (no new points source, no ranking logic — this is a plain roster
  // join, Groups decision #1/#2). Ordered joined-at DESC (most recently
  // joined group first — decision: "My Groups" is a personal roster, not a
  // discovery surface that would sort by name/activity).
  static const String _listGroupsForUserSql = '''
SELECT
  g.id, g.owner_id, g.name, g.invite_code, g.created_at,
  gm.role::text AS my_role, gm.joined_at AS my_joined_at,
  (
    SELECT COUNT(*) FROM "group".group_memberships gm2
    WHERE gm2.group_id = g.id
  ) AS member_count
FROM "group".groups g
JOIN "group".group_memberships gm
  ON gm.group_id = g.id AND gm.user_id = @user_id
ORDER BY gm.joined_at DESC, g.id ASC
''';

  @override
  Future<Result<List<MyGroupSummary>>> listGroupsForUser(UserId userId) async {
    final result = await _connection.query(
      _listGroupsForUserSql,
      parameters: {'user_id': userId.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapMyGroupSummaries(
        value,
      ),
    };
  }

  @override
  Future<Result<GroupMembership?>> findMembership(
    GroupId groupId,
    UserId userId,
  ) async {
    final result = await _connection.query(
      _selectMembershipSql,
      parameters: {'group_id': groupId.value, 'user_id': userId.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty ? const Result.ok(null) : _mapMembership(value.first),
    };
  }

  @override
  Future<Result<List<GroupMembership>>> listMemberships(GroupId groupId) async {
    final result = await _connection.query(
      _listMembershipsSql,
      parameters: {'group_id': groupId.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapMemberships(value),
    };
  }

  // --------------------------------------------------------------------------
  // GroupRosterStore — leave / remove / delete, the members of a month
  // --------------------------------------------------------------------------

  // One statement: the membership goes with the invitation that brought the
  // player in, so he can be invited again. Only a member row: the owner's
  // is never removed here (the use-cases refuse it first).
  static const String _removeMembershipSql = '''
WITH gone AS (
  DELETE FROM "group".group_memberships
  WHERE group_id = @group_id::uuid
    AND user_id = @user_id::uuid
    AND role = 'member'
  RETURNING user_id
), invitation AS (
  DELETE FROM "group".group_invitations i
  USING gone
  WHERE i.group_id = @group_id::uuid
    AND i.invitee_user_id = gone.user_id
)
SELECT count(*)::int AS removed FROM gone
''';

  // Memberships, invitations, reactions and the league's notifications
  // follow by ON DELETE CASCADE (0007, 0008, 0009, 0020, 0097).
  static const String _deleteGroupSql = '''
WITH gone AS (
  DELETE FROM "group".groups
  WHERE id = @group_id::uuid
  RETURNING id
)
SELECT count(*)::int AS deleted FROM gone
''';

  static const String _memberParticipantIdsSql = '''
SELECT p.id::text AS participant_id
FROM "group".group_memberships gm
JOIN competition.participants p
  ON p.user_id = gm.user_id
 AND p.season_id = @season_id::uuid
WHERE gm.group_id = @group_id::uuid
''';

  @override
  Future<Result<bool>> removeMembership(GroupId groupId, UserId userId) async {
    final result = await _connection.query(
      _removeMembershipSql,
      parameters: {'group_id': groupId.value, 'user_id': userId.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        value.isNotEmpty && (_readInt(value.first['removed']) ?? 0) > 0,
      ),
    };
  }

  @override
  Future<Result<bool>> deleteGroup(GroupId groupId) async {
    final result = await _connection.query(
      _deleteGroupSql,
      parameters: {'group_id': groupId.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        value.isNotEmpty && (_readInt(value.first['deleted']) ?? 0) > 0,
      ),
    };
  }

  @override
  Future<Result<Set<String>>> memberParticipantIds(
    GroupId groupId,
    SeasonId seasonId,
  ) async {
    final result = await _connection.query(
      _memberParticipantIdsSql,
      parameters: {'group_id': groupId.value, 'season_id': seasonId.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok({
        for (final row in value)
          if (row['participant_id'] != null) row['participant_id'].toString(),
      }),
    };
  }

  // --------------------------------------------------------------------------
  // groupSeasonStandings — the reused season projection ∩ group membership
  // --------------------------------------------------------------------------

  // The season's participants who are members of the group, with their
  // points from the SAME store the monthly board reads:
  // `leaderboard.season_fixture_standings` (migration 0034) over
  // `scoring.fixture_scores`, LEFT-joined so a member with nothing scored
  // yet reads 0. The previous source, `leaderboard.season_standings`, sums
  // the round-era `ledger.point_entries`, empty since fixtures moved to
  // seasons -- every member read 0 (audit C-01). NO ORDER BY -- the pure
  // domain SeasonLeaderboard.rank owns ordering and "1224" ranks.
  static const String _selectGroupSeasonStandingsSql = '''
SELECT
  p.id         AS participant_id,
  p.user_id    AS user_id,
  u.display_name AS display_name,
  COALESCE(f.total_points, 0)::bigint    AS total_points,
  COALESCE(f.fixtures_scored, 0)::bigint AS entry_count,
  p.joined_at  AS joined_at,
  COALESCE(f.exact_count, 0)::bigint     AS exact_count,
  COALESCE(f.decided_count, 0)::bigint   AS settled_count,
  COALESCE(f.outcome_count, 0)::bigint   AS outcome_count,
  COALESCE(rm.referral_points, 0)::bigint AS referral_points
FROM competition.participants p
JOIN "group".group_memberships m ON m.user_id = p.user_id
JOIN identity.users u ON u.id = p.user_id
LEFT JOIN leaderboard.season_fixture_standings f ON f.participant_id = p.id
LEFT JOIN gamification.referral_month_points rm
  ON rm.season_id = p.season_id
 AND rm.user_id = p.user_id
WHERE p.season_id = @season_id
  AND m.group_id = @group_id
  AND u.status <> 'suspended'
''';

  @override
  Future<Result<List<GroupStandingEntry>>> groupSeasonStandings({
    required GroupId groupId,
    required SeasonId seasonId,
  }) async {
    final result = await _connection.query(
      _selectGroupSeasonStandingsSql,
      parameters: {'group_id': groupId.value, 'season_id': seasonId.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapStandings(value),
    };
  }

  // --------------------------------------------------------------------------
  // Row mapping
  // --------------------------------------------------------------------------

  Result<Group?> _mapGroup(Map<String, dynamic> row) {
    final idResult = GroupId.tryParse(row['id']?.toString());
    final ownerIdResult = UserId.tryParse(row['owner_id']?.toString());
    final name = row['name'];
    final inviteResult = InviteCode.tryParse(row['invite_code']?.toString());
    final createdAt = _readUtcTimestamp(row['created_at']);

    if (idResult is Err<GroupId>) {
      return Result.err(_corrupt('groups', 'id', idResult.error.message));
    }
    if (ownerIdResult is Err<UserId>) {
      return Result.err(
        _corrupt('groups', 'owner_id', ownerIdResult.error.message),
      );
    }
    if (name is! String) {
      return Result.err(_corrupt('groups', 'name', 'null or not text'));
    }
    if (inviteResult is Err<InviteCode>) {
      return Result.err(
        _corrupt('groups', 'invite_code', inviteResult.error.message),
      );
    }
    if (createdAt == null) {
      return Result.err(_corrupt('groups', 'created_at', 'not a timestamp'));
    }

    return Result.ok(
      Group.fromStored(
        id: (idResult as Ok<GroupId>).value,
        ownerId: (ownerIdResult as Ok<UserId>).value,
        name: name,
        inviteCode: (inviteResult as Ok<InviteCode>).value,
        createdAt: createdAt,
      ),
    );
  }

  Result<List<MyGroupSummary>> _mapMyGroupSummaries(
    List<Map<String, dynamic>> rows,
  ) {
    final list = <MyGroupSummary>[];
    for (final row in rows) {
      final idResult = GroupId.tryParse(row['id']?.toString());
      final ownerIdResult = UserId.tryParse(row['owner_id']?.toString());
      final name = row['name'];
      final inviteResult = InviteCode.tryParse(row['invite_code']?.toString());
      final createdAt = _readUtcTimestamp(row['created_at']);
      final roleResult = GroupRole.tryParse(row['my_role']?.toString());
      final myJoinedAt = _readUtcTimestamp(row['my_joined_at']);
      final memberCount = _readInt(row['member_count']);

      if (idResult is Err<GroupId>) {
        return Result.err(_corrupt('groups', 'id', idResult.error.message));
      }
      if (ownerIdResult is Err<UserId>) {
        return Result.err(
          _corrupt('groups', 'owner_id', ownerIdResult.error.message),
        );
      }
      if (name is! String) {
        return Result.err(_corrupt('groups', 'name', 'null or not text'));
      }
      if (inviteResult is Err<InviteCode>) {
        return Result.err(
          _corrupt('groups', 'invite_code', inviteResult.error.message),
        );
      }
      if (createdAt == null) {
        return Result.err(_corrupt('groups', 'created_at', 'not a timestamp'));
      }
      if (roleResult is Err<GroupRole>) {
        return Result.err(
          _corrupt('group_memberships', 'role', roleResult.error.message),
        );
      }
      if (myJoinedAt == null) {
        return Result.err(
          _corrupt('group_memberships', 'joined_at', 'not a timestamp'),
        );
      }
      if (memberCount == null) {
        return Result.err(
          _corrupt('group_memberships', 'member_count', 'not an integer'),
        );
      }

      list.add(
        MyGroupSummary(
          group: Group.fromStored(
            id: (idResult as Ok<GroupId>).value,
            ownerId: (ownerIdResult as Ok<UserId>).value,
            name: name,
            inviteCode: (inviteResult as Ok<InviteCode>).value,
            createdAt: createdAt,
          ),
          role: (roleResult as Ok<GroupRole>).value,
          joinedAt: myJoinedAt,
          memberCount: memberCount,
        ),
      );
    }
    return Result.ok(List<MyGroupSummary>.unmodifiable(list));
  }

  Result<List<GroupMembership>> _mapMemberships(
    List<Map<String, dynamic>> rows,
  ) {
    final list = <GroupMembership>[];
    for (final row in rows) {
      final mapped = _mapMembership(row);
      if (mapped is Err<GroupMembership?>) {
        return Result.err(mapped.error);
      }
      final value = (mapped as Ok<GroupMembership?>).value;
      if (value == null) {
        return Result.err(_corrupt('group_memberships', 'row', 'null mapping'));
      }
      list.add(value);
    }
    return Result.ok(List<GroupMembership>.unmodifiable(list));
  }

  Result<GroupMembership?> _mapMembership(Map<String, dynamic> row) {
    final idResult = GroupMembershipId.tryParse(row['id']?.toString());
    final groupIdResult = GroupId.tryParse(row['group_id']?.toString());
    final userIdResult = UserId.tryParse(row['user_id']?.toString());
    final roleResult = GroupRole.tryParse(row['role']?.toString());
    final joinedAt = _readUtcTimestamp(row['joined_at']);

    if (idResult is Err<GroupMembershipId>) {
      return Result.err(
        _corrupt('group_memberships', 'id', idResult.error.message),
      );
    }
    if (groupIdResult is Err<GroupId>) {
      return Result.err(
        _corrupt('group_memberships', 'group_id', groupIdResult.error.message),
      );
    }
    if (userIdResult is Err<UserId>) {
      return Result.err(
        _corrupt('group_memberships', 'user_id', userIdResult.error.message),
      );
    }
    if (roleResult is Err<GroupRole>) {
      return Result.err(
        _corrupt('group_memberships', 'role', roleResult.error.message),
      );
    }
    if (joinedAt == null) {
      return Result.err(
        _corrupt('group_memberships', 'joined_at', 'not a timestamp'),
      );
    }

    return Result.ok(
      GroupMembership.fromStored(
        id: (idResult as Ok<GroupMembershipId>).value,
        groupId: (groupIdResult as Ok<GroupId>).value,
        userId: (userIdResult as Ok<UserId>).value,
        role: (roleResult as Ok<GroupRole>).value,
        joinedAt: joinedAt,
      ),
    );
  }

  Result<List<GroupStandingEntry>> _mapStandings(
    List<Map<String, dynamic>> rows,
  ) {
    final list = <GroupStandingEntry>[];
    for (final row in rows) {
      final userIdResult = UserId.tryParse(row['user_id']?.toString());
      final participantIdResult = ParticipantId.tryParse(
        row['participant_id']?.toString(),
      );
      final displayName = row['display_name']?.toString();
      final totalPoints = _readInt(row['total_points']);
      final entryCount = _readInt(row['entry_count']);
      final joinedAt = _readUtcTimestamp(row['joined_at']);
      // The month board's tie-breaks (batch 134); absent reads as none.
      final exactCount = _readInt(row['exact_count']) ?? 0;
      final settledCount = _readInt(row['settled_count']) ?? 0;
      final outcomeCount = _readInt(row['outcome_count']) ?? 0;
      final referralPoints = _readInt(row['referral_points']) ?? 0;

      if (userIdResult is Err<UserId>) {
        return Result.err(
          _corrupt('season_standings', 'user_id', userIdResult.error.message),
        );
      }
      if (participantIdResult is Err<ParticipantId>) {
        return Result.err(
          _corrupt(
            'season_standings',
            'participant_id',
            participantIdResult.error.message,
          ),
        );
      }
      if (displayName == null || displayName.isEmpty) {
        return Result.err(
          _corrupt('season_standings', 'display_name', 'null or empty'),
        );
      }
      if (totalPoints == null) {
        return Result.err(
          _corrupt('season_standings', 'total_points', 'not an integer'),
        );
      }
      if (entryCount == null) {
        return Result.err(
          _corrupt('season_standings', 'entry_count', 'not an integer'),
        );
      }
      if (joinedAt == null) {
        return Result.err(
          _corrupt('season_standings', 'joined_at', 'not a timestamp'),
        );
      }

      final projected = LeaderboardEntry.projected(
        participantId: (participantIdResult as Ok<ParticipantId>).value,
        displayName: displayName,
        totalPoints: totalPoints,
        entryCount: entryCount,
        joinedAt: joinedAt,
        exactCount: exactCount,
        settledCount: settledCount,
        outcomeCount: outcomeCount,
        referralPoints: referralPoints,
      );
      if (projected is Err<LeaderboardEntry>) {
        return Result.err(
          _corrupt('season_standings', 'row', projected.error.message),
        );
      }

      list.add(
        GroupStandingEntry(
          userId: (userIdResult as Ok<UserId>).value,
          entry: (projected as Ok<LeaderboardEntry>).value,
        ),
      );
    }
    return Result.ok(List<GroupStandingEntry>.unmodifiable(list));
  }

  // --------------------------------------------------------------------------
  // Shared helpers (mirror the ledger/scoring/competition/leaderboard adapters)
  // --------------------------------------------------------------------------

  AppError _reclassify(AppError error) {
    final cause = error.cause;
    if (cause is! ServerException) {
      return error;
    }
    final code = cause.code;
    // 23505 unique_violation, 23503 foreign_key_violation, 23514 check_violation.
    const integrityCodes = {'23505', '23503', '23514'};
    if (code == null || !integrityCodes.contains(code)) {
      return error;
    }
    final constraint = cause.constraintName;
    switch (constraint) {
      case 'groups_invite_code_key':
        return const AppError.invariant(
          'group.invite_code_conflict',
          'A group with that invite code already exists',
        );
      case 'group_memberships_group_user_uniq':
        return const AppError.invariant(
          'group.already_member',
          'The user is already a member of the group',
        );
      case 'group_memberships_group_id_fkey':
        return const AppError.invariant('group.not_found', 'Group not found');
      case 'group_memberships_user_id_fkey':
      case 'groups_owner_id_fkey':
        return const AppError.invariant(
          'group.user_not_found',
          'User not found',
        );
      case 'group_memberships_capacity':
        return JoinGroupByInvite.full;
      case 'groups_name_len_chk':
        return const AppError.invariant(
          'group.integrity_violation',
          'The group name violated a length constraint',
        );
    }
    // A group id PK collision (no named constraint) or any other integrity code.
    return const AppError.invariant(
      'group.integrity_violation',
      'The write violated a group integrity rule',
    );
  }

  static int? _readInt(Object? raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is BigInt && raw.isValidInt) {
      return raw.toInt();
    }
    if (raw is String) {
      return int.tryParse(raw);
    }
    return null;
  }

  static DateTime? _readUtcTimestamp(Object? raw) {
    if (raw is DateTime) {
      return raw.toUtc();
    }
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      return parsed?.toUtc();
    }
    return null;
  }

  static AppError _corrupt(String table, String field, String detail) =>
      AppError.transient(
        'group.row_corrupt',
        'Stored $table row has invalid $field: $detail',
      );
}
