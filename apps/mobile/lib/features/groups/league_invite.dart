/// The friends' league (phase 2 of the plan): its month board, the link
/// that invites a friend in one tap, and who to invite first.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/providers.dart';
import '../gamification/invite_friends_screen.dart' show inviteWebBase;

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

/// The players [mine] faced most in duels, most first, at most [limit].
List<String> frequentOpponents(MyDuelsDto mine, {int limit = 3}) {
  final Map<String, int> times = <String, int>{};
  final Map<String, String> names = <String, String>{};
  for (final DuelSummaryDto d in mine.duels) {
    if (d.opponentName.trim().isEmpty) continue;
    times.update(d.opponentUserId, (n) => n + 1, ifAbsent: () => 1);
    names[d.opponentUserId] = d.opponentName;
  }
  final List<String> ids = times.keys.toList()
    ..sort((a, b) => times[b]!.compareTo(times[a]!));
  return <String>[for (final String id in ids.take(limit)) names[id]!];
}
