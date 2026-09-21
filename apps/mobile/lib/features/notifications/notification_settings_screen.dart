/// The notification settings page (P3-1): the switches the server keeps in
/// `notification_preferences`, read from and written to
/// `/me/notification-preferences`.
///
/// The server is the record. The switch shows what the server answered, and
/// a write that fails leaves it where it was, with a message -- the page
/// never shows a setting the server does not hold.
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
  bool? _stored;

  /// True while a write is in flight: the switch is disabled so two taps
  /// cannot race each other to the server.
  bool _saving = false;

  Future<void> _setReminder(bool on) async {
    setState(() => _saving = true);
    final Result<NotificationPreferencesDto> result = await ref
        .read(authApiProvider)
        .updateNotificationPreferences(predictionReminder: on);
    if (!mounted) {
      return;
    }
    switch (result) {
      case Ok<NotificationPreferencesDto>(:final value):
        setState(() {
          _stored = value.predictionReminder;
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
        builder: (context, preferences) {
          final bool reminderOn = _stored ?? preferences.predictionReminder;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: <Widget>[
              AccountMenuCard(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.alarm_rounded,
                          color: tokens.primary,
                          size: AppSizes.iconLg,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                l10n.notificationSettingsReminderTitle,
                                style: context.text.bodyLarge?.copyWith(
                                  color: tokens.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                l10n.notificationSettingsReminderHint,
                                style: context.text.bodySmall?.copyWith(
                                  color: tokens.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Switch(
                          key: const Key(
                            'notifications.settings.predictionReminder',
                          ),
                          value: reminderOn,
                          onChanged: _saving ? null : _setReminder,
                        ),
                      ],
                    ),
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
