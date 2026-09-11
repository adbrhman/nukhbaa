/// The FotMob-style **day strip** that sits under the matches app bar
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
  /// 40 still fits the 14px label, its 8px gap and the 3px underline,
  /// with the leading spacer absorbing the rest.
  static const double height = 40;

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

  /// The very first centring jumps rather than animates — animating from
  /// offset 0 on the first frame reads as the strip sliding away on its
  /// own before the user has touched anything.
  bool _centredOnce = false;

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
        duration: _centredOnce ? AppMotion.fast : Duration.zero,
        curve: AppMotion.standardCurve,
      );
      _centredOnce = true;
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
      child: SingleChildScrollView(
        key: const Key('currentMonthFixtures.dayStrip'),
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Row(
          children: <Widget>[
            for (int index = 0; index < _radius * 2 + 1; index++)
              _DayTab(
                key: index == _radius ? _selectedKey : null,
                label: _label(
                  context,
                  selected.add(Duration(days: index - _radius)),
                  today,
                ),
                selected: index == _radius,
                tokens: tokens,
                onTap: () => widget.onDaySelected(
                  selected.add(Duration(days: index - _radius)),
                ),
              ),
          ],
        ),
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
