import 'package:api_client/src/api_transport.dart';
import 'package:contracts/contracts.dart';
import 'package:shared/shared.dart';

/// Typed client for the Groups (Community) surface of `apps/server`.
///
/// Wraps the ratified routes verbatim — no invented path:
///   * `POST /groups` -> [GroupDto] (`routes/groups/index.dart`).
///   * `GET  /groups/{id}` -> [GroupDto] (`routes/groups/[id]/index.dart`).
///   * `POST /groups/join` -> [GroupMembershipDto] (the join response is a
///     membership, not a group — `routes/groups/join/index.dart`).
///   * `GET  /groups/{id}/members` -> [GroupMembersDto]
///     (`routes/groups/[id]/members/index.dart`).
///   * `GET  /groups/{id}/seasons/{seasonId}/leaderboard` ->
///     [GroupLeaderboardDto]
///     (`routes/groups/[id]/seasons/[seasonId]/leaderboard/index.dart`).
///   * `GET  /groups/{id}/feed` -> [GroupActivityFeedDto]
///     (`routes/groups/[id]/feed/index.dart`).
///
/// Every visibility gate (member-only, owner-only for a future rename) lives
/// entirely inside the server use-cases (Security ADR §2) — this client makes
/// no authorization decision; a non-member call is refused identically as
/// `401 group.not_a_member` (no existence oracle, Groups decision #3).
///
/// The whole `/groups` subtree is already behind `bearerAuth`
/// (`routes/groups/_middleware.dart`); an unauthenticated call is refused
/// there with `401`. Every method returns a typed [Result] and never throws.
final class GroupsApi {
  /// Creates the Groups client over the shared [ApiTransport].
  const GroupsApi(this._transport);

  final ApiTransport _transport;

  /// `POST /groups` — creates a new private group owned by the caller.
  Future<Result<GroupDto>> createGroup(String name) {
    return _transport.postObject<GroupDto>(
      '/groups',
      body: {'name': name},
      parse: GroupDto.fromJson,
    );
  }

  /// `GET /me/groups` — lists every group the caller belongs to.
  Future<Result<MyGroupsDto>> myGroups() {
    return _transport.getObject<MyGroupsDto>(
      '/me/groups',
      parse: MyGroupsDto.fromJson,
    );
  }

  /// `GET /groups/{groupId}` — reads the group, visible only to a member.
  Future<Result<GroupDto>> getGroup(String groupId) {
    return _transport.getObject<GroupDto>(
      '/groups/$groupId',
      parse: GroupDto.fromJson,
    );
  }

  /// `POST /groups/join` — joins a private group via its shareable invite
  /// code (the capability). Idempotent: an existing member gets their current
  /// membership back rather than a duplicate or an error.
  Future<Result<GroupMembershipDto>> joinByInvite(String inviteCode) {
    return _transport.postObject<GroupMembershipDto>(
      '/groups/join',
      body: {'invite_code': inviteCode},
      parse: GroupMembershipDto.fromJson,
    );
  }

  /// `GET /groups/{groupId}/members` — the group's roster, joinedAt ascending
  /// (the owner first). Member-only visibility.
  Future<Result<GroupMembersDto>> listMembers(String groupId) {
    return _transport.getObject<GroupMembersDto>(
      '/groups/$groupId/members',
      parse: GroupMembersDto.fromJson,
    );
  }

  /// `GET /groups/{groupId}/seasons/{seasonId}/leaderboard` — the group's
  /// ranked standings for a season, filtered from the same season-standings
  /// projection (no new points source).
  Future<Result<GroupLeaderboardDto>> leaderboard(
    String groupId,
    String seasonId,
  ) {
    return _transport.getObject<GroupLeaderboardDto>(
      '/groups/$groupId/seasons/$seasonId/leaderboard',
      parse: GroupLeaderboardDto.fromJson,
    );
  }

  /// `GET /groups/{groupId}/feed` — the group's activity feed, newest first.
  /// [limit] is an optional cap; the server clamps an untrusted value rather
  /// than rejecting it.
  Future<Result<GroupActivityFeedDto>> feed(String groupId, {int? limit}) {
    return _transport.getObject<GroupActivityFeedDto>(
      '/groups/$groupId/feed',
      query: limit == null ? null : {'limit': '$limit'},
      parse: GroupActivityFeedDto.fromJson,
    );
  }
}
