library;

import 'dart:async';
import 'package:contracts/contracts.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/error/error_presenter.dart';
import '../../core/ui/app_button.dart';
import '../../core/ui/app_text_field.dart';
import '../../l10n/app_localizations.dart';
import '../admin/admin_hub_screen.dart';
import '../competition/my_active_seasons_screen.dart';
import '../groups/create_group_screen.dart';
import '../groups/my_groups_screen.dart';
import '../groups/join_group_screen.dart';
import '../hall_of_fame/hall_of_fame_screen.dart';
import '../fixture_prediction/current_month_fixtures_screen.dart';
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
                  _DisplayNameRow(
                    displayName: user.displayName,
                    tokens: tokens,
                    text: text,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  // Raw identity fields (id/role/status/email) are debug-only
                  // diagnostics, never production UI (next-task.md #1) - kept
                  // behind kDebugMode instead of deleted so the team can still
                  // inspect the signed-in principal while developing/testing.
                  if (kDebugMode) ...[
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
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  AppButton(
                    key: const Key('account.matches'),
                    label: l10n.matchesTitle,
                    icon: Icons.sports_soccer,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const CurrentMonthFixturesScreen(),
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
                    key: const Key('account.myActiveSeasons'),
                    label: l10n.myActiveSeasons,
                    icon: Icons.calendar_month_outlined,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const MyActiveSeasonsScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    key: const Key('account.myGroups'),
                    label: l10n.myGroups,
                    icon: Icons.groups_outlined,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const MyGroupsScreen(),
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
                          builder: (_) => const AdminHubScreen(),
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

class _DisplayNameRow extends StatelessWidget {
  const _DisplayNameRow({
    required this.displayName,
    required this.tokens,
    required this.text,
  });

  final String displayName;
  final AppTokens tokens;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Container(
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
      child: Row(
        children: [
          Expanded(
            child: Text(
              displayName,
              key: const Key('account.displayName'),
              style: text.titleMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            key: const Key('account.editDisplayName'),
            tooltip: l10n.changeDisplayName,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  _ChangeDisplayNameDialog(currentName: displayName),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChangeDisplayNameDialog extends ConsumerStatefulWidget {
  const _ChangeDisplayNameDialog({required this.currentName});
  final String currentName;

  @override
  ConsumerState<_ChangeDisplayNameDialog> createState() =>
      _ChangeDisplayNameDialogState();
}

class _ChangeDisplayNameDialogState
    extends ConsumerState<_ChangeDisplayNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.currentName,
  );
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _submitting = false;
  AppError? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await ref
        .read(sessionControllerProvider.notifier)
        .updateDisplayName(_controller.text.trim());
    if (!mounted) return;
    switch (result) {
      case Ok<void>():
        Navigator.of(context).pop();
      case Err<void>(:final error):
        setState(() {
          _submitting = false;
          _error = error;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.changeDisplayName),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              fieldKey: const Key('account.displayNameField'),
              controller: _controller,
              enabled: !_submitting,
              label: l10n.displayName,
              hint: l10n.displayNameHint,
              prefixIcon: Icons.person_outline,
              autofillHints: const [AutofillHints.name],
              validator: (String? value) =>
                  (value == null || value.trim().isEmpty)
                  ? l10n.displayNameRequired
                  : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                ErrorPresenter.message(_error!),
                key: const Key('account.displayNameError'),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: context.tokens.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        AppButton(
          key: const Key('account.saveDisplayName'),
          label: l10n.save,
          loading: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
      ],
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
