import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;

import '../../core/design/app_radius.dart';
import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/design/app_typography.dart';
import '../../core/ui/app_button.dart';
import '../../core/ui/forward_chevron.dart';
import '../../core/ui/streak_chip.dart';
import '../../core/ui/team_logo.dart';
import '../competition/competition_providers.dart';
import '../competition/team_catalog_index.dart';
import '../competition/team_identity.dart';
import '../fixture_prediction/current_month_fixtures_providers.dart';
import '../gamification/daily_challenge_card.dart';
import '../notifications/notifications_providers.dart';
import '../notifications/notifications_screen.dart';
import 'pending_predictions_provider.dart';

/// The real authenticated home surface. It is intentionally a read-only
/// summary: fixtures and active seasons come from server-backed providers,
/// while detailed prediction and leaderboard flows remain in their own tabs.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    required this.user,
    required this.onOpenMatches,
    required this.onOpenAccount,
    super.key,
  });

  final AuthenticatedUserDto user;
  final VoidCallback onOpenMatches;
  final VoidCallback onOpenAccount;

  /// How many of the day's matches the home page lists.
  static const int highlightCount = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final fixtures = ref.watch(currentMonthFixturesProvider);
    final seasons = ref.watch(activeSeasonsProvider);
    final name = user.displayName.trim().isEmpty ? 'المتنبئ' : user.displayName;
    final _Highlights highlights = _Highlights.from(
      fixtures.value ?? const <CurrentMonthFixtureItemDto>[],
    );

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
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 104),
            children: <Widget>[
              _HomeHeader(onAccount: onOpenAccount),
              const SizedBox(height: 20),
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
                'تابع مبارياتك وأثبت أنك من النخبة.',
                style: TextStyle(color: tokens.textSecondary),
              ),
              const SizedBox(height: 16),
              // Reading order: what to do now -- the predictions still open,
              // with the one action -- then the matches they are about, then
              // the day's challenge, then the season overview. Each card
              // reads to a screen reader as one sentence.
              MergeSemantics(
                child: _PendingPredictionsCard(
                  pending: ref.watch(pendingPredictionsProvider),
                  onPredict: onOpenMatches,
                ),
              ),
              if (highlights.items.isNotEmpty) ...<Widget>[
                const SizedBox(height: 24),
                _SectionHeader(
                  title: highlights.isToday
                      ? 'أهم مباريات اليوم'
                      : 'أقرب المباريات القادمة',
                  action: 'عرض الكل',
                  onAction: onOpenMatches,
                ),
                const SizedBox(height: 10),
                for (final CurrentMonthFixtureItemDto item
                    in highlights.items) ...<Widget>[
                  MergeSemantics(
                    child: _HighlightRow(item: item, onTap: onOpenMatches),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
              const SizedBox(height: 24),
              MergeSemantics(
                child: DailyChallengeCard(onOpenMatches: onOpenMatches),
              ),
              const SizedBox(height: 18),
              MergeSemantics(
                child: _OverviewCard(
                  fixtures: fixtures,
                  seasons: seasons,
                  onOpenMatches: onOpenMatches,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The matches the home page highlights: today's, earliest kickoff first;
/// on a day without matches, the nearest upcoming day's instead, so the
/// section never promises "today" and shows another day.
class _Highlights {
  const _Highlights(this.items, {required this.isToday});

  factory _Highlights.from(List<CurrentMonthFixtureItemDto> all) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final List<(DateTime, CurrentMonthFixtureItemDto)> dated =
        <(DateTime, CurrentMonthFixtureItemDto)>[
          for (final CurrentMonthFixtureItemDto item in all)
            if (DateTime.tryParse(item.fixture.kickoffAt ?? '')
                case final DateTime kickoff)
              (kickoff.toLocal(), item),
        ]..sort((a, b) => a.$1.compareTo(b.$1));

    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    final List<CurrentMonthFixtureItemDto> todays =
        <CurrentMonthFixtureItemDto>[
          for (final (DateTime kickoff, CurrentMonthFixtureItemDto item)
              in dated)
            if (sameDay(kickoff, today)) item,
        ];
    if (todays.isNotEmpty) {
      return _Highlights(
        todays.take(HomeScreen.highlightCount).toList(growable: false),
        isToday: true,
      );
    }

    DateTime? nextDay;
    for (final (DateTime kickoff, CurrentMonthFixtureItemDto _) in dated) {
      if (kickoff.isAfter(now)) {
        nextDay = DateTime(kickoff.year, kickoff.month, kickoff.day);
        break;
      }
    }
    final DateTime? day = nextDay;
    if (day == null) {
      return const _Highlights(<CurrentMonthFixtureItemDto>[], isToday: false);
    }
    return _Highlights(
      <CurrentMonthFixtureItemDto>[
        for (final (DateTime kickoff, CurrentMonthFixtureItemDto item) in dated)
          if (sameDay(kickoff, day)) item,
      ].take(HomeScreen.highlightCount).toList(growable: false),
      isToday: false,
    );
  }

  final List<CurrentMonthFixtureItemDto> items;
  final bool isToday;
}

/// One highlighted match: league and kickoff on top, then home crest and
/// name, "Vs", away name and crest.
class _HighlightRow extends ConsumerWidget {
  const _HighlightRow({required this.item, required this.onTap});

  final CurrentMonthFixtureItemDto item;
  final VoidCallback onTap;

  static const double _crestSize = 30;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final catalogById = ref.watch(teamCatalogByIdProvider);
    final SeasonFixtureCardDto fixture = item.fixture;
    final ResolvedTeamIdentity home = resolveTeamIdentity(
      catalog: null,
      catalogById: catalogById,
      teamId: fixture.homeTeamId,
      teamName: fixture.homeTeam,
    );
    final ResolvedTeamIdentity away = resolveTeamIdentity(
      catalog: null,
      catalogById: catalogById,
      teamId: fixture.awayTeamId,
      teamName: fixture.awayTeam,
    );
    final DateTime? kickoff = DateTime.tryParse(
      fixture.kickoffAt ?? '',
    )?.toLocal();
    final String league = fixture.leagueName ?? item.competitionName;
    final String meta = kickoff == null
        ? league
        : '$league · ${intl.DateFormat.jm(Localizations.localeOf(context).toString()).format(kickoff)}';

    Widget crest(ResolvedTeamIdentity team) => TeamLogo(
      displayName: team.displayName,
      crestUrl: team.crestUrl,
      assetPath: team.assetPath,
      brandColor: team.brandColor,
      size: _crestSize,
    );
    Widget teamName(ResolvedTeamIdentity team, TextAlign align) => Text(
      team.displayName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: align,
      style: TextStyle(
        color: tokens.textPrimary,
        fontSize: AppFontSize.s13,
        fontWeight: FontWeight.w700,
      ),
    );

    return Material(
      key: Key('home.highlight.${fixture.fixtureId}'),
      color: tokens.surface,
      borderRadius: AppRadius.brLg,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.brLg,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: AppRadius.brLg,
            border: Border.all(color: tokens.border),
          ),
          child: Column(
            children: <Widget>[
              Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: AppFontSize.s12,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Row(
                      children: <Widget>[
                        crest(home),
                        const SizedBox(width: AppSpacing.sm),
                        Flexible(child: teamName(home, TextAlign.start)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    child: Text(
                      'Vs',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        Flexible(child: teamName(away, TextAlign.end)),
                        const SizedBox(width: AppSpacing.sm),
                        crest(away),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The month's unpredicted matches in one card: how many are left and a
/// button through to the matches tab.
///
/// Renders nothing while either input is still loading (`pending == null`):
/// a claim about what you have not done must not appear before it is known.
/// Once everything is predicted it becomes a quiet confirmation rather than
/// disappearing, so the row does not blink out of the layout mid-scroll.
class _PendingPredictionsCard extends StatelessWidget {
  const _PendingPredictionsCard({
    required this.pending,
    required this.onPredict,
  });

  final PendingPredictions? pending;

  /// Opens the matches tab.
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

    return Container(
      key: const Key('home.pendingPredictions'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.primary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'لا تفوّت مبارياتك القادمة',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _countLine(summary.count),
                      key: const Key('home.pendingPredictions.count'),
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: AppFontSize.s13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Icon(
                Icons.emoji_events_rounded,
                color: tokens.gold,
                size: AppSizes.iconXl,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const Key('home.pendingPredictions.cta'),
            label: 'تفاصيل المباريات',
            icon: Icons.arrow_forward_rounded,
            onPressed: onPredict,
          ),
        ],
      ),
    );
  }

  /// Arabic counts are not a plural suffix: one, two, few (3-10) and many
  /// (11+) are four different sentences, so the line is chosen rather than
  /// interpolated into a single template.
  static String _countLine(int count) {
    if (count == 1) return 'لديك مباراة قادمة واحدة';
    if (count == 2) return 'لديك مباراتان قادمتان';
    if (count <= 10) return 'لديك $count مباريات قادمة';
    return 'لديك $count مباراة قادمة';
  }
}

class _HomeHeader extends ConsumerWidget {
  const _HomeHeader({required this.onAccount});

  final VoidCallback onAccount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final int unread = ref.watch(unreadCountProvider).value ?? 0;
    return Row(
      children: <Widget>[
        // The wordmark gives way first: at large system text it scales
        // down beside the two icons instead of pushing them off screen.
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (Rect bounds) =>
                    tokens.primaryGradient.createShader(bounds),
                child: const Text(
                  'NUKHBAA',
                  key: Key('home.brand'),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: AppFontSize.s22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                  ),
                ),
              ),
            ),
          ),
        ),
        IconButton(
          key: const Key('home.notifications'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const NotificationsScreen(),
            ),
          ),
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text('$unread'),
            child: const Icon(Icons.notifications_none_rounded),
          ),
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
    // Only kickoffs still ahead can be predicted -- the lock rule of the
    // prediction card and [pendingPredictionsProvider]. The feed also
    // carries the month's played fixtures, which the label must not call
    // available.
    final DateTime nowUtc = DateTime.now().toUtc();
    final int? fixtureCount = fixtures.value
        ?.where(
          (item) =>
              DateTime.tryParse(
                item.fixture.kickoffAt ?? '',
              )?.toUtc().isAfter(nowUtc) ??
              false,
        )
        .length;
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
          LayoutBuilder(
            builder: (context, constraints) => Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'لوحة النخبة',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: tokens.onPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Icon(Icons.auto_awesome_rounded, color: tokens.onPrimary),
                const SizedBox(width: AppSpacing.sm),
                // At large system text the chip used to push past the
                // card's edge; it now shrinks inside at most 60% of the
                // row, and at normal size it is never near that.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * 0.6,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: StreakChip(
                      label: seasonCount == null
                          ? '...'
                          : _activeSeasonsLabel(seasonCount),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            fixtureCount == null
                ? 'جارٍ تحديث مبارياتك...'
                : _monthFixturesLabel(fixtureCount),
            style: TextStyle(
              color: tokens.onPrimary.withValues(alpha: 0.9),
              fontSize: AppFontSize.s13,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            key: const Key('home.startPredicting'),
            onPressed: onOpenMatches,
            style: FilledButton.styleFrom(
              backgroundColor: tokens.onPrimary,
              foregroundColor: tokens.primary,
              minimumSize: const Size.fromHeight(AppSizes.controlMd),
              // A button's textStyle replaces the theme's instead of merging
              // with it, so the family has to be named or the label falls
              // back to the system font.
              textStyle: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: AppFontSize.s16,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: const Text('ابدأ التوقع'),
          ),
        ],
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
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        TextButton(
          key: const Key('home.viewAll'),
          onPressed: onAction,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(action),
              const SizedBox(width: AppSpacing.xs),
              const ForwardChevron(size: AppSizes.iconSm),
            ],
          ),
        ),
      ],
    );
  }
}

/// Arabic number agreement: zero, one, two, few (3-10) and many (11-99)
/// are different sentences, not a plural suffix -- the same split as the
/// pending-fixtures line above.
String _activeSeasonsLabel(int count) {
  final int tail = count % 100;
  if (count == 0) return 'لا مواسم نشطة';
  if (count == 1) return 'موسم نشط واحد';
  if (count == 2) return 'موسمان نشطان';
  if (tail >= 3 && tail <= 10) return '$count مواسم نشطة';
  if (tail >= 11) return '$count موسمًا نشطًا';
  return '$count موسم نشط';
}

String _monthFixturesLabel(int count) {
  final int tail = count % 100;
  if (count == 0) return 'لا مباريات متاحة هذا الشهر';
  if (count == 1) return 'مباراة واحدة متاحة هذا الشهر';
  if (count == 2) return 'مباراتان متاحتان هذا الشهر';
  if (tail >= 3 && tail <= 10) return '$count مباريات متاحة هذا الشهر';
  return '$count مباراة متاحة هذا الشهر';
}
