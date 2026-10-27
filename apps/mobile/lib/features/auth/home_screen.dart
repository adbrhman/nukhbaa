import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/design/app_radius.dart';
import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/design/app_typography.dart';
import '../../core/error/error_presenter.dart';
import '../../core/format/timestamps.dart';
import '../../core/time/riyadh_day_turnover.dart';
import '../../core/ui/app_button.dart';
import '../../core/ui/forward_chevron.dart';
import '../../core/ui/score_pill.dart';
import '../../core/ui/streak_chip.dart';
import '../../core/ui/team_logo.dart';
import '../../core/ui/unread_badge.dart';
import '../../l10n/app_localizations.dart';
import '../competition/competition_providers.dart';
import '../competition/team_catalog_index.dart';
import '../competition/team_identity.dart';
import '../fixture_prediction/current_month_fixtures_providers.dart';
import '../fixture_prediction/widgets/live_home_card.dart';
import '../fixture_prediction/widgets/live_matches_chip.dart';
import '../history/prediction_history_providers.dart';
import '../history/prediction_history_screen.dart';
import '../notifications/notifications_providers.dart';
import '../notifications/notifications_screen.dart';
import '../notifications/web_push_card.dart';
import '../update/update_gate.dart';
import 'pending_predictions_provider.dart';

/// The real authenticated home surface. It is intentionally a read-only
/// summary: fixtures and active seasons come from server-backed providers,
/// while detailed prediction and leaderboard flows remain in their own tabs.
/// The daily-challenge card is not part of this screen's information flow.
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
            // Refresh the prediction summary used by the home feed.
            ref.invalidate(myFixturePredictionsProvider);
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
              // A newer build waiting, when the update check says so.
              const _UpdateNudgeCard(),
              // Flow: pending action, live match, fixtures, monthly overview, history.
              MergeSemantics(
                child: _PendingPredictionsCard(
                  pending: ref.watch(pendingPredictionsProvider),
                  onPredict: onOpenMatches,
                ),
              ),
              // While a match the player predicted is in play: what it
              // would earn and their month place if it ended now; hidden
              // otherwise.
              LiveHomeCard(onOpenMatches: onOpenMatches),
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
                child: _OverviewCard(
                  fixtures: fixtures,
                  seasons: seasons,
                  onOpenMatches: onOpenMatches,
                  onRetry: () {
                    ref.invalidate(currentMonthFixturesProvider);
                    ref.invalidate(activeSeasonsProvider);
                  },
                ),
              ),
              const SizedBox(height: 18),
              // "My predictions" left the bottom bar for the head-to-head
              // league (2026-10-10); it opens from here.
              const MergeSemantics(child: _MyPredictionsCard()),
              const SizedBox(height: 18),
              // Web notification setup stays secondary to football activity.
              const WebPushCard(),
            ],
          ),
        ),
      ),
    );
  }
}

/// A newer build is waiting (batch 147): an Android build a week old with
/// a release out, or a web page left open across a release. One tap
/// updates; the cross closes the card until the app starts again.
class _UpdateNudgeCard extends ConsumerWidget {
  const _UpdateNudgeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(updateNudgeProvider)) return const SizedBox.shrink();
    final LatestBuildDto? pending = ref.watch(pendingUpdateProvider);
    if (!kIsWeb && pending == null) return const SizedBox.shrink();
    final tokens = context.tokens;

    void update() {
      if (kIsWeb) {
        ref.read(pageReloaderProvider)();
        return;
      }
      final LatestBuildDto? release = pending;
      if (release != null) unawaited(installUpdate(context, ref, release));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Container(
        key: const Key('home.updateNudge'),
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.xs,
          AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: AppRadius.brLg,
          border: Border.all(color: tokens.primary),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.system_update_rounded, color: tokens.primaryText),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'نسخة أحدث من نُخبة جاهزة',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              key: const Key('home.updateNudge.update'),
              onPressed: update,
              child: const Text('حدِّث'),
            ),
            IconButton(
              key: const Key('home.updateNudge.close'),
              tooltip: 'إغلاق',
              onPressed: () => ref.read(updateNudgeProvider.notifier).close(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the caller's predictions ("توقعاتي") as a page of its own, with
/// its back button: the tab it used to be went to the head-to-head league.
class _MyPredictionsCard extends StatelessWidget {
  const _MyPredictionsCard();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.surface,
      borderRadius: AppRadius.brLg,
      child: InkWell(
        key: const Key('home.myPredictions'),
        borderRadius: AppRadius.brLg,
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const PredictionHistoryScreen(),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: AppRadius.brLg,
            border: Border.all(color: tokens.border),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.bolt_rounded, color: tokens.primaryText),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'توقعاتي',
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: AppFontSize.s15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'كل توقعاتك ونتائجها في مكان واحد',
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: AppFontSize.s12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              ForwardChevron(color: tokens.textMuted),
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
    final DateTime today = RiyadhDayTurnover.dayKeyOf(now);
    final List<(DateTime, CurrentMonthFixtureItemDto)> dated =
        <(DateTime, CurrentMonthFixtureItemDto)>[
          for (final CurrentMonthFixtureItemDto item in all)
            if (DateTime.tryParse(item.fixture.kickoffAt ?? '')
                case final DateTime kickoff)
              (kickoff.toLocal(), item),
        ]..sort((a, b) => a.$1.compareTo(b.$1));

    // A kickoff belongs to its Riyadh day, the day the matches tab and the
    // server file it under.
    bool sameDay(DateTime kickoff, DateTime day) {
      final DateTime a = RiyadhDayTurnover.dayKeyOf(kickoff);
      return a.year == day.year && a.month == day.month && a.day == day.day;
    }

    final List<CurrentMonthFixtureItemDto> todays =
        <CurrentMonthFixtureItemDto>[
          for (final (DateTime kickoff, CurrentMonthFixtureItemDto item)
              in dated)
            if (sameDay(kickoff, today)) item,
        ];
    if (todays.isNotEmpty) {
      // script 126: the matches in play first, then those still to come,
      // then those over; kickoff order within each.
      int rank(CurrentMonthFixtureItemDto item) {
        final DateTime? kickoff = DateTime.tryParse(
          item.fixture.kickoffAt ?? '',
        );
        if (kickoff != null && kickoff.isAfter(now)) return 1;
        return _isOver(item) ? 2 : 0;
      }

      final List<CurrentMonthFixtureItemDto> ranked =
          <CurrentMonthFixtureItemDto>[
            for (int r = 0; r < 3; r++)
              for (final CurrentMonthFixtureItemDto item in todays)
                if (rank(item) == r) item,
          ];
      return _Highlights(
        ranked.take(HomeScreen.highlightCount).toList(growable: false),
        isToday: true,
      );
    }

    DateTime? nextDay;
    for (final (DateTime kickoff, CurrentMonthFixtureItemDto _) in dated) {
      if (kickoff.isAfter(now)) {
        nextDay = RiyadhDayTurnover.dayKeyOf(kickoff);
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

/// Whether [item] is over (script 126): its result recorded, the live feed
/// says finished, or past the live window since kickoff.
bool _isOver(CurrentMonthFixtureItemDto item) {
  if (item.resultHomeGoals != null && item.resultAwayGoals != null) {
    return true;
  }
  if (item.liveFinished ?? false) return true;
  final DateTime? kickoff = DateTime.tryParse(item.fixture.kickoffAt ?? '');
  return kickoff != null &&
      !kickoff.isAfter(DateTime.now()) &&
      !isFixtureLive(item.fixture.kickoffAt);
}

/// One highlighted match: league and kickoff on top, then home crest and
/// name, "vs" in the reader's language, away name and crest.
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
    // script 126: where the match stands, and its score once it has one.
    final bool over = _isOver(item);
    final bool started = kickoff != null && !kickoff.isAfter(DateTime.now());
    final bool hasResult =
        item.resultHomeGoals != null && item.resultAwayGoals != null;
    final int? shownHome = hasResult
        ? item.resultHomeGoals
        : item.liveHomeGoals;
    final int? shownAway = hasResult
        ? item.resultAwayGoals
        : item.liveAwayGoals;
    final String meta = over
        ? '$league · انتهت'
        : started
        ? '$league · مباشر'
        : kickoff == null
        ? league
        : '$league · ${formatKickoffTime(context, fixture.kickoffAt!)}';

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
                    // Arabic in an Arabic row, not a Latin "Vs" (UI-29);
                    // the score instead once there is one (script 126).
                    child: shownHome != null && shownAway != null
                        ? Text(
                            orientedScoreLabel(context, shownHome, shownAway),
                            key: Key(
                              'home.highlight.score.${fixture.fixtureId}',
                            ),
                            textDirection: TextDirection.ltr,
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: AppFontSize.s16,
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : Text(
                            AppLocalizations.of(context).versusShort,
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
    // script 126: which match is nearest, so the card says what waits.
    final String? nextLine = _nextLine(context, summary.next);
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
                      'مباريات بانتظار توقعك',
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
                    if (nextLine != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        nextLine,
                        key: const Key('home.pendingPredictions.next'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: AppFontSize.s12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Icon(
                Icons.emoji_events_rounded,
                // goldAccent: the text gold reads olive in the light theme.
                color: tokens.goldAccent,
                size: AppSizes.iconXl,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const Key('home.pendingPredictions.cta'),
            label: 'توقّع الآن',
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
  /// What the count is (script 126): the matches still to come that the
  /// player has not called, not every match to come.
  static String _countLine(int count) {
    if (count == 1) return 'مباراة واحدة لم تتوقعها بعد';
    if (count == 2) return 'مباراتان لم تتوقعهما بعد';
    if (count <= 10) return '$count مباريات لم تتوقعها بعد';
    return '$count مباراة لم تتوقعها بعد';
  }

  /// The nearest of them: its teams and when.
  static String? _nextLine(
    BuildContext context,
    CurrentMonthFixtureItemDto? next,
  ) {
    if (next == null) return null;
    final SeasonFixtureCardDto fixture = next.fixture;
    final String teams =
        '${fixture.homeTeam ?? '؟'} × ${fixture.awayTeam ?? '؟'}';
    final String? kickoff = fixture.kickoffAt;
    return kickoff == null
        ? 'أقربها: $teams'
        : 'أقربها: $teams · ${formatDayAndTime(context, kickoff)}';
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
          // Named for screen readers: the badge alone read "19" (UI-27).
          tooltip: 'الإشعارات',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const NotificationsScreen(),
            ),
          ),
          icon: UnreadBadge(
            count: unread,
            child: const Icon(Icons.notifications_none_rounded),
          ),
          color: tokens.textSecondary,
        ),
        IconButton(
          key: const Key('home.account'),
          tooltip: 'الحساب',
          onPressed: onAccount,
          icon: const Icon(Icons.person_outline_rounded),
          color: tokens.textSecondary,
        ),
      ],
    );
  }
}

/// The month at a glance. A read that failed says so, with a retry,
/// instead of "updating your matches..." for ever (audit M-06).
class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.fixtures,
    required this.seasons,
    required this.onOpenMatches,
    required this.onRetry,
  });

  final AsyncValue<List<CurrentMonthFixtureItemDto>> fixtures;
  final AsyncValue<List<ActiveSeasonDto>> seasons;
  final VoidCallback onOpenMatches;

  /// Reads the month's matches and the seasons again.
  final VoidCallback onRetry;

  /// The failure to show: only while there is nothing older to show
  /// instead (a failed refresh keeps the last list).
  static AppError? _failure(AsyncValue<Object?> value) {
    if (value.hasValue || !value.hasError) return null;
    final Object? error = value.error;
    return error is AppError
        ? error
        : const AppError.transient(
            'client.unexpected',
            'Something went wrong. Please try again.',
          );
  }

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
    final AppError? failure = _failure(fixtures);
    return Container(
      key: const Key('home.overview'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        // White text sits on it: the gradient made for white (UI-07).
        gradient: tokens.actionGradient,
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
                // At most 60% of the row; at large system text the chip's
                // label wraps there instead of shrinking (UI-17). A failed
                // read shows no count rather than "..." for ever.
                if (_failure(seasons) == null)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * 0.6,
                    ),
                    child: StreakChip(
                      label: seasonCount == null
                          ? '...'
                          : _activeSeasonsLabel(seasonCount),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (failure != null) ...<Widget>[
            Text(
              ErrorPresenter.message(failure),
              key: const Key('home.overview.error'),
              style: TextStyle(
                color: tokens.onPrimary,
                fontSize: AppFontSize.s13,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              key: const Key('home.overview.retry'),
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: tokens.onPrimary,
                side: BorderSide(color: tokens.onPrimary),
                minimumSize: const Size.fromHeight(AppSizes.controlMd),
              ),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(AppLocalizations.of(context).retry),
            ),
          ] else
            Text(
              fixtureCount == null
                  ? 'جارٍ تحديث مبارياتك...'
                  : _monthFixturesLabel(fixtureCount),
              // Full white: at 90% it fell to 3.9:1 on the gradient (UI-07).
              style: TextStyle(
                color: tokens.onPrimary,
                fontSize: AppFontSize.s13,
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            key: const Key('home.startPredicting'),
            onPressed: onOpenMatches,
            style: FilledButton.styleFrom(
              backgroundColor: tokens.onPrimary,
              // The deeper blue: the dark theme's bright primary sat at
              // 4.54:1 on white, on the edge (colour audit, CA-12).
              foregroundColor: context.scheme.primaryContainer,
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
