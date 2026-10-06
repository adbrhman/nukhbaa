library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/analytics/screen_views.dart';
import '../../core/design/app_typography.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../competition/widgets/async_list_view.dart';
import '../duels/duels_screen.dart';
import 'notifications_providers.dart';

/// Opens an address taken from an announcement.
///
/// A provider so a test can see which address was opened without a real
/// browser; in the app it hands the address to the system (browser, WhatsApp).
final Provider<Future<bool> Function(Uri uri)> notificationLinkOpenerProvider =
    Provider<Future<bool> Function(Uri uri)>(
      (ref) =>
          (Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
    );

/// The caller's own notification inbox, newest first, with a "mark read"
/// affordance per unread row.
class NotificationsScreen extends ConsumerWidget implements NamedScreen {
  @override
  String get screenName => ScreenNames.notifications;

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

/// Matches an https address in free text. Only characters legal in a URL are
/// accepted, so the match stops at the first Arabic letter or Arabic mark.
final RegExp _httpsLink = RegExp(
  r"https://[A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=%]+",
  caseSensitive: false,
);

/// Drops sentence punctuation that trails an address but is not part of it.
String _withoutTrailingPunctuation(String address) {
  const String trailing = '.,;:!?)';
  int end = address.length;
  while (end > 0 && trailing.contains(address[end - 1])) {
    end--;
  }
  return address.substring(0, end);
}

/// The body of an announcement with every https address made tappable.
///
/// The address opens outside the app exactly as the admin typed it. Nothing
/// else is tappable: plain text stays plain and a non-https address is never
/// opened.
class _LinkifiedBody extends ConsumerStatefulWidget {
  const _LinkifiedBody({
    required this.text,
    required this.style,
    required this.linkStyle,
    super.key,
  });

  final String text;
  final TextStyle style;
  final TextStyle linkStyle;

  @override
  ConsumerState<_LinkifiedBody> createState() => _LinkifiedBodyState();
}

class _LinkifiedBodyState extends ConsumerState<_LinkifiedBody> {
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _releaseRecognizers();
    super.dispose();
  }

  void _releaseRecognizers() {
    for (final TapGestureRecognizer recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  Future<void> _open(Uri uri) async {
    try {
      await ref.read(notificationLinkOpenerProvider)(uri);
    } on Object {
      // No app could open the address; the row stays as it was.
    }
  }

  @override
  Widget build(BuildContext context) {
    _releaseRecognizers();
    final String text = widget.text;
    final List<InlineSpan> spans = <InlineSpan>[];
    int cursor = 0;
    for (final RegExpMatch match in _httpsLink.allMatches(text)) {
      final String address = _withoutTrailingPunctuation(match.group(0)!);
      final Uri? uri = Uri.tryParse(address);
      if (uri == null || uri.host.isEmpty) {
        continue;
      }
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final TapGestureRecognizer recognizer = TapGestureRecognizer()
        ..onTap = () => _open(uri);
      _recognizers.add(recognizer);
      // A left-to-right mark after the address keeps a closing slash on its
      // right inside right-to-left text instead of jumping to the front.
      spans.add(
        TextSpan(
          text: '$address\u200E',
          style: widget.linkStyle,
          recognizer: recognizer,
        ),
      );
      cursor = match.start + address.length;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return Text.rich(TextSpan(children: spans), style: widget.style);
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
    'duel_challenged' || 'duel_accepted' => Icons.compare_arrows_rounded,
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
      'duel_challenged' => 'لاعب يتحداك على مباراة. اضغط لتتوقّع.',
      'duel_accepted' => 'قُبل تحديك. تابع المواجهة.',
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

  /// Marks [id] read while this row's page may already be covered: the
  /// controller is auto-disposed, so a listener holds it until the call
  /// and its invalidations finish.
  static Future<void> _markReadKeptAlive(
    BuildContext context,
    String id,
  ) async {
    final ProviderContainer container = ProviderScope.containerOf(
      context,
      listen: false,
    );
    final ProviderSubscription<void> hold = container.listen<void>(
      notificationControllerProvider,
      (_, _) {},
    );
    try {
      await container
          .read(notificationControllerProvider.notifier)
          .markRead(id);
    } finally {
      hold.close();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens tokens = context.tokens;
    final String? body = notification.body;
    final bool hasBody = body != null && body.isNotEmpty;
    final bool isDuel = notification.kind.startsWith('duel_');
    return ListTile(
      key: Key('notifications.item.${notification.id}'),
      // A duel row opens the Duels page, where the challenge waits.
      onTap: isDuel
          ? () {
              if (!notification.read) {
                unawaited(_markReadKeptAlive(context, notification.id));
              }
              unawaited(
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(builder: (_) => const DuelsScreen()),
                ),
              );
            }
          : null,
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
            _LinkifiedBody(
              key: Key('notifications.body.${notification.id}'),
              text: body,
              style: TextStyle(color: tokens.textPrimary),
              linkStyle: TextStyle(
                color: tokens.primaryText,
                decoration: TextDecoration.underline,
                decorationColor: tokens.primaryText,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            _formatDate(notification.createdAt),
            key: Key('notifications.createdAt.${notification.id}'),
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: AppFontSize.s12,
            ),
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
