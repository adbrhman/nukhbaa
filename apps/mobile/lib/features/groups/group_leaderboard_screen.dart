library;
import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../competition/widgets/async_list_view.dart';
import 'groups_providers.dart';

/// A group's ranked standings for one season — the same visual shape as
/// `SeasonLeaderboardScreen`, filtered to the group's members.
class GroupLeaderboardScreen extends ConsumerWidget {
  const GroupLeaderboardScreen({required this.groupId, required this.seasonId, required this.groupName, super.key});
  final String groupId;
  final String seasonId;
  final String groupName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<GroupLeaderboardDto> standings = ref.watch(groupLeaderboardProvider(groupId, seasonId));
    return Scaffold(
      appBar: AppBar(title: Text('$groupName — Leaderboard', key: const Key('groupLeaderboard.title'))),
      body: AsyncListView<GroupLeaderboardEntryDto>(
        value: standings.whenData((board) => board.entries),
        emptyMessage: 'No members of this group have joined the season yet.',
        onRetry: () => ref.invalidate(groupLeaderboardProvider(groupId, seasonId)),
        itemBuilder: (context, entry) => _GroupLeaderboardRow(entry: entry),
      ),
    );
  }
}

class _GroupLeaderboardRow extends StatelessWidget {
  const _GroupLeaderboardRow({required this.entry});
  final GroupLeaderboardEntryDto entry;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('groupLeaderboard.item.${entry.participantId}'),
      leading: CircleAvatar(child: Text('${entry.rank}', key: Key('groupLeaderboard.rank.${entry.participantId}'))),
      title: Text(entry.userId, key: Key('groupLeaderboard.user.${entry.participantId}'), style: const TextStyle(color: AppColors.textPrimary)),
      subtitle: Text('${entry.entryCount} entries counted', key: Key('groupLeaderboard.entries.${entry.participantId}')),
      trailing: Text('${entry.totalPoints} pts', key: Key('groupLeaderboard.points.${entry.participantId}'), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
    );
  }
}
