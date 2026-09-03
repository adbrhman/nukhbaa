import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_radius.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/ui/match_card.dart';
import '../../core/ui/streak_chip.dart';
import '../../l10n/app_localizations.dart';
import '../competition/competition_providers.dart';
import '../fixture_prediction/current_month_fixtures_providers.dart';

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
    final l10n = AppLocalizations.of(context);
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
              _SectionHeader(
                title: l10n.matchesTitle,
                action: 'عرض الكل',
                onAction: onOpenMatches,
              ),
              const SizedBox(height: 10),
              fixtures.when(
                loading: () => const _HomeLoadingCard(),
                error: (error, stackTrace) => _HomeMessage(
                  message: 'تعذر تحميل مباريات هذا الشهر.',
                  action: onOpenMatches,
                  actionLabel: 'فتح المباريات',
                ),
                data: (items) {
                  if (items.isEmpty) {
                    return _HomeMessage(
                      message: l10n.matchesEmpty,
                      action: onOpenMatches,
                      actionLabel: 'تحديث',
                    );
                  }
                  return Column(
                    children: items
                        .take(3)
                        .map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: MatchCard(
                              competition: item.competitionName,
                              homeTeam: item.fixture.homeTeam,
                              awayTeam: item.fixture.awayTeam,
                              kickoffAt: item.fixture.kickoffAt,
                              onTap: onOpenMatches,
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
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

class _HomeLoadingCard extends StatelessWidget {
  const _HomeLoadingCard();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      height: 112,
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: AppRadius.brMd,
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _HomeMessage extends StatelessWidget {
  const _HomeMessage({
    required this.message,
    required this.action,
    required this.actionLabel,
  });

  final String message;
  final VoidCallback action;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(message, style: TextStyle(color: tokens.textSecondary)),
          ),
          TextButton(onPressed: action, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
