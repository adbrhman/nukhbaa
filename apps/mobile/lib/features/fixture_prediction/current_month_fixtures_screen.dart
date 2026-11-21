/// The regular user's unified **current month** screen (Monthly
/// Competitions transition, `docs/project-context.md` §9) — every public
/// competition's current-month fixture, now grouped by kickoff day behind a
/// FotMob-style day strip (`widgets/fixtures_date_bar.dart`) and a calendar
/// page (`widgets/fixtures_calendar_page.dart`) reachable from the app bar.
///
/// Reuses the existing per-fixture submit slice exactly as-is, unmodified:
///   * [fixturePredictionControllerProvider] / [FixtureSubmissionState] from
///     `fixture_prediction_controller.dart` / `fixture_prediction_submission.dart`
///     — the same controller the season-scoped `FixturePredictionScreen`
///     already uses, keyed by the same `(seasonId, fixtureId)` pair. Each
///     `CurrentMonthFixtureItemDto.fixture` already carries its own
///     `seasonId`, so this screen needs no separate season lookup.
///
/// Only the read is new: [currentMonthFixturesProvider]
/// (`GET /feed/current-month-fixtures`, `current_month_fixtures_providers.dart`).
/// The day grouping is a pure client-side view over that one read — no new
/// endpoint, no new provider, no server change.
///
/// ## Day selection
/// The screen owns the selected day so the strip, the calendar and the list
/// can never disagree. Before the user picks anything, the selection snaps
/// to the day nearest to today that actually has fixtures (future preferred
/// on a tie) — otherwise a month whose fixtures all sit later would open on
/// an empty "today" and read as a broken feed. Once the user picks a day,
/// their choice is final for the session, empty or not.
///
/// A fixture with no `kickoffAt` cannot be filed under any day, so it stays
/// visible on every day rather than disappearing from the app entirely.
///
/// Within a day the cards run in kickoff order, earliest first, across every
/// competition; a fixture with no kickoff comes last (`_byKickoff`).
///
/// Per-fixture rendering is still [FotmobMatchCard]
/// (`widgets/fotmob_match_card.dart`, `match-card-fotmob-spec.md`) — this
/// screen itself only owns the read/loading/empty/error states.
library;

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/error/error_presenter.dart';
import '../../core/time/riyadh_day_turnover.dart';
import '../../core/ui/app_skeleton.dart';
import '../../core/ui/app_tab_header.dart';
import '../../l10n/app_localizations.dart';
import '../history/my_fixture_scores_providers.dart';
import '../history/prediction_history_providers.dart';
import 'current_month_fixtures_providers.dart';
import 'feed_refresh_signal.dart';
import 'widgets/fixtures_calendar_page.dart';
import 'widgets/fixtures_date_bar.dart';
import 'widgets/fotmob_match_card.dart';
import 'widgets/live_matches_chip.dart';

/// The current-month fixtures screen.
class CurrentMonthFixturesScreen extends ConsumerStatefulWidget {
  /// Creates the current-month fixtures screen.
  const CurrentMonthFixturesScreen({super.key});

  @override
  ConsumerState<CurrentMonthFixturesScreen> createState() =>
      _CurrentMonthFixturesScreenState();
}

class _CurrentMonthFixturesScreenState
    extends ConsumerState<CurrentMonthFixturesScreen> {
  DateTime _selectedDay = RiyadhDayTurnover.dayKeyOf(DateTime.now());
  bool _userPickedDay = false;

  /// Whether the live-only filter is on. Never trusted on its own — the
  /// build reads it as `_liveOnly && hasLive`, so a match finishing while
  /// the filter is on drops the screen back to the full day rather than
  /// stranding the user on an empty list they did not empty.
  bool _liveOnly = false;

  /// Which leagues the player opened or closed on the day's list, by name
  /// (script 301); a league he never touched follows the default.
  final Map<String, bool> _leagueOpen = <String, bool>{};

  /// Re-evaluates every clock-derived state on the screen once a minute.
  ///
  /// Kickoff passing changes nothing in the feed, so nothing rebuilt the
  /// cards at that moment: the steppers stayed live after a match had
  /// started (the auto-save then bounced off the server with
  /// `prediction.fixture_locked`, which reads to the user as a random
  /// error), and the live chip neither lit up nor went out while the screen
  /// stayed open. One minute is the finest granularity anything here shows.
  Timer? _clockTick;
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    _clockTick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      // One coalesced feed read per minute, instead of one per saved
      // prediction (see feed_refresh_signal.dart).
      _ticks++;
      final bool anyLive =
          ref
              .read(currentMonthFixturesProvider)
              .value
              ?.any((item) => isFixtureLive(item.fixture.kickoffAt)) ??
          false;
      if (ref.read(feedRefreshSignalProvider)) {
        ref.read(feedRefreshSignalProvider.notifier).consume();
        ref.invalidate(currentMonthFixturesProvider);
      } else if (anyLive && _ticks.isEven) {
        // Running scores are refreshed server-side every 2 minutes.
        ref.invalidate(currentMonthFixturesProvider);
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTick?.cancel();
    super.dispose();
  }

  /// The Riyadh kickoff day of [item], or `null` when it has no kickoff.
  ///
  /// The device's own calendar put a 23:30 Riyadh match on the next day
  /// for a player in the Emirates, and a 00:30 one on the day before for a
  /// player in Egypt or Morocco, while the server counts both on the Riyadh
  /// day: a double the strip showed on two days was refused as two on one.
  DateTime? _kickoffDay(CurrentMonthFixtureItemDto item) {
    final String? raw = item.fixture.kickoffAt;
    if (raw == null) return null;
    final DateTime? parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    return RiyadhDayTurnover.dayKeyOf(parsed);
  }

  /// [items] in kickoff order, earliest first -- the order a day is drawn in.
  ///
  /// The feed arrives grouped by competition (name order, then
  /// `display_order`), so a 20:30 Bundesliga match used to sit above a 17:15
  /// La Liga one. Kickoffs are compared as UTC instants, so the device's
  /// offset can never reorder anything. Equal kickoffs keep the feed's own
  /// order, and a fixture with no readable kickoff goes last (same rule as
  /// `admin_pickers.dart`). `List.sort` is not stable, hence the index.
  static List<CurrentMonthFixtureItemDto> _byKickoff(
    List<CurrentMonthFixtureItemDto> items,
  ) {
    final List<(int, DateTime?, CurrentMonthFixtureItemDto)> keyed =
        <(int, DateTime?, CurrentMonthFixtureItemDto)>[
          for (int i = 0; i < items.length; i++)
            (
              i,
              DateTime.tryParse(items[i].fixture.kickoffAt ?? '')?.toUtc(),
              items[i],
            ),
        ];
    keyed.sort((a, b) {
      final DateTime? ta = a.$2;
      final DateTime? tb = b.$2;
      if (ta != null && tb != null) {
        final int byTime = ta.compareTo(tb);
        if (byTime != 0) return byTime;
      } else if (ta != null) {
        return -1;
      } else if (tb != null) {
        return 1;
      }
      return a.$1.compareTo(b.$1);
    });
    return <CurrentMonthFixtureItemDto>[for (final k in keyed) k.$3];
  }

  /// The day the list should show: the user's pick once they have made one,
  /// otherwise the day nearest [_selectedDay] that has at least one fixture
  /// (future preferred on a tie). Pure — never mutates state during build.
  DateTime _effectiveDay(List<CurrentMonthFixtureItemDto> items) {
    if (_userPickedDay) return _selectedDay;
    // Measured from the real today on every build, not from the day the
    // screen was first built: the tab stays alive, and an app left open
    // past midnight kept opening on the day before.
    final DateTime today = RiyadhDayTurnover.dayKeyOf(DateTime.now());
    DateTime? best;
    int bestDistance = 1 << 30;
    for (final CurrentMonthFixtureItemDto item in items) {
      final DateTime? day = _kickoffDay(item);
      if (day == null) continue;
      final int delta = day.difference(today).inDays;
      final int distance = delta.abs() * 2 + (delta < 0 ? 1 : 0);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = day;
      }
    }
    return best ?? today;
  }

  void _selectDay(DateTime day) {
    setState(() {
      _selectedDay = fixtureDayOnly(day);
      _userPickedDay = true;
      // Choosing a day is an explicit "show me this day" — keeping a live
      // filter on top of it would silently hide most of what was asked for.
      _liveOnly = false;
    });
  }

  /// Toggling the live filter on also moves the selection to today, since a
  /// fixture in play is by definition today's — without it the filter would
  /// read as broken while the strip sat on some other day.
  void _toggleLiveOnly() {
    setState(() {
      _liveOnly = !_liveOnly;
      if (_liveOnly) {
        _selectedDay = RiyadhDayTurnover.dayKeyOf(DateTime.now());
        _userPickedDay = true;
      }
    });
  }

  /// Pull to refresh: the tab lives in the shell's `IndexedStack`, so
  /// without this a fixture the admin adds during the day never appears
  /// until the app restarts.
  Future<void> _refresh() async {
    ref.read(feedRefreshSignalProvider.notifier).consume();
    ref.invalidate(currentMonthFixturesProvider);
    ref.invalidate(myFixturePredictionsProvider);
    ref.invalidate(myFixtureScoresProvider);
    try {
      await ref.read(currentMonthFixturesProvider.future);
    } on Object {
      // A failed reload keeps its error on screen through the feed itself;
      // the pull gesture still has to finish.
    }
  }

  /// The empty states pull to refresh too: a day the admin had not filled
  /// yet kept saying "no matches" until the app was restarted.
  Widget _refreshable(Widget child) => RefreshIndicator(
    onRefresh: _refresh,
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.hasBoundedHeight ? constraints.maxHeight : 0,
          ),
          child: child,
        ),
      ),
    ),
  );

  Future<void> _openCalendar(DateTime current) async {
    final DateTime? picked = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute<DateTime>(
        builder: (_) => FixturesCalendarPage(selectedDay: current),
      ),
    );
    if (picked != null) _selectDay(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final feed = ref.watch(currentMonthFixturesProvider);
    final tokens = context.tokens;
    final List<CurrentMonthFixtureItemDto> all = feed.value ?? const [];
    final bool hasLive = all.any(
      (item) => isFixtureLive(item.fixture.kickoffAt),
    );
    final bool liveOnly = _liveOnly && hasLive;
    final DateTime day = liveOnly
        ? RiyadhDayTurnover.dayKeyOf(DateTime.now())
        : _effectiveDay(all);

    return Scaffold(
      backgroundColor: tokens.background,
      // The tab's name at the start, like every tab; the wordmark stays on
      // home alone (UI-20).
      appBar: AppTabHeader(
        title: Text(
          l10n.matchesTitle,
          key: const Key('currentMonthFixtures.title'),
        ),
        actions: <Widget>[
          LiveMatchesChip(
            hasLive: hasLive,
            selected: liveOnly,
            onTap: _toggleLiveOnly,
          ),
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            key: const Key('currentMonthFixtures.calendar'),
            tooltip: l10n.fixturesCalendarTooltip,
            icon: const Icon(Icons.calendar_today_outlined),
            iconSize: AppSizes.iconMd,
            onPressed: () => unawaited(_openCalendar(day)),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(FixturesDateStrip.heightFor(context)),
          child: FixturesDateStrip(selectedDay: day, onDaySelected: _selectDay),
        ),
      ),
      body: SafeArea(
        bottom: true,
        top: false,
        child: feed.when(
          skipLoadingOnRefresh: true,
          // A refresh that fails (the minute tick fires the moment the app
          // comes back from the background) keeps the list on screen; only
          // a first load with nothing to show falls back to the error.
          skipError: true,
          loading: () => const AppSkeletonCardList(
            key: Key('currentMonthFixtures.loading'),
            itemHeight: 96,
          ),
          // Scrolls and pulls to refresh like the empty states: at large
          // text the message did not fit under the date strip (x2.0 on a
          // phone overflowed by 57 px, ui_audit_survey_test shell.matches).
          error: (error, _) => _refreshable(
            _CurrentMonthFixturesError(
              error: error,
              onRetry: () => ref.invalidate(currentMonthFixturesProvider),
            ),
          ),
          data: (items) {
            if (items.isEmpty) {
              return _refreshable(
                _EmptyMessage(
                  messageKey: const Key('currentMonthFixtures.empty.message'),
                  containerKey: const Key('currentMonthFixtures.empty'),
                  message: l10n.matchesEmpty,
                ),
              );
            }
            final List<CurrentMonthFixtureItemDto> dayFiltered = items
                .where((item) {
                  if (liveOnly) return isFixtureLive(item.fixture.kickoffAt);
                  final DateTime? kickoff = _kickoffDay(item);
                  return kickoff == null || isSameFixtureDay(kickoff, day);
                })
                .toList(growable: false);
            final List<CurrentMonthFixtureItemDto> dayItems = _byKickoff(
              dayFiltered,
            );
            if (dayItems.isEmpty) {
              return _refreshable(
                _EmptyMessage(
                  messageKey: const Key(
                    'currentMonthFixtures.dayEmpty.message',
                  ),
                  containerKey: const Key('currentMonthFixtures.dayEmpty'),
                  message: l10n.fixturesDayEmpty,
                ),
              );
            }
            // NK301_01 script 301: the day's matches under one header per
            // league, as the player picks: a header opens or closes its own.
            final List<_LeagueGroup> groups = _LeagueGroup.of(dayItems);
            // The player's own predictions, counted under each header (5/7).
            final Set<String> predicted = <String>{
              for (final FixturePredictionDto p
                  in ref.watch(myFixturePredictionsProvider).value ??
                      const <FixturePredictionDto>[])
                p.fixtureId,
            };
            // One league, or the live filter: nothing to choose, all open.
            final bool openByDefault = liveOnly || groups.length == 1;
            bool isOpen(_LeagueGroup g) => _leagueOpen[g.name] ?? openByDefault;
            final List<Object> rows = <Object>[
              for (final _LeagueGroup g in groups) ...<Object>[
                g,
                if (isOpen(g)) ...g.items,
              ],
            ];
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.builder(
                key: const Key('currentMonthFixtures.list'),
                physics: const AlwaysScrollableScrollPhysics(),
                // script 132: list margin -- the FotMob card stands 16
                // logical px from either edge.
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xs,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final Object row = rows[index];
                  if (row is _LeagueGroup) {
                    final bool open = isOpen(row);
                    return _LeagueHeader(
                      key: ValueKey<String>('league.${row.name}'),
                      index: row.index,
                      name: row.name,
                      total: row.items.length,
                      predicted: row.items
                          .where((i) => predicted.contains(i.fixture.fixtureId))
                          .length,
                      open: open,
                      onTap: () =>
                          setState(() => _leagueOpen[row.name] = !open),
                    );
                  }
                  final CurrentMonthFixtureItemDto item =
                      row as CurrentMonthFixtureItemDto;
                  return RepaintBoundary(
                    key: ValueKey<String>('card.${item.fixture.fixtureId}'),
                    // A card's State holds the scoreline being typed: keyed
                    // by fixture id, it stays tied to its own fixture.
                    child: FotmobMatchCard(
                      key: ValueKey<String>(item.fixture.fixtureId),
                      item: item,
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One league's matches of the day, in kickoff order (script 301).
class _LeagueGroup {
  _LeagueGroup(this.index, this.name);

  /// Its place on the day's list, from 0.
  final int index;

  /// The league's name (the competition's when the fixture names none).
  final String name;

  /// Its matches, earliest first.
  final List<CurrentMonthFixtureItemDto> items = <CurrentMonthFixtureItemDto>[];

  /// [dayItems] (already in kickoff order) by league, each league placed
  /// where its first match falls.
  static List<_LeagueGroup> of(List<CurrentMonthFixtureItemDto> dayItems) {
    final Map<String, _LeagueGroup> byName = <String, _LeagueGroup>{};
    for (final CurrentMonthFixtureItemDto item in dayItems) {
      final String? league = item.fixture.leagueName?.trim();
      final String name = league == null || league.isEmpty
          ? item.competitionName
          : league;
      byName
          .putIfAbsent(name, () => _LeagueGroup(byName.length, name))
          .items
          .add(item);
    }
    return byName.values.toList(growable: false);
  }
}

/// A league's header on the day's list (script 301): its name, how many
/// of its matches the player predicted, and an arrow that opens or closes
/// its matches.
class _LeagueHeader extends StatelessWidget {
  const _LeagueHeader({
    super.key,
    required this.index,
    required this.name,
    required this.total,
    required this.predicted,
    required this.open,
    required this.onTap,
  });

  final int index;
  final String name;
  final int total;
  final int predicted;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool any = predicted > 0;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
      child: Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('currentMonthFixtures.league.$index'),
          onTap: onTap,
          child: Semantics(
            button: true,
            expanded: open,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.emoji_events_outlined,
                      size: 20,
                      color: t.textMuted,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        name,
                        key: Key('currentMonthFixtures.league.$index.name'),
                        style: context.text.titleSmall?.copyWith(
                          color: t.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: any ? t.success : t.surfaceHigh,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        any ? '$predicted/$total' : '$total',
                        key: Key('currentMonthFixtures.league.$index.count'),
                        textDirection: TextDirection.ltr,
                        style: context.text.labelLarge?.copyWith(
                          color: any ? t.onSuccess : t.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      open
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: t.textSecondary,
                    ),
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

/// The screen's two empty states — no fixtures at all this month, and none
/// on the selected day — drawn identically so the difference is the message
/// alone.
class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({
    required this.messageKey,
    required this.containerKey,
    required this.message,
  });

  final Key messageKey;
  final Key containerKey;
  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      key: containerKey,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          key: messageKey,
          textAlign: TextAlign.center,
          style: TextStyle(color: tokens.textSecondary),
        ),
      ),
    );
  }
}

/// Renders a thrown [AppError] via `ErrorPresenter` with a retry affordance.
class _CurrentMonthFixturesError extends StatelessWidget {
  const _CurrentMonthFixturesError({
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final VoidCallback onRetry;

  AppError get _appError => ErrorPresenter.asAppError(error);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final appError = _appError;
    final tokens = context.tokens;
    return Center(
      key: const Key('currentMonthFixtures.error'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, size: 48, color: tokens.error),
            const SizedBox(height: 12),
            Text(
              ErrorPresenter.message(appError),
              key: const Key('currentMonthFixtures.error.message'),
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textPrimary),
            ),
            // Every failure, not only a dropped connection (audit L-17).
            const SizedBox(height: 16),
            FilledButton.tonal(
              key: const Key('currentMonthFixtures.error.retry'),
              onPressed: onRetry,
              child: Text(l10n.tryAgainButton),
            ),
          ],
        ),
      ),
    );
  }
}
