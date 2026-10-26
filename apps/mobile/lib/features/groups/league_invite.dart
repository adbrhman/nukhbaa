/// The friends' league (phase 2 of the plan): its month board and the link
/// that invites a friend in one tap.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/config/web_links.dart';
import '../../core/providers.dart';

/// A group's board for a month contest.
typedef GroupMonthBoardKey = ({String groupId, String seasonId});

/// `GET /groups/{id}/seasons/{seasonId}/month-board`: the month's board of
/// the group's members, ranked among them by the server. A failed read
/// shows its error on the board rather than retrying behind it.
final groupMonthBoardProvider = FutureProvider.autoDispose
    .family<FixtureLeaderboardDto, GroupMonthBoardKey>((ref, key) async {
      final api = ref.watch(groupsApiProvider);
      final result = await api.monthBoard(key.groupId, key.seasonId);
      return switch (result) {
        Ok<FixtureLeaderboardDto>(:final value) => value,
        Err<FixtureLeaderboardDto>(:final error) => throw error,
      };
    }, retry: (_, _) => null);

/// The link that opens the app on the invitation to [inviteCode]'s league.
String leagueLinkFor(String inviteCode) => '$inviteWebBase?league=$inviteCode';

/// What a player sends to invite a friend into [group].
String leagueShareText(GroupDto group) =>
    'انضم إلى دوري «${group.name}» في نُخبة، ونتنافس على ترتيب الشهر.\n'
    '${leagueLinkFor(group.inviteCode)}\n'
    'أو أدخل الرمز: ${group.inviteCode}';
