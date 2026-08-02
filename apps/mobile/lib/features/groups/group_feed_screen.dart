library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/design/app_tokens.dart';
import '../competition/widgets/async_list_view.dart';
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
    final AsyncValue<GroupActivityFeedDto> feed = ref.watch(
      groupFeedProvider(groupId),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text('$groupName — Activity', key: const Key('groupFeed.title')),
      ),
      body: AsyncListView<ActivityEventDto>(
        value: feed.whenData((dto) => dto.events),
        emptyMessage: 'No activity yet in this group.',
        onRetry: () => ref.invalidate(groupFeedProvider(groupId)),
        itemBuilder: (context, event) => _FeedRow(event: event),
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

  static String _labelFor(ActivityEventDto event) => switch (event.type) {
    'round_scored' => 'A round was scored',
    'member_joined' => 'A new member joined',
    'rank_shift' =>
      event.oldRank != null && event.newRank != null
          ? 'Rank moved ${event.oldRank} → ${event.newRank}'
          : 'A rank changed',
    _ => event.type,
  };

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return ListTile(
      key: Key('groupFeed.item.${event.groupId}.${event.occurredAt}'),
      leading: Icon(_iconFor(event.type), color: tokens.textSecondary),
      title: Text(
        _labelFor(event),
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
