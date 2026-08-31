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

/// The signed-in user's home hub — a card-based dashboard replacing the flat
/// button list. Every destination below already existed as a plain
/// [AppButton] target; this is a visual restyle only (same providers, same
/// navigation, same `account.*` keys), not a new architecture or data
/// source. No success-rate/points/rank stats are shown here: the server
/// exposes no cross-season aggregate for those (leaderboards are strictly
/// per-season, Axiom 2/5 — `leaderboards_providers.dart`), so nothing is
/// fabricated on the client.
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
                  _ProfileHeader(
                    displayName: user.displayName,
                    tokens: tokens,
                    text: text,
                  ),
                  // Raw identity fields (id/role/status/email) are debug-only
                  // diagnostics, never production UI - kept behind
                  // kDebugMode instead of deleted so the team can still
                  // inspect the signed-in principal while developing/testing.
                  if (kDebugMode) ...[
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
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  _MatchesCtaCard(
                    itemKey: const Key('account.matches'),
                    title: l10n.matchesTitle,
                    subtitle: l10n.homeMatchesSubtitle,
                    tokens: tokens,
                    text: text,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const CurrentMonthFixturesScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _SectionHeader(
                    title: l10n.homePerformanceSection,
                    tokens: tokens,
                    text: text,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _HomeActionCard(
                          itemKey: const Key('account.myPredictions'),
                          icon: Icons.history_outlined,
                          label: l10n.myPredictions,
                          tokens: tokens,
                          text: text,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const PredictionHistoryScreen(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _HomeActionCard(
                          itemKey: const Key('account.hallOfFame'),
                          icon: Icons.workspace_premium_outlined,
                          label: l10n.hallOfFame,
                          tokens: tokens,
                          text: text,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const HallOfFameScreen(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _SectionHeader(
                    title: l10n.myActiveSeasons,
                    tokens: tokens,
                    text: text,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _HomeListCard(
                    itemKey: const Key('account.myActiveSeasons'),
                    icon: Icons.calendar_month_outlined,
                    label: l10n.myActiveSeasons,
                    tokens: tokens,
                    text: text,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const MyActiveSeasonsScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _SectionHeader(
                    title: l10n.myGroups,
                    tokens: tokens,
                    text: text,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _HomeListCard(
                    itemKey: const Key('account.myGroups'),
                    icon: Icons.groups_outlined,
                    label: l10n.myGroups,
                    tokens: tokens,
                    text: text,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const MyGroupsScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _HomeActionCard(
                          itemKey: const Key('account.createGroup'),
                          icon: Icons.group_add_outlined,
                          label: l10n.createGroup,
                          tokens: tokens,
                          text: text,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const CreateGroupScreen(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _HomeActionCard(
                          itemKey: const Key('account.joinGroup'),
                          icon: Icons.group_outlined,
                          label: l10n.joinGroup,
                          tokens: tokens,
                          text: text,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const JoinGroupScreen(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (user.role == 'admin') ...[
                    const SizedBox(height: AppSpacing.xl),
                    _SectionHeader(
                      title: l10n.homeAdminSection,
                      tokens: tokens,
                      text: text,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _HomeListCard(
                      itemKey: const Key('account.adminDashboard'),
                      icon: Icons.admin_panel_settings_outlined,
                      label: l10n.adminDashboard,
                      tokens: tokens,
                      text: text,
                      onTap: () => Navigator.of(context).push(
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

/// Avatar (first letter of [displayName]) + name + edit affordance, replacing
/// the old plain-text `_DisplayNameRow`. Same edit dialog/behavior as before.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
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
    final String trimmed = displayName.trim();
    final String initial = trimmed.isEmpty
        ? '?'
        : trimmed.substring(0, 1).toUpperCase();
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
          Container(
            width: AppSizes.avatarSm,
            height: AppSizes.avatarSm,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: tokens.primaryGradient,
              shape: BoxShape.circle,
            ),
            child: Text(
              initial,
              style: text.titleLarge?.copyWith(
                color: tokens.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
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

/// A section title above a group of home cards.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.tokens,
    required this.text,
  });

  final String title;
  final AppTokens tokens;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: text.titleSmall?.copyWith(
        color: tokens.textSecondary,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// The big primary call-to-action card ("المباريات") — full-width, gradient.
class _MatchesCtaCard extends StatelessWidget {
  const _MatchesCtaCard({
    required this.itemKey,
    required this.title,
    required this.subtitle,
    required this.tokens,
    required this.text,
    required this.onTap,
  });

  final Key itemKey;
  final String title;
  final String subtitle;
  final AppTokens tokens;
  final TextTheme text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: itemKey,
      color: Colors.transparent,
      borderRadius: AppRadius.brLg,
      child: InkWell(
        borderRadius: AppRadius.brLg,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            gradient: tokens.primaryGradient,
            borderRadius: AppRadius.brLg,
            boxShadow: tokens.shadowMd,
          ),
          child: Row(
            children: [
              Container(
                width: AppSizes.avatarSm,
                height: AppSizes.avatarSm,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.onPrimary.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.sports_soccer,
                  color: tokens.onPrimary,
                  size: AppSizes.iconLg,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: text.titleMedium?.copyWith(
                        color: tokens.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subtitle,
                      style: text.bodySmall?.copyWith(
                        color: tokens.onPrimary.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_left,
                color: tokens.onPrimary.withValues(alpha: 0.85),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One square-ish tappable card used two-per-row (predictions/hall of fame,
/// create/join group).
class _HomeActionCard extends StatelessWidget {
  const _HomeActionCard({
    required this.itemKey,
    required this.icon,
    required this.label,
    required this.tokens,
    required this.text,
    required this.onTap,
  });

  final Key itemKey;
  final IconData icon;
  final String label;
  final AppTokens tokens;
  final TextTheme text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: itemKey,
      color: Colors.transparent,
      borderRadius: AppRadius.brMd,
      child: InkWell(
        borderRadius: AppRadius.brMd,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.lg,
          ),
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: AppRadius.brMd,
            border: Border.all(color: tokens.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: AppSizes.avatarSm,
                height: AppSizes.avatarSm,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.surfaceHigh,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: tokens.primary, size: AppSizes.iconMd),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One full-width tappable row card (active seasons / groups / admin).
class _HomeListCard extends StatelessWidget {
  const _HomeListCard({
    required this.itemKey,
    required this.icon,
    required this.label,
    required this.tokens,
    required this.text,
    required this.onTap,
  });

  final Key itemKey;
  final IconData icon;
  final String label;
  final AppTokens tokens;
  final TextTheme text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: itemKey,
      color: Colors.transparent,
      borderRadius: AppRadius.brMd,
      child: InkWell(
        borderRadius: AppRadius.brMd,
        onTap: onTap,
        child: Container(
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
              Container(
                width: AppSizes.avatarSm,
                height: AppSizes.avatarSm,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.surfaceHigh,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: tokens.primary, size: AppSizes.iconMd),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: text.bodyMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.chevron_left, color: tokens.textMuted),
            ],
          ),
        ),
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
