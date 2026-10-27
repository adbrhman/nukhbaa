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
import '../../core/ui/brand_mark.dart';
import '../../core/ui/forward_chevron.dart';
import '../../core/ui/score_pill.dart';
import '../../core/ui/team_logo.dart';
import '../../core/ui/unread_badge.dart';
import '../../l10n/app_localizations.dart';
import '../competition/competition_providers.dart';
import '../competition/team_catalog_index.dart';
import '../competition/team_identity.dart';
import '../fixture_prediction/current_month_fixtures_providers.dart';
import '../fixture_prediction/widgets/live_home_card.dart';
import '../fixture_prediction/widgets/live_matches_chip.dart';
import '../leaderboards/leaderboards_providers.dart';
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
    this.onOpenLeaders,
    super.key,
  });

  final AuthenticatedUserDto user;
  final VoidCallback onOpenMatches;
  final VoidCallback onOpenAccount;

  /// Opens the leaderboard tab from the month card (script 161); without
  /// it the card opens the matches instead.
  final VoidCallback? onOpenLeaders;

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
    final _MonthStanding? standing = _MonthStanding.read(
      ref,
      seasons: seasons.value,
      fixtures: fixtures.value,
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
                  standing: standing,
                  onOpenMatches: onOpenMatches,
                  onOpenLeaders: onOpenLeaders ?? onOpenMatches,
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

  /// Crests at the size the matches tab gives them room for: team
  /// identity before density (2026-10-26).
  static const double _crestSize = 34;

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
    final bool live = started && !over;
    final bool scored = shownHome != null && shownAway != null;
    // The state sits in the middle, where the eye already goes (script
    // 161): the score once there is one, else the kickoff, else "live";
    // the line above says "live" or "over" only beside a score.
    final String meta = over
        ? '$league · انتهت'
        : live && scored
        ? '$league · مباشر'
        : league;

    Widget crest(ResolvedTeamIdentity team) => TeamLogo(
      displayName: team.displayName,
      crestUrl: team.crestUrl,
      assetPath: team.assetPath,
      brandColor: team.brandColor,
      size: _crestSize,
    );
    // Two lines before an ellipsis: the state pill took room from the
    // names, and a long club name must still read whole (script 161).
    Widget teamName(ResolvedTeamIdentity team, TextAlign align) => Text(
      team.displayName,
      maxLines: 2,
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
                    child: _HighlightState(
                      fixtureId: fixture.fixtureId,
                      score: shownHome != null && shownAway != null
                          ? orientedScoreLabel(context, shownHome, shownAway)
                          : null,
                      live: live,
                      kickoff: !started && kickoff != null
                          ? formatKickoffTime(context, fixture.kickoffAt!)
                          : null,
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

/// The middle of a highlighted match: its score (red-edged while live),
/// else its kickoff time, else "live", else "vs".
class _HighlightState extends StatelessWidget {
  const _HighlightState({
    required this.fixtureId,
    required this.score,
    required this.live,
    required this.kickoff,
  });

  final String fixtureId;
  final String? score;
  final bool live;
  final String? kickoff;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final String? shownScore = score;
    final String? shownKickoff = kickoff;
    final Widget label;
    if (shownScore != null) {
      label = Text(
        shownScore,
        key: Key('home.highlight.score.$fixtureId'),
        textDirection: TextDirection.ltr,
        style: TextStyle(
          color: tokens.textPrimary,
          fontSize: AppFontSize.s16,
          fontWeight: FontWeight.w800,
        ),
      );
    } else if (live) {
      label = Row(
        key: Key('home.highlight.live.$fixtureId'),
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: tokens.error,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'مباشر',
            style: TextStyle(
              color: tokens.errorText,
              fontSize: AppFontSize.s12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );
    } else if (shownKickoff != null) {
      label = Text(
        shownKickoff,
        key: Key('home.highlight.kickoff.$fixtureId'),
        maxLines: 1,
        style: TextStyle(
          color: tokens.textPrimary,
          fontSize: AppFontSize.s13,
          fontWeight: FontWeight.w800,
        ),
      );
    } else {
      return Text(
        AppLocalizations.of(context).versusShort,
        style: TextStyle(color: tokens.textMuted, fontWeight: FontWeight.w800),
      );
    }
    // At most 88 wide: at large system text the label scales down inside
    // it, so the two clubs keep their crests and names (UI-17).
    return Container(
      constraints: const BoxConstraints(minWidth: 56, maxWidth: 88),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: AppRadius.brSm,
        // Script 162: red is the live dot and its word, never an edge.
        border: Border.all(color: tokens.border),
      ),
      // Sized to the label, centred in the 56 minimum.
      child: Align(
        widthFactor: 1,
        heightFactor: 1,
        child: FittedBox(fit: BoxFit.scaleDown, child: label),
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
              // The mark and the name in Arabic (script 161), in place of a
              // Latin wordmark on an Arabic page.
              child: Row(
                key: const Key('home.brand'),
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const BrandMark(size: 30),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'نُخبة',
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: AppFontSize.s24,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                ],
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

/// Where the viewer stands on the month's board (script 161): the same
/// read as the leaderboard tab's month view (`fixtureLeaderboardProvider`
/// for the month that holds now), found by the viewer's participant id.
/// Null until it is known, or when the viewer has no line on it yet.
final class _MonthStanding {
  const _MonthStanding({
    required this.rank,
    required this.points,
    required this.players,
    required this.leads,
    this.nextPoints,
    this.nextRank,
  });

  /// The viewer's rank (competition ranking: tied totals share it).
  final int rank;

  /// The viewer's points this month.
  final int points;

  /// Lines on the month's board.
  final int players;

  /// The viewer holds rank 1, alone or tied.
  final bool leads;

  /// Points to the nearest higher total, and the rank it holds.
  final int? nextPoints;
  final int? nextRank;

  static _MonthStanding? read(
    WidgetRef ref, {
    required List<ActiveSeasonDto>? seasons,
    required List<CurrentMonthFixtureItemDto>? fixtures,
  }) {
    if (seasons == null || fixtures == null) return null;
    final Set<String> withFixtures = <String>{
      for (final CurrentMonthFixtureItemDto item in fixtures)
        item.fixture.seasonId,
    };
    final List<ActiveSeasonDto> visible = <ActiveSeasonDto>[
      for (final ActiveSeasonDto season in seasons)
        if (withFixtures.contains(season.seasonId)) season,
    ];
    if (visible.isEmpty) return null;
    final ActiveSeasonDto season = _currentSeasonOf(visible);
    String? me;
    for (final FixturePredictionDto prediction
        in ref.watch(myFixturePredictionsProvider).value ??
            const <FixturePredictionDto>[]) {
      if (prediction.seasonId == season.seasonId) {
        me = prediction.participantId;
        break;
      }
    }
    if (me == null) return null;
    final List<FixtureLeaderboardEntryDto>? entries = ref
        .watch(fixtureLeaderboardProvider(season.seasonId))
        .value
        ?.entries;
    if (entries == null || entries.isEmpty) return null;
    FixtureLeaderboardEntryDto? mine;
    for (final FixtureLeaderboardEntryDto entry in entries) {
      if (entry.participantId == me) {
        mine = entry;
        break;
      }
    }
    final FixtureLeaderboardEntryDto? viewer = mine;
    if (viewer == null) return null;
    FixtureLeaderboardEntryDto? above;
    for (final FixtureLeaderboardEntryDto entry in entries) {
      if (entry.totalPoints > viewer.totalPoints &&
          (above == null || entry.totalPoints < above.totalPoints)) {
        above = entry;
      }
    }
    return _MonthStanding(
      rank: viewer.rank,
      points: viewer.totalPoints,
      players: entries.length,
      leads: viewer.rank == 1,
      nextPoints: above == null ? null : above.totalPoints - viewer.totalPoints,
      nextRank: above?.rank,
    );
  }

  /// The season whose window holds now, else the first one: the month the
  /// leaderboard tab opens on.
  static ActiveSeasonDto _currentSeasonOf(List<ActiveSeasonDto> seasons) {
    final DateTime now = DateTime.now().toUtc();
    for (final ActiveSeasonDto season in seasons) {
      final DateTime? start = DateTime.tryParse(season.startAt)?.toUtc();
      final DateTime? end = DateTime.tryParse(season.endAt)?.toUtc();
      if (start != null &&
          end != null &&
          !now.isBefore(start) &&
          now.isBefore(end)) {
        return season;
      }
    }
    return seasons.first;
  }
}

/// The month at a glance. Once the viewer has a line on the month's board
/// it leads with where he stands -- his place, his points and the next
/// step up -- and opens the leaderboard (script 161); before that, how
/// many matches are left and the way to the matches. A read that failed
/// says so, with a retry, instead of "updating your matches..." for ever
/// (audit M-06).
class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.fixtures,
    required this.standing,
    required this.onOpenMatches,
    required this.onOpenLeaders,
    required this.onRetry,
  });

  final AsyncValue<List<CurrentMonthFixtureItemDto>> fixtures;
  final _MonthStanding? standing;
  final VoidCallback onOpenMatches;
  final VoidCallback onOpenLeaders;

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
    final AppLocalizations l10n = AppLocalizations.of(context);
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
    final AppError? failure = _failure(fixtures);
    final _MonthStanding? place = failure == null ? standing : null;
    // Script 162: a card like the others, not a second blue block beside
    // the pending card's button -- one solid blue action per screen. Its
    // figures are white, its secondary lines grey, its action an outline
    // in the text blue (AAA on the card).
    final TextStyle onCard = TextStyle(color: tokens.textPrimary);
    final TextStyle onCardSecondary = TextStyle(color: tokens.textSecondary);
    final ButtonStyle cardButton = OutlinedButton.styleFrom(
      foregroundColor: tokens.primaryText,
      side: BorderSide(color: tokens.primaryText),
      minimumSize: const Size.fromHeight(AppSizes.controlMd),
      // A button's textStyle replaces the theme's instead of merging
      // with it, so the family has to be named or the label falls
      // back to the system font.
      textStyle: const TextStyle(
        fontFamily: AppTypography.fontFamily,
        fontSize: AppFontSize.s16,
        fontWeight: FontWeight.w800,
      ),
    );
    final String countLine = fixtureCount == null
        ? 'جارٍ تحديث مبارياتك...'
        : _monthFixturesLabel(fixtureCount);
    return Container(
      key: const Key('home.overview'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  place == null ? 'لوحة النخبة' : 'ترتيبك هذا الشهر',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(
                place == null
                    ? Icons.auto_awesome_rounded
                    : Icons.leaderboard_rounded,
                color: tokens.primaryText,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (failure != null) ...<Widget>[
            Text(
              ErrorPresenter.message(failure),
              key: const Key('home.overview.error'),
              style: onCardSecondary.copyWith(fontSize: AppFontSize.s13),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              key: const Key('home.overview.retry'),
              onPressed: onRetry,
              style: cardButton,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.retry),
            ),
          ] else if (place != null) ...<Widget>[
            // The place first, the points at the other end: the two
            // figures a player opens the app for.
            Row(
              key: const Key('home.overview.standing'),
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  '${place.rank}',
                  key: const Key('home.overview.rank'),
                  style: onCard.copyWith(
                    fontSize: AppFontSize.s26,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      'من ${place.players}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: onCardSecondary.copyWith(
                        fontSize: AppFontSize.s13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  l10n.boardPoints(place.points),
                  key: const Key('home.overview.points'),
                  style: onCard.copyWith(
                    fontSize: AppFontSize.s18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                key: const Key('home.overview.next'),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: tokens.surfaceHigh,
                  borderRadius: AppRadius.brXxl,
                ),
                child: Text(
                  place.leads
                      ? l10n.boardYouLead
                      : place.nextPoints != null && place.nextRank != null
                      ? l10n.boardGapToRank(
                          l10n.boardPoints(place.nextPoints!),
                          place.nextRank!,
                        )
                      : countLine,
                  style: TextStyle(
                    color: tokens.primaryText,
                    fontSize: AppFontSize.s13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              countLine,
              key: const Key('home.overview.count'),
              style: onCardSecondary.copyWith(fontSize: AppFontSize.s12),
            ),
          ] else
            Text(
              countLine,
              style: onCardSecondary.copyWith(fontSize: AppFontSize.s13),
            ),
          const SizedBox(height: AppSpacing.md),
          if (place != null && failure == null)
            OutlinedButton(
              key: const Key('home.overview.leaders'),
              onPressed: onOpenLeaders,
              style: cardButton,
              child: const Text('عرض الترتيب'),
            )
          else
            OutlinedButton(
              key: const Key('home.startPredicting'),
              onPressed: onOpenMatches,
              style: cardButton,
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

String _monthFixturesLabel(int count) {
  final int tail = count % 100;
  if (count == 0) return 'لا مباريات متاحة هذا الشهر';
  if (count == 1) return 'مباراة واحدة متاحة هذا الشهر';
  if (count == 2) return 'مباراتان متاحتان هذا الشهر';
  if (tail >= 3 && tail <= 10) return '$count مباريات متاحة هذا الشهر';
  return '$count مباراة متاحة هذا الشهر';
}
