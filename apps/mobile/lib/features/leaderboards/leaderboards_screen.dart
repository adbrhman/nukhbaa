import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;

import '../../core/design/app_radius.dart';
import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/ui/segmented_pills.dart';
import '../../l10n/app_localizations.dart';
import '../competition/competition_providers.dart';
import '../fixture_prediction/current_month_fixtures_providers.dart';
import 'leaderboards_providers.dart';
import 'widgets/fixture_standings_board.dart';
import 'widgets/sporting_season_standings_board.dart';

/// What the leaderboard tab ranks.
enum LeaderboardScope {
  /// The current monthly contest.
  month,

  /// One local day of the current month.
  day,

  /// The sporting season, September to August, summed per user.
  season,
}

/// The bottom-tab leaderboard surface.
///
/// It narrows the display to the season that actually carries current-month
/// fixtures, then offers three views of the standings -- the month, one day,
/// and the whole sporting season -- each ranked by the server, most points
/// first.
class LeaderboardsScreen extends ConsumerWidget {
  const LeaderboardsScreen({this.userDisplayName, this.userId, super.key});

  final String? userDisplayName;

  /// The signed-in user's id; the season board is keyed by user.
  final String? userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTokens tokens = context.tokens;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<ActiveSeasonDto>> seasons = ref.watch(
      activeSeasonsProvider,
    );
    final AsyncValue<List<CurrentMonthFixtureItemDto>> monthFixtures = ref
        .watch(currentMonthFixturesProvider);

    return Scaffold(
      backgroundColor: tokens.background,
      body: seasons.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text(
            l10n.leaderboardsLoadFailed,
            style: TextStyle(color: tokens.textSecondary),
          ),
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
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  l10n.leaderboardsJoinSeasonPrompt,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: tokens.textSecondary),
                ),
              ),
            );
          }

          final ActiveSeasonDto season = _currentOf(visible);
          return _ScopedLeaderboard(
            key: ValueKey<String>('leaderboards.scoped.${season.seasonId}'),
            season: season,
            userDisplayName: userDisplayName,
            userId: userId,
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

class _ScopedLeaderboard extends ConsumerStatefulWidget {
  const _ScopedLeaderboard({
    required this.season,
    required this.userDisplayName,
    required this.userId,
    super.key,
  });

  final ActiveSeasonDto season;
  final String? userDisplayName;
  final String? userId;

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
    };
    final String period = switch (_scope) {
      LeaderboardScope.month => widget.season.seasonLabel,
      LeaderboardScope.day => intl.DateFormat(
        'EEEE d MMMM yyyy',
        locale,
      ).format(_day),
      LeaderboardScope.season =>
        ref.watch(sportingSeasonLeaderboardProvider).value?.label ?? '—',
    };
    final Widget board = switch (_scope) {
      LeaderboardScope.month => FixtureStandingsBoard(
        key: const ValueKey<String>('leaderboards.board.month'),
        seasonId: widget.season.seasonId,
        keyPrefix: 'leaderboards',
        myDisplayName: widget.userDisplayName,
        showHeader: true,
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
      LeaderboardScope.season => SportingSeasonStandingsBoard(
        key: const ValueKey<String>('leaderboards.board.season'),
        keyPrefix: 'leaderboards.season',
        myUserId: widget.userId,
        myDisplayName: widget.userDisplayName,
        showHeader: true,
      ),
    };

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.leaderboardsHeading,
            key: const Key('leaderboards.title'),
            textAlign: TextAlign.center,
            style: context.text.titleLarge?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            key: const Key('leaderboards.subtitle'),
            textAlign: TextAlign.center,
            style: context.text.bodySmall?.copyWith(
              color: tokens.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: _PeriodBar(
              label: period,
              onTap: _scope == LeaderboardScope.day ? _pickDay : null,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: SegmentedPills(
              keyPrefix: 'leaderboards.scope',
              labels: <String>[
                l10n.leaderboardScopeMonth,
                l10n.leaderboardScopeDay,
                l10n.leaderboardScopeSeason,
              ],
              selectedIndex: _scope.index,
              onSelected: (index) =>
                  setState(() => _scope = LeaderboardScope.values[index]),
            ),
          ),
          Expanded(child: board),
        ],
      ),
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
          decoration: BoxDecoration(
            borderRadius: AppRadius.brLg,
            border: Border.all(color: tokens.border),
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
                  color: tokens.primary,
                  size: AppSizes.iconMd,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
