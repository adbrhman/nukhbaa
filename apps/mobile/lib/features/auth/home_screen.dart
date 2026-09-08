import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/ui/app_button.dart';
import '../../core/ui/streak_chip.dart';
import '../competition/competition_providers.dart';
import '../competition/team_identity.dart';
import '../competition/teams_providers.dart';
import '../fixture_prediction/current_month_fixtures_providers.dart';
import '../fixture_prediction/fixture_predict_sheet.dart';
import '../fixture_prediction/kickoff_countdown.dart';
import 'pending_predictions_provider.dart';

/// The real authenticated home surface. It is intentionally a read-only
/// summary: fixtures and active seasons come from server-backed providers,
/// while detailed prediction and leaderboard flows remain in their own tabs.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    required this.user,
    required this.onOpenMatches,
    required this.onOpenPredictions,
    required this.onOpenLeaderboards,
    required this.onOpenAccount,
    super.key,
  });

  final AuthenticatedUserDto user;
  final VoidCallback onOpenMatches;
  final VoidCallback onOpenPredictions;
  final VoidCallback onOpenLeaderboards;
  final VoidCallback onOpenAccount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final fixtures = ref.watch(currentMonthFixturesProvider);
    final seasons = ref.watch(activeSeasonsProvider);
    final teamCatalog = ref.watch(teamCatalogProvider).value;
    final name = user.displayName.trim().isEmpty ? 'المتنبئ' : user.displayName;

    return Scaffold(
      backgroundColor: tokens.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(currentMonthFixturesProvider);
            ref.invalidate(activeSeasonsProvider);
            try {
              await ref.read(currentMonthFixturesProvider.future);
            } on Object {
              // The provider keeps the error visible in the page; a pull to
              // refresh should still finish its gesture normally.
            }
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 104),
            children: <Widget>[
              _HomeHeader(
                onNotifications: onOpenAccount,
                onAccount: onOpenAccount,
              ),
              const SizedBox(height: 24),
              Text(
                'مرحبًا، $name',
                key: const Key('home.welcome'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'تابع مبارياتك واثبت أنك من النخبة.',
                style: TextStyle(color: tokens.textSecondary),
              ),
              const SizedBox(height: 18),
              _OverviewCard(
                fixtures: fixtures,
                seasons: seasons,
                onOpenMatches: onOpenMatches,
              ),
              const SizedBox(height: 24),
              _SectionHeader(title: 'وصول سريع', action: null, onAction: null),
              const SizedBox(height: 10),
              _QuickActions(
                onOpenMatches: onOpenMatches,
                onOpenPredictions: onOpenPredictions,
                onOpenLeaderboards: onOpenLeaderboards,
                onOpenAccount: onOpenAccount,
              ),
              const SizedBox(height: 24),
              _PendingPredictionsCard(
                pending: ref.watch(pendingPredictionsProvider),
                teamCatalog: teamCatalog,
                onPredict: onOpenMatches,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The next ACTION, not a summary: how many fixtures are still unpredicted,
/// which one locks first, a live countdown to that lock, and one button that
/// opens THAT fixture's predict sheet -- never the generic matches tab, which
/// would hand the user back the job of finding the match again.
///
/// Renders nothing while either input is still loading (`pending == null`):
/// a claim about what you have not done must not appear before it is known.
/// Once everything is predicted it becomes a quiet confirmation rather than
/// disappearing, so the row does not blink out of the layout mid-scroll.
class _PendingPredictionsCard extends StatelessWidget {
  const _PendingPredictionsCard({
    required this.pending,
    required this.teamCatalog,
    required this.onPredict,
  });

  final PendingPredictions? pending;
  final List<TeamDto>? teamCatalog;

  /// The fallback for the one case with nothing specific to open: fixtures
  /// are pending but none carries a parsable kickoff, so no single match can
  /// be named. Then, and only then, the button opens the matches tab.
  final VoidCallback onPredict;

  @override
  Widget build(BuildContext context) {
    final summary = pending;
    if (summary == null) return const SizedBox.shrink();

    final tokens = context.tokens;
    if (summary.isEmpty) {
      return Container(
        key: const Key('home.pendingPredictions.done'),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: tokens.border),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.verified_rounded, color: tokens.primaryLight, size: 22),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'أكملت جميع توقعاتك',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final next = summary.next;
    return Container(
      key: const Key('home.pendingPredictions'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.primary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.local_fire_department_rounded,
                color: tokens.primaryLight,
                size: 22,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'لا تفوّت توقعاتك',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _countLine(summary.count),
            key: const Key('home.pendingPredictions.count'),
            style: TextStyle(color: tokens.textSecondary, fontSize: 13),
          ),
          if (next != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                Icon(
                  Icons.emoji_events_outlined,
                  color: tokens.textMuted,
                  size: 18,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _teams(next),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Icon(Icons.timer_outlined, color: tokens.textMuted, size: 18),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'يُغلق التوقع بعد ',
                  style: TextStyle(color: tokens.textMuted, fontSize: 12),
                ),
                KickoffCountdown(kickoffAt: next.fixture.kickoffAt),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const Key('home.pendingPredictions.cta'),
            label: 'توقّع الآن',
            icon: Icons.arrow_back_rounded,
            onPressed: () {
              if (next == null) {
                onPredict();
                return;
              }
              unawaited(showFixturePredictSheet(context: context, item: next));
            },
          ),
        ],
      ),
    );
  }

  /// Arabic counts are not a plural suffix: one, two, few (3-10) and many
  /// (11+) are four different sentences, so the line is chosen rather than
  /// interpolated into a single template.
  static String _countLine(int count) {
    if (count == 1) return 'آخر مباراة لم تتوقعها!';
    if (count == 2) return 'بقيت لك مباراتان بلا توقع';
    if (count <= 10) return 'بقيت لك $count مباريات بلا توقع';
    return 'بقيت لك $count مباراة بلا توقع';
  }

  String _teams(CurrentMonthFixtureItemDto item) {
    final home = resolveTeamIdentity(
      catalog: teamCatalog,
      teamId: item.fixture.homeTeamId,
      teamName: item.fixture.homeTeam,
    );
    final away = resolveTeamIdentity(
      catalog: teamCatalog,
      teamId: item.fixture.awayTeamId,
      teamName: item.fixture.awayTeam,
    );
    return '${home.displayName} × ${away.displayName}';
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.onNotifications, required this.onAccount});

  final VoidCallback onNotifications;
  final VoidCallback onAccount;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      children: <Widget>[
        Text(
          'NUKHBAA',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: tokens.textPrimary,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const Spacer(),
        IconButton(
          key: const Key('home.notifications'),
          onPressed: onNotifications,
          icon: const Icon(Icons.notifications_none_rounded),
          color: tokens.textSecondary,
        ),
        IconButton(
          key: const Key('home.account'),
          onPressed: onAccount,
          icon: const Icon(Icons.person_outline_rounded),
          color: tokens.textSecondary,
        ),
      ],
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.fixtures,
    required this.seasons,
    required this.onOpenMatches,
  });

  final AsyncValue<List<CurrentMonthFixtureItemDto>> fixtures;
  final AsyncValue<List<ActiveSeasonDto>> seasons;
  final VoidCallback onOpenMatches;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fixtureCount = fixtures.value?.length;
    final seasonCount = seasons.value?.length;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: tokens.primaryGradient,
        borderRadius: AppRadius.brLg,
        boxShadow: tokens.shadowMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.auto_awesome_rounded, color: tokens.onPrimary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'لوحة النخبة',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: tokens.onPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              StreakChip(
                label: seasonCount == null ? '...' : '$seasonCount موسم نشط',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            fixtureCount == null
                ? 'جارٍ تحديث مبارياتك...'
                : '$fixtureCount مباراة متاحة هذا الشهر',
            style: TextStyle(
              color: tokens.onPrimary.withValues(alpha: 0.9),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: onOpenMatches,
            style: FilledButton.styleFrom(
              backgroundColor: tokens.onPrimary,
              foregroundColor: tokens.primary,
            ),
            child: const Text('ابدأ التوقع'),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onOpenMatches,
    required this.onOpenPredictions,
    required this.onOpenLeaderboards,
    required this.onOpenAccount,
  });

  final VoidCallback onOpenMatches;
  final VoidCallback onOpenPredictions;
  final VoidCallback onOpenLeaderboards;
  final VoidCallback onOpenAccount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _QuickAction(
          icon: Icons.sports_soccer_rounded,
          label: 'المباريات',
          onTap: onOpenMatches,
        ),
        const SizedBox(width: 8),
        _QuickAction(
          icon: Icons.bolt_rounded,
          label: 'توقعاتي',
          onTap: onOpenPredictions,
        ),
        const SizedBox(width: 8),
        _QuickAction(
          icon: Icons.leaderboard_rounded,
          label: 'المتصدرون',
          onTap: onOpenLeaderboards,
        ),
        const SizedBox(width: 8),
        _QuickAction(
          icon: Icons.person_rounded,
          label: 'الحساب',
          onTap: onOpenAccount,
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Expanded(
      child: Material(
        color: tokens.surfaceElevated,
        borderRadius: AppRadius.brMd,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.brMd,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
            child: Column(
              children: <Widget>[
                Icon(icon, color: tokens.primaryLight, size: 22),
                const SizedBox(height: 7),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.action,
    required this.onAction,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      children: <Widget>[
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: tokens.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const Spacer(),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    );
  }
}
