import 'dart:typed_data';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;

import '../../core/design/app_radius.dart';
import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/ui/app_error_state.dart';
import '../../core/ui/app_skeleton.dart';
import '../../core/ui/app_tab_header.dart';
import '../../core/ui/segmented_pills.dart';
import '../../l10n/app_localizations.dart';
import '../competition/competition_providers.dart';
import '../fixture_prediction/current_month_fixtures_providers.dart';
import 'champions_providers.dart';
import 'champions_record_screen.dart';
import 'leaderboards_providers.dart';
import 'widgets/champion_crown.dart';
import 'widgets/champion_spotlight.dart';
import 'widgets/fixture_standings_board.dart';
import 'widgets/friends_league_board.dart';
import 'widgets/sporting_season_standings_board.dart';
import 'widgets/weekly_league_board.dart';

/// What the leaderboard tab ranks.
enum LeaderboardScope {
  /// The current monthly contest.
  month,

  /// One local day of the current month.
  day,

  /// The sporting season, September to August, summed per user.
  season,

  /// The caller's weekly-league group for the Riyadh week open now.
  league,

  /// The caller's own friends' league: the month's board of its members
  /// (phase 2 of the plan).
  friends,
}

/// The bottom-tab leaderboard surface.
///
/// It narrows the display to the season that actually carries current-month
/// fixtures, then offers three views of the standings -- the month, one day,
/// and the whole sporting season -- each ranked by the server, most points
/// first.
///
/// While a crowning is being celebrated (the first 48 hours of the new
/// month) the champion's hero leads the month's board, above the new month's
/// standings -- and above the "the month starts with its first match"
/// message when the new month has no fixture yet, so the celebration never
/// depends on the new month being ready.
class LeaderboardsScreen extends ConsumerWidget {
  const LeaderboardsScreen({
    this.userDisplayName,
    this.userId,
    this.previewChampions,
    this.previewPhotos = const <String, Uint8List>{},
    super.key,
  });

  final String? userDisplayName;

  /// The signed-in user's id; the season board is keyed by user.
  final String? userId;

  /// The admin's rehearsal: these champions are celebrated whatever the
  /// server's list says, so the screen can be seen before the crowning.
  final List<MonthChampionDto>? previewChampions;

  /// Pictures still on the admin's device, by user id (the rehearsal).
  final Map<String, Uint8List> previewPhotos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens tokens = context.tokens;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<ActiveSeasonDto>> seasons = ref.watch(
      activeSeasonsProvider,
    );
    final AsyncValue<List<CurrentMonthFixtureItemDto>> monthFixtures = ref
        .watch(currentMonthFixturesProvider);
    // The celebration runs for the 48 hours the server set; after that the
    // champion stays in the record and beside their name on the boards.
    final List<MonthChampionDto> celebrating =
        previewChampions ??
        celebratingChampions(
          ref.watch(monthChampionsProvider).value,
          DateTime.now().toUtc(),
        );

    return Scaffold(
      backgroundColor: tokens.background,
      body: seasons.when(
        loading: () => const AppSkeletonCardList(
          key: Key('leaderboards.loading'),
          itemCount: 6,
          itemHeight: 64,
        ),
        error: (error, stackTrace) => AppErrorState(
          key: const Key('leaderboards.error'),
          message: l10n.leaderboardsLoadFailed,
          retryLabel: l10n.retry,
          onRetry: () => ref.invalidate(activeSeasonsProvider),
        ),
        data: (items) {
          final Set<String>? seasonsWithFixtures = monthFixtures.hasValue
              ? monthFixtures.value!
                    .map((item) => item.fixture.seasonId)
                    .toSet()
              : null;

          final List<ActiveSeasonDto> visible = seasonsWithFixtures == null
              ? items
              : items
                    .where(
                      (season) => seasonsWithFixtures.contains(season.seasonId),
                    )
                    .toList(growable: false);

          if (visible.isEmpty) {
            // The new month has no fixture yet (or none of its fixtures has
            // reached this device). Nobody has to "join" anything --
            // enrolment is automatic -- so the old join prompt misled; and
            // the celebration still shows.
            return _MonthNotStarted(
              celebrating: celebrating,
              previewPhotos: previewPhotos,
              userId: userId,
            );
          }

          final ActiveSeasonDto season = _currentOf(visible);
          return _ScopedLeaderboard(
            key: ValueKey<String>('leaderboards.scoped.${season.seasonId}'),
            season: season,
            userDisplayName: userDisplayName,
            userId: userId,
            celebrating: celebrating,
            previewPhotos: previewPhotos,
          );
        },
      ),
    );
  }
}

/// The season whose window holds "now", else the first one listed.
ActiveSeasonDto _currentOf(List<ActiveSeasonDto> seasons) {
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

/// Opens the champions' record.
void _openRecord(BuildContext context) {
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => const ChampionsRecordScreen()),
  );
}

/// The screen between the end of one month and the first fixture of the
/// next: the title, the celebration when one runs, and a word on when the
/// standings begin.
class _MonthNotStarted extends ConsumerWidget {
  const _MonthNotStarted({
    required this.celebrating,
    required this.previewPhotos,
    required this.userId,
  });

  final List<MonthChampionDto> celebrating;
  final Map<String, Uint8List> previewPhotos;
  final String? userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens tokens = context.tokens;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Widget list = SafeArea(
      bottom: false,
      child: ListView(
        key: const Key('leaderboards.notStarted'),
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
        ),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            // The one tab-title style (UI-20), drawn in the page so the
            // champion's backdrop can run under it.
            child: Text(
              l10n.leaderboardsHeading,
              key: const Key('leaderboards.title'),
              style: AppTabHeader.titleStyle(context),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (celebrating.isNotEmpty) ...<Widget>[
            ChampionSpotlight(
              champions: celebrating,
              keyPrefix: 'leaderboards.champion',
              previewPhotos: previewPhotos,
              viewerUserId: userId,
              margin: EdgeInsets.zero,
              onOpenRecord: () => _openRecord(context),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              l10n.leaderboardMonthStarting,
              key: const Key('leaderboards.monthStarting'),
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textSecondary),
            ),
          ),
        ],
      ),
    );
    if (celebrating.isEmpty) return list;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 340 + MediaQuery.paddingOf(context).top,
          child: ChampionBackdrop(
            champions: celebrating,
            previewPhotos: previewPhotos,
          ),
        ),
        list,
      ],
    );
  }
}

class _ScopedLeaderboard extends ConsumerStatefulWidget {
  const _ScopedLeaderboard({
    required this.season,
    required this.userDisplayName,
    required this.userId,
    required this.celebrating,
    required this.previewPhotos,
    super.key,
  });

  final ActiveSeasonDto season;
  final String? userDisplayName;
  final String? userId;

  /// The champions being celebrated, empty outside the 48 hours.
  final List<MonthChampionDto> celebrating;

  /// Pictures still on the admin's device, by user id (the rehearsal).
  final Map<String, Uint8List> previewPhotos;

  @override
  ConsumerState<_ScopedLeaderboard> createState() => _ScopedLeaderboardState();
}

class _ScopedLeaderboardState extends ConsumerState<_ScopedLeaderboard> {
  LeaderboardScope _scope = LeaderboardScope.month;
  late DateTime _day;

  @override
  void initState() {
    super.initState();
    final (DateTime first, DateTime last) = _dayBounds();
    _day = _clamp(_today(), first, last);
  }

  static DateTime _today() {
    final DateTime now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static DateTime _clamp(DateTime day, DateTime first, DateTime last) {
    if (day.isBefore(first)) return first;
    if (day.isAfter(last)) return last;
    return day;
  }

  /// The first and last local day of the month contest. `endAt` is
  /// exclusive, so the last day is the one before its local date.
  (DateTime, DateTime) _dayBounds() {
    final DateTime today = _today();
    final DateTime? start = DateTime.tryParse(widget.season.startAt)?.toLocal();
    final DateTime? end = DateTime.tryParse(widget.season.endAt)?.toLocal();
    final DateTime first = start == null
        ? DateTime(today.year, today.month, 1)
        : DateTime(start.year, start.month, start.day);
    DateTime last = end == null
        ? DateTime(today.year, today.month + 1, 0)
        : DateTime(end.year, end.month, end.day - 1);
    if (last.isBefore(first)) last = first;
    return (first, last);
  }

  Future<void> _pickDay() async {
    final (DateTime first, DateTime last) = _dayBounds();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _clamp(_day, first, last),
      firstDate: first,
      lastDate: last,
    );
    if (picked == null || !mounted) return;
    setState(() => _day = DateTime(picked.year, picked.month, picked.day));
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String locale = Localizations.localeOf(context).toString();

    final String subtitle = switch (_scope) {
      LeaderboardScope.month => l10n.leaderboardSubtitleMonth,
      LeaderboardScope.day => l10n.leaderboardSubtitleDay,
      LeaderboardScope.season => l10n.leaderboardSubtitleSeason,
      LeaderboardScope.league => l10n.leaderboardSubtitleLeague,
      LeaderboardScope.friends => 'ترتيبك بين أصدقائك بنقاط الشهر',
    };
    final String period = switch (_scope) {
      LeaderboardScope.month => widget.season.seasonLabel,
      LeaderboardScope.day => intl.DateFormat(
        'EEEE d MMMM yyyy',
        locale,
      ).format(_day),
      LeaderboardScope.league => switch (ref
          .watch(myWeeklyLeagueProvider)
          .value) {
        final MyWeeklyLeagueDto league => weeklyLeaguePeriodLabel(
          l10n,
          league,
          locale,
        ),
        null => l10n.leaderboardScopeLeague,
      },
      LeaderboardScope.season =>
        ref.watch(sportingSeasonLeaderboardProvider).value?.label ?? '—',
      LeaderboardScope.friends => widget.season.seasonLabel,
    };
    final List<MonthChampionDto> celebrating = widget.celebrating;
    final Widget board = switch (_scope) {
      LeaderboardScope.month => FixtureStandingsBoard(
        key: const ValueKey<String>('leaderboards.board.month'),
        seasonId: widget.season.seasonId,
        keyPrefix: 'leaderboards',
        myDisplayName: widget.userDisplayName,
        showHeader: true,
        emptyMessage: l10n.leaderboardMonthStarting,
        showDuelWins: true,
        // The hero leads the month's board and scrolls with it, above the
        // new month's standings -- the design of 2026-09-29.
        header: celebrating.isEmpty
            ? null
            : ChampionSpotlight(
                champions: celebrating,
                keyPrefix: 'leaderboards.champion',
                previewPhotos: widget.previewPhotos,
                viewerUserId: widget.userId,
                margin: EdgeInsets.zero,
                onOpenRecord: () => _openRecord(context),
              ),
      ),
      LeaderboardScope.day => FixtureStandingsBoard(
        key: ValueKey<String>('leaderboards.board.day.$_day'),
        seasonId: widget.season.seasonId,
        keyPrefix: 'leaderboards.day',
        myDisplayName: widget.userDisplayName,
        showHeader: true,
        day: _day,
        emptyMessage: l10n.leaderboardDayEmpty,
      ),
      LeaderboardScope.league => WeeklyLeagueBoard(
        key: const ValueKey<String>('leaderboards.board.league'),
        keyPrefix: 'leaderboards.league',
        myUserId: widget.userId,
        showHeader: true,
      ),
      LeaderboardScope.friends => FriendsLeagueBoard(
        key: const ValueKey<String>('leaderboards.board.friends'),
        seasonId: widget.season.seasonId,
        keyPrefix: 'leaderboards.friends',
        myDisplayName: widget.userDisplayName,
      ),
      LeaderboardScope.season => SportingSeasonStandingsBoard(
        key: const ValueKey<String>('leaderboards.board.season'),
        keyPrefix: 'leaderboards.season',
        myUserId: widget.userId,
        myDisplayName: widget.userDisplayName,
        showHeader: true,
      ),
    };

    final MonthChampionsDto? champions = ref
        .watch(monthChampionsProvider)
        .value;
    final bool hasRecord = champions?.champions.isNotEmpty ?? false;

    final Widget content = SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: <Widget>[
                Expanded(
                  // The one tab-title style (UI-20), in the page so the
                  // champion's backdrop can run under it.
                  child: Text(
                    l10n.leaderboardsHeading,
                    key: const Key('leaderboards.title'),
                    textAlign: TextAlign.start,
                    style: AppTabHeader.titleStyle(context),
                  ),
                ),
                // While the celebration runs, its own header links the
                // record; afterwards this crown does.
                if (hasRecord && celebrating.isEmpty)
                  IconButton(
                    key: const Key('leaderboards.champions.record'),
                    tooltip: l10n.championsRecordTitle,
                    onPressed: () => _openRecord(context),
                    icon: const ChampionCrown(size: 24),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              subtitle,
              key: const Key('leaderboards.subtitle'),
              textAlign: TextAlign.start,
              style: context.text.bodySmall?.copyWith(color: tokens.textMuted),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // What is ranked first, then which stretch of time.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: SegmentedPills(
              keyPrefix: 'leaderboards.scope',
              labels: <String>[
                l10n.leaderboardScopeMonth,
                l10n.leaderboardScopeDay,
                l10n.leaderboardScopeSeason,
                l10n.leaderboardScopeLeague,
                'أصدقائي',
              ],
              selectedIndex: _scope.index,
              onSelected: (index) =>
                  setState(() => _scope = LeaderboardScope.values[index]),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: _PeriodBar(
              label: period,
              onTap: _scope == LeaderboardScope.day ? _pickDay : null,
            ),
          ),
          Expanded(child: board),
        ],
      ),
    );
    if (celebrating.isEmpty) return content;
    // Layer 1 of the celebration: the champion's faint picture behind the
    // header (under the status bar too), fading out before the board.
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 340 + MediaQuery.paddingOf(context).top,
          child: ChampionBackdrop(
            champions: celebrating,
            previewPhotos: widget.previewPhotos,
          ),
        ),
        content,
      ],
    );
  }
}

/// The period line above the scope pills: the month label, the chosen day
/// (tappable, opens a date picker bound to the month), or the season label.
class _PeriodBar extends StatelessWidget {
  const _PeriodBar({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final VoidCallback? tap = onTap;
    return Material(
      color: tokens.surface,
      borderRadius: AppRadius.brLg,
      child: InkWell(
        key: const Key('leaderboards.period'),
        onTap: tap,
        borderRadius: AppRadius.brLg,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              if (tap != null) ...<Widget>[
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: tokens.textSecondary,
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // The calendar only where it opens one -- the day board; on
              // the month and the season it looked like a button that did
              // nothing (UI-14).
              if (tap != null) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                Container(
                  width: AppSizes.controlSm - 4,
                  height: AppSizes.controlSm - 4,
                  decoration: BoxDecoration(
                    color: tokens.primary.withValues(alpha: 0.13),
                    borderRadius: AppRadius.brMd,
                  ),
                  child: Icon(
                    Icons.calendar_month_rounded,
                    color: tokens.primaryText,
                    size: AppSizes.iconMd,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
