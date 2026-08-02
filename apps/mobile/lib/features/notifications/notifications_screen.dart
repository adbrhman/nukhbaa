library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/design/app_tokens.dart';
import '../competition/widgets/async_list_view.dart';
import 'notifications_providers.dart';

/// The caller's own notification inbox, newest first, with a "mark read"
/// affordance per unread row.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<NotificationListDto> inbox = ref.watch(
      myNotificationsProvider,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications', key: Key('notifications.title')),
      ),
      body: AsyncListView<NotificationDto>(
        value: inbox.whenData((dto) => dto.notifications),
        emptyMessage: 'You have no notifications yet.',
        onRetry: () => ref.invalidate(myNotificationsProvider),
        itemBuilder: (context, notification) =>
            _NotificationRow(notification: notification),
      ),
    );
  }
}

class _NotificationRow extends ConsumerWidget {
  const _NotificationRow({required this.notification});
  final NotificationDto notification;

  static IconData _iconFor(String kind) => switch (kind) {
    'round_scored' => Icons.emoji_events_outlined,
    'group_member_joined' => Icons.group_add_outlined,
    'reaction_received' => Icons.favorite_border,
    _ => Icons.notifications_outlined,
  };

  static String _labelFor(String kind) => switch (kind) {
    'round_scored' => 'A round you predicted was scored',
    'group_member_joined' => 'Someone joined your group',
    'reaction_received' => 'You received a reaction',
    _ => kind,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens tokens = context.tokens;
    return ListTile(
      key: Key('notifications.item.${notification.id}'),
      leading: Icon(
        _iconFor(notification.kind),
        color: notification.read ? tokens.textSecondary : tokens.primary,
      ),
      title: Text(
        _labelFor(notification.kind),
        key: Key('notifications.label.${notification.id}'),
      ),
      subtitle: Text(
        notification.createdAt,
        key: Key('notifications.createdAt.${notification.id}'),
        style: TextStyle(color: tokens.textSecondary),
      ),
      trailing: notification.read
          ? null
          : IconButton(
              key: Key('notifications.markRead.${notification.id}'),
              icon: const Icon(Icons.mark_email_read_outlined),
              tooltip: 'Mark as read',
              onPressed: () => ref
                  .read(notificationControllerProvider.notifier)
                  .markRead(notification.id),
            ),
    );
  }
}
