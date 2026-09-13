library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../l10n/app_localizations.dart';
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
      backgroundColor: context.tokens.background,
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context).notifications,
          key: const Key('notifications.title'),
        ),
      ),
      body: AsyncListView<NotificationDto>(
        value: inbox.whenData((dto) => dto.notifications),
        emptyMessage: AppLocalizations.of(context).notificationsEmpty,
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
    'fixture_scored' => Icons.sports_soccer_outlined,
    'group_member_joined' => Icons.group_add_outlined,
    'reaction_received' => Icons.favorite_border,
    'admin_announcement' => Icons.campaign_outlined,
    _ => Icons.notifications_outlined,
  };

  /// العنوان المعروض: نصّ المشرف إن وُجد، وإلا وصف مقروء للنوع.
  ///
  /// النصّ الحر يصل جاهزًا من الخادم (`title`/`body`) لأنّه يخصّ إعلانًا
  /// بعينه؛ أمّا بقيّة الأنواع فلا نصّ لها أصلًا، فتُترجَم من الرمز. الرمز
  /// الخام (`fixture_scored`) لم يعد يظهر للمستخدم في أي حال.
  static String _titleFor(BuildContext context, NotificationDto notification) {
    final String? title = notification.title;
    if (title != null && title.isNotEmpty) {
      return title;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    return switch (notification.kind) {
      'round_scored' => l10n.notificationRoundScored,
      'fixture_scored' => l10n.notificationFixtureScored,
      'group_member_joined' => l10n.notificationGroupMemberJoined,
      'reaction_received' => l10n.notificationReactionReceived,
      'admin_announcement' => l10n.notificationAdminAnnouncement,
      _ => l10n.notificationsTitle,
    };
  }

  /// تاريخ مقروء بالتوقيت المحلّي بدل طابع ISO الخام.
  static String _formatDate(String iso) {
    final DateTime? parsed = DateTime.tryParse(iso);
    if (parsed == null) {
      return iso;
    }
    final DateTime local = parsed.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}/${two(local.month)}/${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens tokens = context.tokens;
    final String? body = notification.body;
    final bool hasBody = body != null && body.isNotEmpty;
    return ListTile(
      key: Key('notifications.item.${notification.id}'),
      isThreeLine: hasBody,
      leading: Icon(
        _iconFor(notification.kind),
        color: notification.read ? tokens.textSecondary : tokens.primary,
      ),
      title: Text(
        _titleFor(context, notification),
        key: Key('notifications.label.${notification.id}'),
        style: TextStyle(
          color: tokens.textPrimary,
          fontWeight: notification.read ? FontWeight.w500 : FontWeight.w700,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasBody) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              body,
              key: Key('notifications.body.${notification.id}'),
              style: TextStyle(color: tokens.textPrimary),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            _formatDate(notification.createdAt),
            key: Key('notifications.createdAt.${notification.id}'),
            style: TextStyle(color: tokens.textSecondary, fontSize: 12),
          ),
        ],
      ),
      trailing: notification.read
          ? null
          : IconButton(
              key: Key('notifications.markRead.${notification.id}'),
              icon: const Icon(Icons.mark_email_read_outlined),
              tooltip: AppLocalizations.of(context).markNotificationRead,
              onPressed: () => ref
                  .read(notificationControllerProvider.notifier)
                  .markRead(notification.id),
            ),
    );
  }
}
