library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/design/app_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../competition/competition_providers.dart';
import '../competition/widgets/async_list_view.dart';
import 'group_leaderboard_screen.dart';
import 'groups_providers.dart';

/// A group's activity feed, newest first — a read-side projection over
/// already-ratified data (Social decision #2: no new table, never a source of
/// truth).
class GroupFeedScreen extends ConsumerWidget {
  const GroupFeedScreen({
    required this.groupId,
    required this.groupName,
    super.key,
  });
  final String groupId;
  final String groupName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<GroupActivityFeedDto> feed = ref.watch(
      groupFeedProvider(groupId),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.groupFeedTitle(groupName),
          key: const Key('groupFeed.title'),
        ),
        actions: [
          IconButton(
            key: const Key('groupFeed.viewLeaderboard'),
            tooltip: l10n.viewLeaderboardTooltip,
            icon: const Icon(Icons.leaderboard_outlined),
            onPressed: () => _openLeaderboard(context, ref, l10n),
          ),
        ],
      ),
      body: AsyncListView<ActivityEventDto>(
        value: feed.whenData((dto) => dto.events),
        emptyMessage: l10n.groupFeedEmpty,
        onRetry: () => ref.invalidate(groupFeedProvider(groupId)),
        itemBuilder: (context, event) => _FeedRow(event: event),
      ),
    );
  }

  /// Opens this group's leaderboard. A group spans no single season on its
  /// own, so — mirroring how the fixtures screens pick the season a
  /// leaderboard icon opens — this resolves it from the caller's currently
  /// active seasons: straight through when there is exactly one, otherwise
  /// via a quick picker sheet.
  Future<void> _openLeaderboard(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final seasons = await ref.read(activeSeasonsProvider.future);
    if (!context.mounted) return;

    if (seasons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.groupLeaderboardNoActiveSeasons)),
      );
      return;
    }

    final ActiveSeasonDto? chosen = seasons.length == 1
        ? seasons.single
        : await showModalBottomSheet<ActiveSeasonDto>(
            context: context,
            builder: (sheetContext) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      l10n.groupLeaderboardSelectSeasonTitle,
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
                  ),
                  for (final season in seasons)
                    ListTile(
                      key: Key('groupFeed.seasonPicker.${season.seasonId}'),
                      title: Text(season.seasonLabel),
                      subtitle: Text(season.competitionName),
                      onTap: () => Navigator.of(sheetContext).pop(season),
                    ),
                ],
              ),
            ),
          );
    if (chosen == null || !context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupLeaderboardScreen(
          groupId: groupId,
          seasonId: chosen.seasonId,
          groupName: groupName,
        ),
      ),
    );
  }
}

class _FeedRow extends StatelessWidget {
  const _FeedRow({required this.event});
  final ActivityEventDto event;

  static IconData _iconFor(String type) => switch (type) {
    'round_scored' => Icons.emoji_events_outlined,
    'member_joined' => Icons.group_add_outlined,
    'rank_shift' => Icons.swap_vert,
    _ => Icons.circle_outlined,
  };

  static String _labelFor(ActivityEventDto event, AppLocalizations l10n) =>
      switch (event.type) {
        'round_scored' => l10n.activityRoundScored,
        'member_joined' => l10n.activityMemberJoined,
        'rank_shift' =>
          event.oldRank != null && event.newRank != null
              ? l10n.activityRankShift(event.oldRank!, event.newRank!)
              : l10n.activityRankShiftUnknown,
        _ => event.type,
      };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    return ListTile(
      key: Key('groupFeed.item.${event.groupId}.${event.occurredAt}'),
      leading: Icon(_iconFor(event.type), color: tokens.textSecondary),
      title: Text(
        _labelFor(event, l10n),
        key: Key('groupFeed.label.${event.occurredAt}'),
      ),
      subtitle: Text(
        event.occurredAt,
        key: Key('groupFeed.occurredAt.${event.occurredAt}'),
        style: TextStyle(color: tokens.textSecondary),
      ),
    );
  }
}
