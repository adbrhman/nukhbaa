/// The **day strip** that sits under the matches app bar
/// (`current_month_fixtures_screen.dart`): one horizontally scrollable chip
/// per calendar day -- weekday on top, date below -- the selected one filled
/// blue. Yesterday / today / tomorrow carry a small badge on top.
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
import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/theme/app_colors.dart';
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

  /// The strip's fixed height, for the app bar's `PreferredSize`: a 58px
  /// chip (badge, weekday, date) plus its vertical margin.
  static const double height = 70;

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

  /// "اليوم" / "أمس" / "غداً" for the three days around today, else null.
  String? _relative(BuildContext context, DateTime day, DateTime today) {
    final l10n = AppLocalizations.of(context);
    final int diff = day.difference(today).inDays;
    if (diff == 0) return l10n.fixturesDateToday;
    if (diff == -1) return l10n.fixturesDateYesterday;
    if (diff == 1) return l10n.fixturesDateTomorrow;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final String locale = Localizations.localeOf(context).toString();
    final intl.DateFormat weekdayFormat = intl.DateFormat.EEEE(locale);
    final intl.DateFormat dateFormat = intl.DateFormat('d MMMM', locale);
    final DateTime today = fixtureDayOnly(DateTime.now());
    final DateTime selected = fixtureDayOnly(widget.selectedDay);

    return SizedBox(
      height: FixturesDateStrip.height,
      child: SingleChildScrollView(
        key: const Key('currentMonthFixtures.dayStrip'),
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 6,
        ),
        child: Row(
          children: <Widget>[
            for (int index = 0; index < _radius * 2 + 1; index++)
              _DayTab(
                key: index == _radius ? _selectedKey : null,
                weekday: weekdayFormat.format(
                  selected.add(Duration(days: index - _radius)),
                ),
                date: dateFormat.format(
                  selected.add(Duration(days: index - _radius)),
                ),
                badge: _relative(
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

/// One day chip: an optional relative badge, the weekday and the date. The
/// selected chip is filled with the action colour; the rest sit on the
/// surface colour with a hairline border, so the strip reads as a row of
/// days rather than as text.
class _DayTab extends StatelessWidget {
  const _DayTab({
    required this.weekday,
    required this.date,
    required this.badge,
    required this.selected,
    required this.tokens,
    required this.onTap,
    super.key,
  });

  final String weekday;
  final String date;
  final String? badge;
  final bool selected;
  final AppTokens tokens;
  final VoidCallback onTap;

  static const double _width = 80;
  static const double _badgeHeight = 15;

  @override
  Widget build(BuildContext context) {
    final String? relative = badge;
    final Color primaryText = selected ? tokens.onPrimary : tokens.textPrimary;
    final Color secondaryText = selected
        ? tokens.onPrimary.withValues(alpha: 0.85)
        : tokens.textMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.brMd,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            width: _width,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: selected ? tokens.primary : tokens.surface,
              borderRadius: AppRadius.brMd,
              border: Border.all(
                color: selected ? tokens.primary : tokens.controlBorder,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                SizedBox(
                  height: _badgeHeight,
                  child: relative == null
                      ? null
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: tokens.gold,
                            borderRadius: AppRadius.brSm,
                          ),
                          child: Text(
                            relative,
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 9,
                              height: 1.1,
                              fontWeight: FontWeight.w800,
                              color: AppColors.onBronze,
                            ),
                          ),
                        ),
                ),
                Text(
                  weekday,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                    color: primaryText,
                  ),
                ),
                Text(
                  date,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
