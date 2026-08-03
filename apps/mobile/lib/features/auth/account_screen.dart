library;

import 'dart:async';
import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/ui/app_button.dart';
import '../../l10n/app_localizations.dart';
import '../admin/admin_dashboard_screen.dart';
import '../competition/competition_list_screen.dart';
import '../groups/create_group_screen.dart';
import '../groups/join_group_screen.dart';
import '../hall_of_fame/hall_of_fame_screen.dart';
import '../history/prediction_history_screen.dart';
import '../notifications/notifications_providers.dart';
import '../notifications/notifications_screen.dart';
import 'session_controller.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({required this.user, super.key});
  final AuthenticatedUserDto user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<int> unread = ref.watch(unreadCountProvider);
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          IconButton(
            key: const Key('account.notifications'),
            tooltip: l10n.notifications,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const NotificationsScreen(),
              ),
            ),
            icon: Badge(
              key: const Key('account.notifications.badge'),
              label: unread.maybeWhen(
                data: (count) => count > 0 ? Text('$count') : null,
                orElse: () => null,
              ),
              isLabelVisible: unread.maybeWhen(
                data: (count) => count > 0,
                orElse: () => false,
              ),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
          IconButton(
            key: const Key('account.signOut'),
            tooltip: l10n.signOut,
            icon: const Icon(Icons.logout),
            onPressed: () => unawaited(
              ref.read(sessionControllerProvider.notifier).signOut(),
            ),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: tokens.backgroundGradient),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.maxAccountWidth,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.signedIn,
                    key: const Key('account.title'),
                    style: text.headlineSmall?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _Field(
                    label: l10n.userId,
                    value: user.userId,
                    valueKey: const Key('account.userId'),
                    tokens: tokens,
                    text: text,
                  ),
                  _Field(
                    label: l10n.role,
                    value: user.role,
                    valueKey: const Key('account.role'),
                    tokens: tokens,
                    text: text,
                  ),
                  _Field(
                    label: l10n.status,
                    value: user.status,
                    valueKey: const Key('account.status'),
                    tokens: tokens,
                    text: text,
                  ),
                  if (user.email != null)
                    _Field(
                      label: l10n.email,
                      value: user.email!,
                      valueKey: const Key('account.email'),
                      tokens: tokens,
                      text: text,
                    ),
                  const SizedBox(height: AppSpacing.xl),
                  AppButton(
                    key: const Key('account.browseCompetitions'),
                    label: l10n.browseCompetitions,
                    icon: Icons.emoji_events_outlined,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const CompetitionListScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    key: const Key('account.hallOfFame'),
                    label: l10n.hallOfFame,
                    icon: Icons.workspace_premium_outlined,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const HallOfFameScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    key: const Key('account.myPredictions'),
                    label: l10n.myPredictions,
                    icon: Icons.history_outlined,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PredictionHistoryScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    key: const Key('account.createGroup'),
                    label: l10n.createGroup,
                    icon: Icons.group_add_outlined,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const CreateGroupScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    key: const Key('account.joinGroup'),
                    label: l10n.joinGroup,
                    icon: Icons.group_outlined,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const JoinGroupScreen(),
                      ),
                    ),
                  ),
                  if (user.role == 'admin') ...[
                    const SizedBox(height: AppSpacing.md),
                    AppButton(
                      key: const Key('account.adminDashboard'),
                      label: l10n.adminDashboard,
                      icon: Icons.admin_panel_settings_outlined,
                      variant: AppButtonVariant.secondary,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AdminDashboardScreen(),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    required this.valueKey,
    required this.tokens,
    required this.text,
  });

  final String label;
  final String value;
  final Key valueKey;
  final AppTokens tokens;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: text.labelSmall?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: tokens.surfaceElevated,
              borderRadius: AppRadius.brMd,
              border: Border.all(color: tokens.border),
            ),
            child: Text(
              value,
              key: valueKey,
              style: text.bodyMedium?.copyWith(color: tokens.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
