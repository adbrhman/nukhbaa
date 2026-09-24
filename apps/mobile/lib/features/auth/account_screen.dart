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
import '../../core/theme/theme_controller.dart';
import '../../core/ui/user_avatar.dart';
import '../../l10n/app_localizations.dart';
import '../admin/admin_hub_screen.dart';
import '../fixture_prediction/current_month_fixtures_providers.dart';
import '../fixture_prediction/current_month_fixtures_screen.dart';
import '../gamification/insights_screen.dart';
import '../gamification/my_badges_screen.dart';
import '../history/prediction_history_screen.dart';
import '../notifications/notifications_providers.dart';
import '../notifications/notifications_screen.dart';
import '../record/elite_card_screen.dart';
import '../record/my_points_screen.dart';
import '../record/season_record_providers.dart';
import 'account_settings_screen.dart';
import 'app_lock.dart';
import 'session_controller.dart';
import 'widgets/account_menu.dart';

/// The signed-in user's account tab: a profile card with this month's
/// figures, the personal destinations, the settings group and sign-out.
///
/// Every figure on the profile card is the server's: the current month's row
/// of `GET /me/seasons`, whose accuracy is computed exactly like the
/// leaderboard's (exact scorelines over decided fixtures), so the two
/// screens can never disagree. The admin dashboard row is rendered only for
/// the `admin` role; the server authorizes every admin call regardless.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({required this.user, super.key});
  final AuthenticatedUserDto user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<int> unread = ref.watch(unreadCountProvider);
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final MySeasonRecordDto? record = _currentRecord(
      ref.watch(mySeasonRecordsProvider).value,
    );
    final int unreadCount = unread.value ?? 0;

    // Warm the matches feed: it is the destination most likely to be opened
    // from here, and the provider is a non-auto-disposed singleton.
    ref.read(currentMonthFixturesProvider);

    void open(Widget page) => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        centerTitle: true,
        title: Text(l10n.appTitle, key: const Key('account.title')),
        actions: [
          IconButton(
            key: const Key('account.notifications'),
            tooltip: l10n.notifications,
            onPressed: () => open(const NotificationsScreen()),
            icon: Badge(
              key: const Key('account.notifications.badge'),
              label: unreadCount > 0 ? Text('$unreadCount') : null,
              isLabelVisible: unreadCount > 0,
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.maxAccountWidth,
            ),
            child: SingleChildScrollView(
              // The shell's bottom bar floats over the page, so the last
              // card must be able to scroll clear of it.
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                104,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ProfileCard(
                    user: user,
                    record: record,
                    tokens: tokens,
                    text: text,
                    l10n: l10n,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AccountMenuCard(
                    children: [
                      AccountMenuRow(
                        key: const Key('account.myPredictions'),
                        icon: Icons.bolt_rounded,
                        title: l10n.myPredictions,
                        subtitle: l10n.accountMyPredictionsSubtitle,
                        onTap: () => open(const PredictionHistoryScreen()),
                      ),
                      AccountMenuRow(
                        key: const Key('account.myPoints'),
                        icon: Icons.emoji_events_outlined,
                        title: l10n.myPoints,
                        subtitle: l10n.accountMyPointsSubtitle,
                        onTap: () => open(
                          MyPointsScreen(userDisplayName: user.displayName),
                        ),
                      ),
                      AccountMenuRow(
                        key: const Key('account.matches'),
                        icon: Icons.sports_soccer_outlined,
                        title: l10n.matchesTitle,
                        subtitle: l10n.homeMatchesSubtitle,
                        onTap: () => open(const CurrentMonthFixturesScreen()),
                      ),
                      AccountMenuRow(
                        key: const Key('account.eliteCard'),
                        icon: Icons.badge_outlined,
                        title: l10n.eliteCard,
                        subtitle: l10n.accountEliteCardSubtitle,
                        onTap: () => open(EliteCardScreen(user: user)),
                      ),
                      AccountMenuRow(
                        key: const Key('account.badges'),
                        icon: Icons.military_tech_outlined,
                        title: l10n.myBadges,
                        subtitle: l10n.accountBadgesSubtitle,
                        onTap: () => open(const MyBadgesScreen()),
                      ),
                      AccountMenuRow(
                        key: const Key('account.insights'),
                        icon: Icons.insights_rounded,
                        title: l10n.insightsTitle,
                        subtitle: l10n.insightsSubtitle,
                        onTap: () => open(const InsightsScreen()),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AccountMenuCard(
                    children: [
                      AccountMenuRow(
                        key: const Key('account.settings'),
                        icon: Icons.settings_outlined,
                        title: l10n.accountSettings,
                        onTap: () => open(const AccountSettingsScreen()),
                      ),
                      const _DarkModeRow(),
                      const BiometricUnlockRow(),
                      AccountMenuRow(
                        key: const Key('account.notificationsRow'),
                        icon: Icons.notifications_none_rounded,
                        title: l10n.notifications,
                        trailing: unreadCount > 0
                            ? Badge(label: Text('$unreadCount'))
                            : null,
                        onTap: () => open(const NotificationsScreen()),
                      ),
                      if (user.role == 'admin')
                        AccountMenuRow(
                          key: const Key('account.adminDashboard'),
                          icon: Icons.admin_panel_settings_outlined,
                          title: l10n.adminDashboard,
                          onTap: () => open(const AdminHubScreen()),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _SignOutCard(
                    label: l10n.signOut,
                    onTap: () => unawaited(
                      ref.read(sessionControllerProvider.notifier).signOut(),
                    ),
                  ),
                  // Raw identity fields (id/role/status/email) are debug-only
                  // diagnostics, never production UI.
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The row of the month in play, else the newest one the server listed.
  static MySeasonRecordDto? _currentRecord(List<MySeasonRecordDto>? records) {
    if (records == null || records.isEmpty) return null;
    final DateTime now = DateTime.now().toUtc();
    for (final MySeasonRecordDto record in records) {
      final DateTime? start = DateTime.tryParse(record.startAt)?.toUtc();
      final DateTime? end = DateTime.tryParse(record.endAt)?.toUtc();
      if (start != null &&
          end != null &&
          !now.isBefore(start) &&
          now.isBefore(end)) {
        return record;
      }
    }
    return records.first;
  }
}

/// Avatar and name, then this month's points, decided matches and accuracy.
/// There is no rename affordance: the display name is chosen once at
/// registration and is immutable afterwards.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.user,
    required this.record,
    required this.tokens,
    required this.text,
    required this.l10n,
  });

  final AuthenticatedUserDto user;
  final MySeasonRecordDto? record;
  final AppTokens tokens;
  final TextTheme text;
  final AppLocalizations l10n;

  static const double _avatarSize = 64;

  @override
  Widget build(BuildContext context) {
    final MySeasonRecordDto? row = record;
    final int? accuracy = row?.accuracyPercent;

    // Each figure is read with its label, as one node.
    Widget stat(String value, String label, Key valueKey) => Expanded(
      child: MergeSemantics(
        child: Column(
          children: [
            Text(
              value,
              key: valueKey,
              style: text.titleLarge?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: text.bodySmall?.copyWith(color: tokens.textSecondary),
            ),
          ],
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // The picture is its own affordance: tapping the avatar is how
              // you change it.
              // The avatar is a button with no text of its own: name it.
              Semantics(
                button: true,
                label: l10n.avatarChange,
                child: InkWell(
                  key: const Key('account.changeAvatar'),
                  customBorder: const CircleBorder(),
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) =>
                        _AvatarSheet(hasAvatar: user.avatarUrl != null),
                  ),
                  child: UserAvatar(
                    displayName: user.displayName,
                    avatarUrl: user.avatarUrl,
                    size: _avatarSize,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  user.displayName,
                  key: const Key('account.displayName'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleLarge?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Divider(height: 1, color: tokens.border),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              stat(
                accuracy == null ? '—' : '$accuracy%',
                l10n.accountStatAccuracy,
                const Key('account.stat.accuracy'),
              ),
              stat(
                row == null ? '—' : '${row.settledCount}',
                l10n.accountStatMatches,
                const Key('account.stat.matches'),
              ),
              stat(
                row == null ? '—' : '${row.totalPoints}',
                l10n.accountStatPoints,
                const Key('account.stat.points'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The one dark/light switch for the whole app, as a row of the settings
/// card. [ThemeMode] is tri-valued but the switch is binary, so `system`
/// reads as off and [ThemeController.toggle] drives it.
class _DarkModeRow extends ConsumerWidget {
  const _DarkModeRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    final ThemeMode mode = ref.watch(themeControllerProvider);
    return SwitchListTile(
      key: const Key('account.darkModeToggle'),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      secondary: Icon(
        Icons.dark_mode_outlined,
        color: tokens.primary,
        size: AppSizes.iconLg,
      ),
      activeThumbColor: tokens.primary,
      title: Text(
        l10n.accountDarkModeLabel,
        style: context.text.bodyLarge?.copyWith(
          color: tokens.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      value: mode == ThemeMode.dark,
      onChanged: (_) => ref.read(themeControllerProvider.notifier).toggle(),
    );
  }
}

/// Sign-out, on its own card in the danger colour.
class _SignOutCard extends StatelessWidget {
  const _SignOutCard({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return Material(
      color: tokens.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.brLg,
        side: BorderSide(color: tokens.controlBorder),
      ),
      child: InkWell(
        key: const Key('account.signOut'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: context.text.bodyLarge?.copyWith(
                    color: tokens.error,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(Icons.logout_rounded, color: tokens.error),
            ],
          ),
        ),
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

    // Reading the picked file is I/O like any other: a photo removed from
    // the gallery mid-flow, or a revoked read permission, threw straight out
    // of _pick and left _busy stuck true -- every control in the sheet dead
    // until the screen was closed and reopened.
    final List<int> bytes;
    try {
      bytes = await picked.readAsBytes();
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
      _report(l10n.avatarUploadFailed);
      return;
    }
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
