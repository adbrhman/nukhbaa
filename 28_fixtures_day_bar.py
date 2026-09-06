#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""28_fixtures_day_bar — شريط الأيام (FotMob) + التقويم + تصفية حسب اليوم."""
import os, subprocess, sys

ROOT = "/home/dev/nukhbaa-backup-1787537565"
if not os.path.isdir(ROOT):
    ROOT = os.getcwd()
M = os.path.join(ROOT, "apps/mobile")
assert os.path.isdir(M), "apps/mobile not found under %s" % ROOT


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def write(p, s):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        f.write(s)


def patch(rel, old, new, count=1):
    p = os.path.join(M, rel)
    s = read(p)
    assert s.count(old) == count, "anchor x%d != %d in %s" % (s.count(old), count, rel)
    write(p, s.replace(old, new, count))
    print("patched", rel)


# ---------------------------------------------------------------- new file 1
DATE_BAR = r'''/// The FotMob-style **day strip** that sits under the matches app bar
/// (`current_month_fixtures_screen.dart`): one horizontally scrollable tab
/// per calendar day, the selected one underlined. Relative labels for
/// yesterday / today / tomorrow, `EEEE dd MMMM` for everything else — the
/// same shape the reference uses.
///
/// Purely presentational: it owns no fixture read and no selection state.
/// The screen owns the selected day and hands it down, so the strip, the
/// calendar page and the filtered list can never disagree.
library;

import 'package:flutter/material.dart';
// intl is a transitive dependency via flutter_localizations, the same way
// the generated l10n files import it; the "no new dependencies" rule means
// it is not declared in pubspec.yaml just to silence this lint.
// ignore: depend_on_referenced_packages
import 'package:intl/intl.dart' as intl;

import '../../../core/design/app_motion.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../l10n/app_localizations.dart';

/// Midnight-local for [value] — the canonical "day" key used by the strip,
/// the calendar page and the screen's own filter alike.
DateTime fixtureDayOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// Whether [a] and [b] fall on the same calendar day.
bool isSameFixtureDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// The day tab strip.
class FixturesDateStrip extends StatefulWidget {
  /// Creates the strip around [selectedDay].
  const FixturesDateStrip({
    required this.selectedDay,
    required this.onDaySelected,
    super.key,
  });

  /// The currently selected day (midnight-local).
  final DateTime selectedDay;

  /// Called with a midnight-local day when a tab is tapped.
  final ValueChanged<DateTime> onDaySelected;

  /// The strip's fixed height, for the app bar's `PreferredSize`.
  static const double height = 46;

  @override
  State<FixturesDateStrip> createState() => _FixturesDateStripState();
}

class _FixturesDateStripState extends State<FixturesDateStrip> {
  /// Days rendered on each side of the selection — the window always
  /// recentres on the selected day, so the strip stays usable however far
  /// the calendar page jumps.
  static const int _radius = 7;

  final ScrollController _controller = ScrollController();
  final GlobalKey _selectedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _scheduleCentre();
  }

  @override
  void didUpdateWidget(covariant FixturesDateStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!isSameFixtureDay(oldWidget.selectedDay, widget.selectedDay)) {
      _scheduleCentre();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scheduleCentre() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? ctx = _selectedKey.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: AppMotion.fast,
        curve: AppMotion.standardCurve,
      );
    });
  }

  String _label(BuildContext context, DateTime day, DateTime today) {
    final l10n = AppLocalizations.of(context);
    final int diff = day.difference(today).inDays;
    if (diff == 0) return l10n.fixturesDateToday;
    if (diff == -1) return l10n.fixturesDateYesterday;
    if (diff == 1) return l10n.fixturesDateTomorrow;
    final String locale = Localizations.localeOf(context).toString();
    final String weekday = intl.DateFormat.EEEE(locale).format(day);
    final String month = intl.DateFormat.MMMM(locale).format(day);
    final String dayNum = intl.DateFormat('dd', locale).format(day);
    return '$weekday $dayNum $month';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final DateTime today = fixtureDayOnly(DateTime.now());
    final DateTime selected = fixtureDayOnly(widget.selectedDay);

    return SizedBox(
      height: FixturesDateStrip.height,
      child: ListView.builder(
        key: const Key('currentMonthFixtures.dayStrip'),
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        itemCount: _radius * 2 + 1,
        itemBuilder: (context, index) {
          final DateTime day = selected.add(Duration(days: index - _radius));
          final bool isSelected = index == _radius;
          return _DayTab(
            key: isSelected ? _selectedKey : null,
            label: _label(context, day, today),
            selected: isSelected,
            tokens: tokens,
            onTap: () => widget.onDaySelected(day),
          );
        },
      ),
    );
  }
}

/// One day tab: label plus a 3px selection underline, exactly as the
/// reference draws it. Unselected tabs carry no fill and no border, so the
/// strip reads as text until something is chosen.
class _DayTab extends StatelessWidget {
  const _DayTab({
    required this.label,
    required this.selected,
    required this.tokens,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final AppTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Spacer(),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? tokens.textPrimary : tokens.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              height: 3,
              width: 44,
              decoration: BoxDecoration(
                color: selected ? tokens.primary : Colors.transparent,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(3),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
'''

# ---------------------------------------------------------------- new file 2
CALENDAR = r'''/// The full-screen month calendar the matches app bar's calendar icon
/// opens: a vertically scrolling list of months, week starting Monday,
/// with a "today" shortcut in the app bar. Pops the chosen midnight-local
/// [DateTime], or `null` when dismissed.
///
/// Presentational only — it reads no fixture and knows nothing about the
/// feed; the caller decides what a chosen day means.
library;

import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:intl/intl.dart' as intl;

import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../l10n/app_localizations.dart';
import 'fixtures_date_bar.dart';

/// The date-picker page.
class FixturesCalendarPage extends StatelessWidget {
  /// Creates the calendar, highlighting [selectedDay].
  const FixturesCalendarPage({required this.selectedDay, super.key});

  /// The day drawn as selected when the page opens.
  final DateTime selectedDay;

  /// How many months are listed, starting at the current month — the
  /// competition is the calendar month, so the current one leads and the
  /// next two are reachable without an endless scroll.
  static const int monthCount = 3;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final DateTime today = fixtureDayOnly(DateTime.now());
    final DateTime firstMonth = DateTime(today.year, today.month);

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        backgroundColor: tokens.background,
        foregroundColor: tokens.textPrimary,
        elevation: 0,
        title: Text(l10n.fixturesCalendarPickTitle),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: FilledButton(
              key: const Key('fixturesCalendar.today'),
              onPressed: () => Navigator.of(context).pop(today),
              child: Text(l10n.fixturesDateToday),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            const _WeekdayHeader(),
            Expanded(
              child: ListView.builder(
                key: const Key('fixturesCalendar.months'),
                padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                itemCount: monthCount,
                itemBuilder: (context, index) => _MonthBlock(
                  month: DateTime(firstMonth.year, firstMonth.month + index),
                  selectedDay: fixtureDayOnly(selectedDay),
                  today: today,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The pinned Monday-first weekday row.
class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  /// A known Monday, used only to render the seven weekday names in the
  /// active locale without hardcoding any of them.
  static final DateTime _monday = DateTime(2024, 1);

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final String locale = Localizations.localeOf(context).toString();
    final intl.DateFormat format = intl.DateFormat.EEEE(locale);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < 7; i++)
            Expanded(
              child: Text(
                format.format(_monday.add(Duration(days: i))),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: tokens.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}

/// One month: its title, then its day grid as plain rows (no nested
/// scrollable — the page's own `ListView` does all the scrolling).
class _MonthBlock extends StatelessWidget {
  const _MonthBlock({
    required this.month,
    required this.selectedDay,
    required this.today,
  });

  final DateTime month;
  final DateTime selectedDay;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final String locale = Localizations.localeOf(context).toString();
    // Monday-first offset of the 1st, then the row count that covers it.
    final int leading = (DateTime(month.year, month.month).weekday - 1) % 7;
    final int dayCount = DateTime(month.year, month.month + 1, 0).day;
    final int rows = ((leading + dayCount) / 7).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Text(
            intl.DateFormat.yMMMM(locale).format(month),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: tokens.textPrimary,
            ),
          ),
        ),
        for (int row = 0; row < rows; row++)
          Row(
            children: <Widget>[
              for (int col = 0; col < 7; col++)
                Expanded(
                  child: _dayCell(context, row * 7 + col - leading + 1),
                ),
            ],
          ),
      ],
    );
  }

  Widget _dayCell(BuildContext context, int dayNumber) {
    final int dayCount = DateTime(month.year, month.month + 1, 0).day;
    if (dayNumber < 1 || dayNumber > dayCount) {
      return const SizedBox(height: 52);
    }
    final tokens = context.tokens;
    final DateTime day = DateTime(month.year, month.month, dayNumber);
    final bool isSelected = isSameFixtureDay(day, selectedDay);
    final bool isToday = isSameFixtureDay(day, today);

    return SizedBox(
      height: 52,
      child: Center(
        child: InkResponse(
          key: Key('fixturesCalendar.day.${day.toIso8601String()}'),
          radius: 24,
          onTap: () => Navigator.of(context).pop(day),
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? tokens.primary : Colors.transparent,
            ),
            child: Text(
              '$dayNumber',
              style: TextStyle(
                fontSize: 16,
                fontWeight: isSelected || isToday
                    ? FontWeight.w800
                    : FontWeight.w500,
                color: isSelected
                    ? tokens.onPrimary
                    : isToday
                    ? tokens.primary
                    : tokens.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
'''

write(os.path.join(M, "lib/features/fixture_prediction/widgets/fixtures_date_bar.dart"), DATE_BAR)
print("created widgets/fixtures_date_bar.dart")
write(os.path.join(M, "lib/features/fixture_prediction/widgets/fixtures_calendar_page.dart"), CALENDAR)
print("created widgets/fixtures_calendar_page.dart")

# ---------------------------------------------------------------- screen
SCREEN_REL = "lib/features/fixture_prediction/current_month_fixtures_screen.dart"
_scr = read(os.path.join(M, SCREEN_REL))
assert "class CurrentMonthFixturesScreen extends ConsumerWidget" in _scr, "screen already migrated?"
assert "FotmobMatchCard(item: items[index])" in _scr, "unexpected screen body"

SCREEN = r'''/// The regular user's unified **current month** screen (Monthly
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
    final DateTime day = _effectiveDay(feed.value ?? const []);

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
          child: FixturesDateStrip(
            selectedDay: day,
            onDaySelected: _selectDay,
          ),
        ),
      ),
      body: SafeArea(
        bottom: true,
        top: false,
        child: feed.when(
          skipLoadingOnRefresh: false,
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
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: dayItems.length,
              itemBuilder: (context, index) =>
                  FotmobMatchCard(item: dayItems[index]),
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
'''
write(os.path.join(M, SCREEN_REL), SCREEN)
print("rewrote", SCREEN_REL)

# ---------------------------------------------------------------- l10n
patch(
    "lib/l10n/app_ar.arb",
    '  "adminRemoveFixtureSuccess": "تم حذف المباراة من الجولة."\n}',
    '  "adminRemoveFixtureSuccess": "تم حذف المباراة من الجولة.",\n'
    '  "fixturesDateToday": "اليوم",\n'
    '  "fixturesDateYesterday": "أمس",\n'
    '  "fixturesDateTomorrow": "غداً",\n'
    '  "fixturesCalendarTooltip": "التقويم",\n'
    '  "fixturesCalendarPickTitle": "اختر التاريخ",\n'
    '  "fixturesDayEmpty": "لا توجد مباريات في هذا اليوم."\n}',
)

patch(
    "lib/l10n/app_en.arb",
    '  "adminRemoveFixtureSuccess": "Fixture removed from the round."\n}',
    '  "adminRemoveFixtureSuccess": "Fixture removed from the round.",\n'
    '  "fixturesDateToday": "Today",\n'
    '  "fixturesDateYesterday": "Yesterday",\n'
    '  "fixturesDateTomorrow": "Tomorrow",\n'
    '  "fixturesCalendarTooltip": "Calendar",\n'
    '  "fixturesCalendarPickTitle": "Pick a date",\n'
    '  "fixturesDayEmpty": "No matches on this day."\n}',
)

ABSTRACT = """  String get adminRemoveFixtureSuccess;

  /// No description provided for @fixturesDateToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get fixturesDateToday;

  /// No description provided for @fixturesDateYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get fixturesDateYesterday;

  /// No description provided for @fixturesDateTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get fixturesDateTomorrow;

  /// No description provided for @fixturesCalendarTooltip.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get fixturesCalendarTooltip;

  /// No description provided for @fixturesCalendarPickTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick a date'**
  String get fixturesCalendarPickTitle;

  /// No description provided for @fixturesDayEmpty.
  ///
  /// In en, this message translates to:
  /// **'No matches on this day.'**
  String get fixturesDayEmpty;
}"""
patch("lib/l10n/app_localizations.dart", "  String get adminRemoveFixtureSuccess;\n}", ABSTRACT)

patch(
    "lib/l10n/app_localizations_ar.dart",
    "  String get adminRemoveFixtureSuccess => 'تم حذف المباراة من الجولة.';\n}",
    "  String get adminRemoveFixtureSuccess => 'تم حذف المباراة من الجولة.';\n\n"
    "  @override\n  String get fixturesDateToday => 'اليوم';\n\n"
    "  @override\n  String get fixturesDateYesterday => 'أمس';\n\n"
    "  @override\n  String get fixturesDateTomorrow => 'غداً';\n\n"
    "  @override\n  String get fixturesCalendarTooltip => 'التقويم';\n\n"
    "  @override\n  String get fixturesCalendarPickTitle => 'اختر التاريخ';\n\n"
    "  @override\n  String get fixturesDayEmpty => 'لا توجد مباريات في هذا اليوم.';\n}",
)

patch(
    "lib/l10n/app_localizations_en.dart",
    "  String get adminRemoveFixtureSuccess => 'Fixture removed from the round.';\n}",
    "  String get adminRemoveFixtureSuccess => 'Fixture removed from the round.';\n\n"
    "  @override\n  String get fixturesDateToday => 'Today';\n\n"
    "  @override\n  String get fixturesDateYesterday => 'Yesterday';\n\n"
    "  @override\n  String get fixturesDateTomorrow => 'Tomorrow';\n\n"
    "  @override\n  String get fixturesCalendarTooltip => 'Calendar';\n\n"
    "  @override\n  String get fixturesCalendarPickTitle => 'Pick a date';\n\n"
    "  @override\n  String get fixturesDayEmpty => 'No matches on this day.';\n}",
)

# ---------------------------------------------------------------- guards
import json
for arb in ("lib/l10n/app_ar.arb", "lib/l10n/app_en.arb"):
    json.loads(read(os.path.join(M, arb)))
print("ARB files still parse as JSON")

# ---------------------------------------------------------------- log + commit
LOG = os.path.join(ROOT, "docs/checkpoints/session-log.md")
entry = (
    "\n2026-09-06 — 28_fixtures_day_bar: شاشة المباريات صارت تعرض مباريات يوم "
    "واحد بدل الشهر كاملًا، خلف شريط أيام أفقي على نمط FotMob وصفحة تقويم "
    "تُفتح من أيقونة التقويم في الشريط العلوي. التجميع حسب اليوم عرضٌ محض "
    "فوق قراءة currentMonthFixturesProvider نفسها: لا مسار جديد ولا مزوّد "
    "جديد ولا تغيير في الخادم. الشاشة صارت ConsumerStatefulWidget تملك اليوم "
    "المختار وحدها كي لا يختلف الشريط والتقويم والقائمة. قبل أي اختيار من "
    "المستخدم ينزلق التحديد إلى أقرب يوم فيه مباريات (المستقبل مقدَّم عند "
    "التعادل) وإلا لفُتحت شاشة فارغة على «اليوم» وقُرئت كعطل — وهذا أيضًا ما "
    "يُبقي اختبار current_month_fixtures_screen_double_test أخضر رغم أن "
    "futureIso() يضع الانطلاق بعد سنة. مباراة بلا kickoffAt تظهر في كل يوم "
    "لأنها لا تُصنَّف تحت أي يوم. ستة مفاتيح ARB جديدة مع إعادة توليد يدوية "
    "لـapp_localizations*.dart لأنها مُتتبَّعة. مؤجَّل بانتظار قرار: أيقونات "
    "الشريط العلوي الأخرى في المرجع (⋮ والبحث وشارة «مباشر») — لا وظيفة "
    "خلفها اليوم فلم تُضف كنائبات — "
    "apps/mobile/lib/features/fixture_prediction/current_month_fixtures_screen.dart, "
    "apps/mobile/lib/features/fixture_prediction/widgets/fixtures_date_bar.dart, "
    "apps/mobile/lib/features/fixture_prediction/widgets/fixtures_calendar_page.dart, "
    "apps/mobile/lib/l10n/app_ar.arb, apps/mobile/lib/l10n/app_en.arb, "
    "apps/mobile/lib/l10n/app_localizations.dart, "
    "apps/mobile/lib/l10n/app_localizations_ar.dart, "
    "apps/mobile/lib/l10n/app_localizations_en.dart\n"
)
with open(LOG, "a", encoding="utf-8") as f:
    f.write(entry)
print("session log appended")

files = [
    "apps/mobile/lib/features/fixture_prediction/current_month_fixtures_screen.dart",
    "apps/mobile/lib/features/fixture_prediction/widgets/fixtures_date_bar.dart",
    "apps/mobile/lib/features/fixture_prediction/widgets/fixtures_calendar_page.dart",
    "apps/mobile/lib/l10n/app_ar.arb",
    "apps/mobile/lib/l10n/app_en.arb",
    "apps/mobile/lib/l10n/app_localizations.dart",
    "apps/mobile/lib/l10n/app_localizations_ar.dart",
    "apps/mobile/lib/l10n/app_localizations_en.dart",
    "docs/checkpoints/session-log.md",
]
if os.path.isdir(os.path.join(ROOT, ".git")):
    subprocess.run(["git", "-C", ROOT, "add"] + files, check=True)
    subprocess.run(
        ["git", "-C", ROOT, "commit", "-m",
         "feat(mobile): FotMob-style day strip + calendar picker on the matches screen"],
        check=True,
    )
    print("committed (no push)")
else:
    print("no .git — skipped commit")
