library;

import 'dart:async';
import 'package:contracts/contracts.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared/shared.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/error/error_presenter.dart';
import '../../core/ui/app_button.dart';
import '../../core/ui/app_text_field.dart';
import '../../core/ui/forward_chevron.dart';
import '../../core/ui/user_avatar.dart';
import '../../l10n/app_localizations.dart';
import '../admin/admin_hub_screen.dart';
import '../groups/create_group_screen.dart';
import '../groups/my_groups_screen.dart';
import '../groups/join_group_screen.dart';
import '../record/elite_card_screen.dart';
import '../record/my_seasons_screen.dart';
import '../record/season_record_screen.dart';
import '../record/season_record_providers.dart';
import '../record/my_points_screen.dart';
import '../fixture_prediction/current_month_fixtures_screen.dart';
import '../fixture_prediction/current_month_fixtures_providers.dart';
import '../history/prediction_history_screen.dart';
import '../notifications/notifications_providers.dart';
import '../notifications/notifications_screen.dart';
import '../../core/theme/theme_controller.dart';
import 'session_controller.dart';

/// The signed-in user's home hub — a card-based dashboard replacing the flat
/// button list. Every destination below already existed as a plain
/// [AppButton] target; this is a visual restyle only (same providers, same
/// navigation, same `account.*` keys), not a new architecture or data
/// source. Cross-season stats ARE shown now, via the elite card: `GET
/// /me/seasons` is the server-side aggregate whose absence this comment used
/// to record. Nothing is still fabricated on the client -- every figure on
/// that card is a fold over rows the server ruled on.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({required this.user, super.key});
  final AuthenticatedUserDto user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<int> unread = ref.watch(unreadCountProvider);
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;
    final AppLocalizations l10n = AppLocalizations.of(context);

    // Warm the two destinations most likely to be opened from this hub. Both
    // providers are non-auto-disposed singletons, so this starts the request
    // once and makes the subsequent navigation feel immediate.
    ref.read(currentMonthFixturesProvider);
    ref.read(mySeasonRecordsProvider);

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        title: Text(l10n.appTitle, key: const Key('account.title')),
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
      body: SafeArea(
        bottom: true,
        top: false,
        child: DecoratedBox(
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
                      avatarUrl: user.avatarUrl,
                      tokens: tokens,
                      text: text,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const _DarkModeToggle(),
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
                    LayoutBuilder(
                      builder: (context, constraints) {
                        const gap = AppSpacing.md;
                        final int columns = constraints.maxWidth >= 680 ? 3 : 2;
                        final double width =
                            (constraints.maxWidth - gap * (columns - 1)) /
                            columns;
                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            SizedBox(
                              width: width,
                              child: _HomeActionCard(
                                itemKey: const Key('account.myPoints'),
                                icon: Icons.auto_graph_outlined,
                                label: l10n.myPoints,
                                tokens: tokens,
                                text: text,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const MyPointsScreen(),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: _HomeActionCard(
                                itemKey: const Key('account.myPredictions'),
                                icon: Icons.history_outlined,
                                label: l10n.myPredictions,
                                tokens: tokens,
                                text: text,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        const PredictionHistoryScreen(),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: _HomeActionCard(
                                itemKey: const Key('account.eliteCard'),
                                icon: Icons.badge_outlined,
                                label: l10n.eliteCard,
                                tokens: tokens,
                                text: text,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => EliteCardScreen(user: user),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _SectionHeader(
                      title: l10n.seasonRecord,
                      tokens: tokens,
                      text: text,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _HomeListCard(
                      itemKey: const Key('account.seasonRecord'),
                      icon: Icons.emoji_events_outlined,
                      label: l10n.seasonRecord,
                      tokens: tokens,
                      text: text,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SeasonRecordScreen(),
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
                    _HomeListCard(
                      itemKey: const Key('account.mySeasons'),
                      icon: Icons.calendar_month_outlined,
                      label: l10n.mySeasonsLabel,
                      tokens: tokens,
                      text: text,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const MySeasonsScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    IntrinsicHeight(
                      child: Row(
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
      ),
    );
  }
}

/// Avatar (first letter of [displayName]) + name + edit affordance, replacing
/// the old plain-text `_DisplayNameRow`. Same edit dialog/behavior as before.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.displayName,
    required this.avatarUrl,
    required this.tokens,
    required this.text,
  });

  final String displayName;
  final String? avatarUrl;
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
          // The picture is its own affordance: tapping the avatar is how
          // you change it. No separate button, because the thing you want to
          // change is the thing you are looking at.
          InkWell(
            key: const Key('account.changeAvatar'),
            customBorder: const CircleBorder(),
            onTap: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => _AvatarSheet(hasAvatar: avatarUrl != null),
            ),
            child: UserAvatar(
              displayName: displayName,
              avatarUrl: avatarUrl,
              size: AppSizes.avatarSm,
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

/// The picture actions, as a sheet rather than a dialog: two choices, one of
/// them destructive, and a sheet keeps the destructive one visibly separate
/// from the ordinary one.
class _AvatarSheet extends ConsumerStatefulWidget {
  const _AvatarSheet({required this.hasAvatar});

  final bool hasAvatar;

  @override
  ConsumerState<_AvatarSheet> createState() => _AvatarSheetState();
}

class _AvatarSheetState extends ConsumerState<_AvatarSheet> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: CircularProgressIndicator(),
            )
          else ...<Widget>[
            ListTile(
              key: const Key('account.avatar.choose'),
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.avatarChoose),
              onTap: _pick,
            ),
            if (widget.hasAvatar)
              ListTile(
                key: const Key('account.avatar.remove'),
                leading: Icon(
                  Icons.delete_outline,
                  color: context.tokens.error,
                ),
                title: Text(
                  l10n.avatarRemove,
                  style: TextStyle(color: context.tokens.error),
                ),
                onTap: _remove,
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _pick() async {
    setState(() => _busy = true);
    final AppLocalizations l10n = AppLocalizations.of(context);

    // The picker does the resizing. 512px square at 80% quality lands well
    // under the server's 512 KB cap for any photograph, so the upload is
    // shrunk before it leaves the device rather than rejected after it
    // arrives -- and a phone on mobile data does not pay to send a 4 MB
    // original that would only be scaled down anyway.
    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
      _report(l10n.avatarUploadFailed);
      return;
    }
    if (picked == null) {
      if (mounted) setState(() => _busy = false);
      return;
    }

    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    final result = await ref
        .read(sessionControllerProvider.notifier)
        .setAvatar(
          bytes: bytes,
          // The picker re-encodes to JPEG when it resizes, so the type is
          // known rather than guessed from the original file's extension.
          contentType: 'image/jpeg',
        );
    if (!mounted) return;

    switch (result) {
      case Ok<void>():
        Navigator.of(context).pop();
      case Err<void>(:final error):
        setState(() => _busy = false);
        _report(
          error.code == 'identity.avatar_too_large'
              ? l10n.avatarTooLarge
              : l10n.avatarUploadFailed,
        );
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final result = await ref
        .read(sessionControllerProvider.notifier)
        .removeAvatar();
    if (!mounted) return;
    switch (result) {
      case Ok<void>():
        Navigator.of(context).pop();
      case Err<void>():
        setState(() => _busy = false);
        _report(l10n.avatarUploadFailed);
    }
  }

  void _report(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// The one dark/light toggle for the whole app (§8) — reuses
/// [themeControllerProvider] verbatim, no new state mechanism. [ThemeMode]
/// is tri-valued (`system`/`light`/`dark`) but a [SwitchListTile] is binary,
/// so `system` reads as off (light) and [ThemeController.toggle] (already
/// binary light↔dark) drives the switch.
class _DarkModeToggle extends ConsumerWidget {
  const _DarkModeToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    final ThemeMode mode = ref.watch(themeControllerProvider);
    return Material(
      color: tokens.surfaceElevated,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.brMd,
        side: BorderSide(color: tokens.border),
      ),
      child: SwitchListTile(
        key: const Key('account.darkModeToggle'),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.brMd),
        activeThumbColor: tokens.primary,
        title: Text(
          l10n.accountDarkModeLabel,
          style: TextStyle(color: tokens.textPrimary),
        ),
        value: mode == ThemeMode.dark,
        onChanged: (_) => ref.read(themeControllerProvider.notifier).toggle(),
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
              ForwardChevron(color: tokens.onPrimary.withValues(alpha: 0.85)),
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
              ForwardChevron(color: tokens.textMuted),
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
