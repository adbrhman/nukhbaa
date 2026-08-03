library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/design/app_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../competition/widgets/async_list_view.dart';
import 'groups_providers.dart';

/// A group's ranked standings for one season — the same visual shape as
/// `SeasonLeaderboardScreen`, filtered to the group's members.
class GroupLeaderboardScreen extends ConsumerWidget {
  const GroupLeaderboardScreen({
    required this.groupId,
    required this.seasonId,
    required this.groupName,
    super.key,
  });
  final String groupId;
  final String seasonId;
  final String groupName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<GroupLeaderboardDto> standings = ref.watch(
      groupLeaderboardProvider(groupId, seasonId),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.leaderboardTitle(groupName),
          key: const Key('groupLeaderboard.title'),
        ),
      ),
      body: AsyncListView<GroupLeaderboardEntryDto>(
        value: standings.whenData((board) => board.entries),
        emptyMessage: l10n.groupLeaderboardEmpty,
        onRetry: () =>
            ref.invalidate(groupLeaderboardProvider(groupId, seasonId)),
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
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    return ListTile(
      key: Key('groupLeaderboard.item.${entry.participantId}'),
      leading: CircleAvatar(
        child: Text(
          '${entry.rank}',
          key: Key('groupLeaderboard.rank.${entry.participantId}'),
        ),
      ),
      title: Text(
        entry.userId,
        key: Key('groupLeaderboard.user.${entry.participantId}'),
        style: TextStyle(color: tokens.textPrimary),
      ),
      subtitle: Text(
        l10n.leaderboardEntriesCounted(entry.entryCount),
        key: Key('groupLeaderboard.entries.${entry.participantId}'),
      ),
      trailing: Text(
        l10n.pointsAbbreviated(entry.totalPoints),
        key: Key('groupLeaderboard.points.${entry.participantId}'),
        style: TextStyle(fontWeight: FontWeight.bold, color: tokens.primary),
      ),
    );
  }
}
