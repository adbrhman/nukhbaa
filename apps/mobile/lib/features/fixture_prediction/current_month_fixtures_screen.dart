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
import '../../l10n/app_localizations.dart';
import 'current_month_fixtures_providers.dart';
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
  DateTime _selectedDay = fixtureDayOnly(DateTime.now());
  bool _userPickedDay = false;

  /// Whether the live-only filter is on. Never trusted on its own — the
  /// build reads it as `_liveOnly && hasLive`, so a match finishing while
  /// the filter is on drops the screen back to the full day rather than
  /// stranding the user on an empty list they did not empty.
  bool _liveOnly = false;

  /// The local kickoff day of [item], or `null` when it has no kickoff.
  DateTime? _kickoffDay(CurrentMonthFixtureItemDto item) {
    final String? raw = item.fixture.kickoffAt;
    if (raw == null) return null;
    final DateTime? parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    return fixtureDayOnly(parsed.toLocal());
  }

  /// The day the list should show: the user's pick once they have made one,
  /// otherwise the day nearest [_selectedDay] that has at least one fixture
  /// (future preferred on a tie). Pure — never mutates state during build.
  DateTime _effectiveDay(List<CurrentMonthFixtureItemDto> items) {
    if (_userPickedDay) return _selectedDay;
    DateTime? best;
    int bestDistance = 1 << 30;
    for (final CurrentMonthFixtureItemDto item in items) {
      final DateTime? day = _kickoffDay(item);
      if (day == null) continue;
      final int delta = day.difference(_selectedDay).inDays;
      final int distance = delta.abs() * 2 + (delta < 0 ? 1 : 0);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = day;
      }
    }
    return best ?? _selectedDay;
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
        _selectedDay = fixtureDayOnly(DateTime.now());
        _userPickedDay = true;
      }
    });
  }

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
        ? fixtureDayOnly(DateTime.now())
        : _effectiveDay(all);

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        backgroundColor: tokens.background,
        foregroundColor: tokens.textPrimary,
        elevation: 0,
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
          preferredSize: const Size.fromHeight(FixturesDateStrip.height),
          child: FixturesDateStrip(selectedDay: day, onDaySelected: _selectDay),
        ),
      ),
      body: SafeArea(
        bottom: true,
        top: false,
        child: feed.when(
          skipLoadingOnRefresh: true,
          loading: () => const Center(
            key: Key('currentMonthFixtures.loading'),
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (error, _) => _CurrentMonthFixturesError(
            error: error,
            onRetry: () => ref.invalidate(currentMonthFixturesProvider),
          ),
          data: (items) {
            if (items.isEmpty) {
              return _EmptyMessage(
                messageKey: const Key('currentMonthFixtures.empty.message'),
                containerKey: const Key('currentMonthFixtures.empty'),
                message: l10n.matchesEmpty,
              );
            }
            final List<CurrentMonthFixtureItemDto> dayItems = items
                .where((item) {
                  if (liveOnly) return isFixtureLive(item.fixture.kickoffAt);
                  final DateTime? kickoff = _kickoffDay(item);
                  return kickoff == null || isSameFixtureDay(kickoff, day);
                })
                .toList(growable: false);
            if (dayItems.isEmpty) {
              return _EmptyMessage(
                messageKey: const Key('currentMonthFixtures.dayEmpty.message'),
                containerKey: const Key('currentMonthFixtures.dayEmpty'),
                message: l10n.fixturesDayEmpty,
              );
            }
            return ListView.builder(
              key: const Key('currentMonthFixtures.list'),
              // The reference leaves ~6 logical px either side of the
              // card (15px at 1080/2.75x); `lg` (16) was nearly triple
              // that and visibly narrowed every card.
              padding: const EdgeInsets.all(AppSpacing.sm),
              itemCount: dayItems.length,
              itemBuilder: (context, index) => RepaintBoundary(
                child: FotmobMatchCard(item: dayItems[index]),
              ),
            );
          },
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

  AppError get _appError => error is AppError
      ? error as AppError
      : const AppError.transient(
          'client.unexpected',
          'Something went wrong. Please try again.',
        );

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
            if (ErrorPresenter.isRetryable(appError)) ...<Widget>[
              const SizedBox(height: 16),
              FilledButton.tonal(
                key: const Key('currentMonthFixtures.error.retry'),
                onPressed: onRetry,
                child: Text(l10n.tryAgainButton),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
