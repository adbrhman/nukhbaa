library;
import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../competition/widgets/async_list_view.dart';
import 'leaderboards_providers.dart';
class SeasonLeaderboardScreen extends ConsumerWidget {
  const SeasonLeaderboardScreen({required this.seasonId, required this.seasonLabel, super.key});
  final String seasonId;
  final String seasonLabel;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<SeasonLeaderboardDto> standings = ref.watch(seasonLeaderboardProvider(seasonId));
    return Scaffold(
      appBar: AppBar(title: Text('$seasonLabel — Leaderboard', key: const Key('leaderboard.title'))),
      body: AsyncListView<LeaderboardEntryDto>(
        value: standings.whenData((board) => board.entries),
        emptyMessage: 'No one has joined this season yet.',
        onRetry: () => ref.invalidate(seasonLeaderboardProvider(seasonId)),
        itemBuilder: (context, entry) => _LeaderboardRow(entry: entry),
      ),
    );
  }
}
class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({required this.entry});
  final LeaderboardEntryDto entry;
  static String _pluralEntries(int count) => count == 1 ? '1 entry' : '$count entries';
  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('leaderboard.item.${entry.participantId}'),
      leading: CircleAvatar(child: Text('${entry.rank}', key: Key('leaderboard.rank.${entry.participantId}'))),
      title: Text(entry.participantId, key: Key('leaderboard.participant.${entry.participantId}'), style: const TextStyle(color: AppColors.textPrimary)),
      subtitle: Text('${_pluralEntries(entry.entryCount)} counted', key: Key('leaderboard.entries.${entry.participantId}')),
      trailing: Text('${entry.totalPoints} pts', key: Key('leaderboard.points.${entry.participantId}'), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
    );
  }
}
