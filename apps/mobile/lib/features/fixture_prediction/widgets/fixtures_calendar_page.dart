/// The full-screen month calendar the matches app bar's calendar icon
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
