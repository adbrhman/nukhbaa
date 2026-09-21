/// The notification settings page (P3-1): the switches the server keeps in
/// `notification_preferences`, read from and written to
/// `/me/notification-preferences` -- the daily reminder and, from 0066, the
/// pre-match push.
///
/// The server is the record. A switch shows what the server answered, and a
/// write that fails leaves it where it was, with a message -- the page never
/// shows a setting the server does not hold.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../auth/widgets/account_menu.dart';
import '../competition/widgets/async_list_view.dart';

/// `GET /me/notification-preferences` -- the caller's switches, the defaults
/// (all on) for a caller who never changed anything.
final notificationPreferencesProvider =
    FutureProvider.autoDispose<NotificationPreferencesDto>((ref) async {
      final api = ref.watch(authApiProvider);
      return switch (await api.myNotificationPreferences()) {
        Ok<NotificationPreferencesDto>(:final value) => value,
        Err<NotificationPreferencesDto>(:final error) => throw error,
      };
    });

/// The notification settings page.
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  /// Creates the page.
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  /// What the last successful write stored; null until one succeeds, when
  /// the page shows what the read answered.
  NotificationPreferencesDto? _stored;

  /// True while a write is in flight: every switch is disabled so two taps
  /// cannot race each other to the server.
  bool _saving = false;

  Future<void> _save({bool? reminder, bool? preMatch}) async {
    setState(() => _saving = true);
    final Result<NotificationPreferencesDto> result = await ref
        .read(authApiProvider)
        .updateNotificationPreferences(
          predictionReminder: reminder,
          preMatch: preMatch,
        );
    if (!mounted) {
      return;
    }
    switch (result) {
      case Ok<NotificationPreferencesDto>(:final value):
        setState(() {
          _stored = value;
          _saving = false;
        });
      case Err<NotificationPreferencesDto>():
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).notificationSettingsSaveFailed,
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          l10n.notificationSettingsTitle,
          key: const Key('notifications.settings.title'),
        ),
      ),
      body: AsyncObjectView<NotificationPreferencesDto>(
        value: ref.watch(notificationPreferencesProvider),
        onRetry: () => ref.invalidate(notificationPreferencesProvider),
        builder: (context, read) {
          final NotificationPreferencesDto shown = _stored ?? read;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: <Widget>[
              AccountMenuCard(
                children: <Widget>[
                  _SwitchRow(
                    switchKey: const Key(
                      'notifications.settings.predictionReminder',
                    ),
                    icon: Icons.alarm_rounded,
                    title: l10n.notificationSettingsReminderTitle,
                    hint: l10n.notificationSettingsReminderHint,
                    value: shown.predictionReminder,
                    onChanged: _saving ? null : (on) => _save(reminder: on),
                  ),
                  _SwitchRow(
                    switchKey: const Key('notifications.settings.preMatch'),
                    icon: Icons.sports_soccer_rounded,
                    title: l10n.notificationSettingsPreMatchTitle,
                    hint: l10n.notificationSettingsPreMatchHint,
                    value: shown.preMatch,
                    onChanged: _saving ? null : (on) => _save(preMatch: on),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One switch with its icon, title and one-line explanation.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.switchKey,
    required this.icon,
    required this.title,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final Key switchKey;
  final IconData icon;
  final String title;
  final String hint;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: tokens.primary, size: AppSizes.iconLg),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: context.text.bodyLarge?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: context.text.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Switch(key: switchKey, value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
