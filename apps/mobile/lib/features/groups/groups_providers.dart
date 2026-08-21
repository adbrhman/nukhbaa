/// The Groups **view** state (member roster, group leaderboard, activity feed)
/// plus the **create**/**join** command controllers.
///
/// Every visibility gate (member-only) lives server-side; this file never
/// supplies or fakes a membership decision. Create/join bind the caller from
/// the verified token — no owner/participant id is ever client-supplied.
library;

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';

part 'groups_providers.g.dart';

T _unwrap<T>(Result<T> result) => switch (result) {
  Ok<T>(:final value) => value,
  Err<T>(:final error) => throw error,
};

/// `GET /groups/{groupId}` — the group, visible only to a member.
@riverpod
Future<GroupDto> group(Ref ref, String groupId) async {
  final api = ref.watch(groupsApiProvider);
  return _unwrap(await api.getGroup(groupId));
}

/// `GET /groups/{groupId}/members` — the group's roster, owner first.
@riverpod
Future<GroupMembersDto> groupMembers(Ref ref, String groupId) async {
  final api = ref.watch(groupsApiProvider);
  return _unwrap(await api.listMembers(groupId));
}

/// `GET /groups/{groupId}/seasons/{seasonId}/leaderboard` — the group's ranked
/// standings for one season.
@riverpod
Future<GroupLeaderboardDto> groupLeaderboard(
  Ref ref,
  String groupId,
  String seasonId,
) async {
  final api = ref.watch(groupsApiProvider);
  return _unwrap(await api.leaderboard(groupId, seasonId));
}

/// `GET /groups/{groupId}/feed` — the group's activity feed, newest first.
@riverpod
Future<GroupActivityFeedDto> groupFeed(Ref ref, String groupId) async {
  final api = ref.watch(groupsApiProvider);
  return _unwrap(await api.feed(groupId));
}

/// `GET /me/groups` — every group the caller belongs to.
@riverpod
Future<MyGroupsDto> myGroups(Ref ref) async {
  final api = ref.watch(groupsApiProvider);
  return _unwrap(await api.myGroups());
}

/// Owns the `POST /groups` create command. A `family`-free single-shot
/// notifier: each screen instance drives its own [create] call and reads the
/// result directly rather than through persistent state, mirroring how a
/// short-lived form command is usually the simplest shape — but modelled as a
/// notifier (rather than a bare future) so a screen can disable its submit
/// button while [state] is in flight.
@riverpod
class CreateGroupController extends _$CreateGroupController {
  GroupsApi get _api => ref.read(groupsApiProvider);

  @override
  AsyncValue<GroupDto>? build() => null;

  /// Creates a new group named [name]. Leaves [state] at `null` (idle) until
  /// called; transitions to loading, then data/error.
  Future<void> create(String name) async {
    state = const AsyncValue.loading();
    final result = await _api.createGroup(name);
    state = switch (result) {
      Ok<GroupDto>(:final value) => AsyncValue.data(value),
      Err<GroupDto>(:final error) => AsyncValue.error(
        error,
        StackTrace.current,
      ),
    };
  }
}

/// Owns the `POST /groups/join` command (join-by-invite-code).
@riverpod
class JoinGroupController extends _$JoinGroupController {
  GroupsApi get _api => ref.read(groupsApiProvider);

  @override
  AsyncValue<GroupMembershipDto>? build() => null;

  /// Joins the group identified by [inviteCode]. Idempotent server-side: an
  /// existing member gets their current membership back.
  Future<void> join(String inviteCode) async {
    state = const AsyncValue.loading();
    final result = await _api.joinByInvite(inviteCode);
    state = switch (result) {
      Ok<GroupMembershipDto>(:final value) => AsyncValue.data(value),
      Err<GroupMembershipDto>(:final error) => AsyncValue.error(
        error,
        StackTrace.current,
      ),
    };
  }
}
