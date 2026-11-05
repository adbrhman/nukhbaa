/// The **day strip** that sits under the matches app bar
/// (`current_month_fixtures_screen.dart`): one horizontally scrollable chip
/// per calendar day -- weekday on top, date below -- the selected one filled
/// blue. Yesterday / today / tomorrow carry a small badge on top.
///
/// Purely presentational: it owns no fixture read and no selection state.
/// The screen owns the selected day and hands it down, so the strip, the
/// calendar page and the filtered list can never disagree.
library;

import 'dart:async';

import 'package:flutter/material.dart';
// intl is a transitive dependency via flutter_localizations, the same way
// the generated l10n files import it; the "no new dependencies" rule means
// it is not declared in pubspec.yaml just to silence this lint.
// ignore: depend_on_referenced_packages
import 'package:intl/intl.dart' as intl;

import '../../../core/design/app_typography.dart';
import '../../../core/design/app_motion.dart';
import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/time/riyadh_day_turnover.dart';
import '../../../l10n/app_localizations.dart';

/// Midnight-local for [value] — the canonical "day" key used by the strip,
/// the calendar page and the screen's own filter alike. It only normalises
/// a key: an instant becomes a key through [RiyadhDayTurnover.dayKeyOf],
/// so every device files a match under the server's day.
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

  /// The strip's height at normal text size, for the app bar's
  /// `PreferredSize`: a 58px chip (badge, weekday, date) plus its margin.
  /// It was 70 with twice the margin; the owner asked for a tighter strip
  /// (2026-10-15).
  static const double height = 64;

  /// The strip's height at the reader's text size: the chips grow with it
  /// instead of shrinking their text to a fixed height (UI-17), so the app
  /// bar asks for this rather than [height].
  static double heightFor(BuildContext context) {
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    final double content =
        _DayTab.badgeHeightFor(scaler) +
        scaler.scale(AppFontSize.s13) * 1.2 +
        scaler.scale(AppFontSize.s10) * 1.2;
    // Margin 6, chip padding 8, border 2, and 4 to spare for rounding.
    final double fitted = content + 20;
    return fitted > height ? fitted : height;
  }

  @override
  State<FixturesDateStrip> createState() => _FixturesDateStripState();
}

class _FixturesDateStripState extends State<FixturesDateStrip> {
  /// Days rendered on each side of the selection — the window always
  /// recentres on the selected day, so the strip stays usable however far
  /// the calendar page jumps.
  static const int _radius = 7;

  /// All the chips the window draws.
  static const int _count = _radius * 2 + 1;

  /// The narrowest chip slot at normal text size: about six days on a
  /// phone, each still a 48 px target or more (the owner asked for smaller
  /// chips, 2026-10-15). The slot grows with the reader's text.
  static const double _minSlot = 64;

  final ScrollController _controller = ScrollController();

  /// The slot width and the number of slots in view at the last layout. The
  /// strip shows whole chips only (script 214): a chip cut by the screen's
  /// edge was a 20 dp touch target to the Accessibility Scanner on every
  /// matches screen, so the view is a whole number of slots wide and a
  /// swipe comes to rest on a slot.
  double _slot = 0;
  int _perView = 0;

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

  /// Puts the selected chip in the middle slot of the view, on a slot edge.
  void _scheduleCentre() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients || _slot <= 0) return;
      final ScrollPosition position = _controller.position;
      final double wanted = (_radius - (_perView - 1) / 2) * _slot;
      final double target = ((wanted / _slot).round() * _slot)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if (_centredOnce) {
        unawaited(
          _controller.animateTo(
            target,
            duration: AppMotion.fast,
            curve: AppMotion.standardCurve,
          ),
        );
      } else {
        _controller.jumpTo(target);
      }
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
    final DateTime today = RiyadhDayTurnover.dayKeyOf(DateTime.now());
    final DateTime selected = fixtureDayOnly(widget.selectedDay);
    final double textGrowth =
        MediaQuery.textScalerOf(context).scale(AppFontSize.s13) /
        AppFontSize.s13;

    return SizedBox(
      height: FixturesDateStrip.heightFor(context),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double room = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : _minSlot * 6;
          final double minSlot = _minSlot * (textGrowth < 1 ? 1 : textGrowth);
          final int perView = (room / minSlot).floor().clamp(2, _count).toInt();
          final double slot = room / perView;
          _slot = slot;
          _perView = perView;
          return SingleChildScrollView(
            key: const Key('currentMonthFixtures.dayStrip'),
            controller: _controller,
            scrollDirection: Axis.horizontal,
            physics: _SlotSnapPhysics(slot: slot),
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: <Widget>[
                for (int index = 0; index < _count; index++)
                  _DayTab(
                    width: slot,
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
          );
        },
      ),
    );
  }
}

/// Scroll physics that bring the strip to rest on a whole slot, as
/// [PageScrollPhysics] does for pages but with the slot, not the viewport,
/// as the step: no chip is left cut by the edge of the screen.
class _SlotSnapPhysics extends ScrollPhysics {
  const _SlotSnapPhysics({required this.slot, super.parent});

  /// The width of one chip slot.
  final double slot;

  @override
  _SlotSnapPhysics applyTo(ScrollPhysics? ancestor) =>
      _SlotSnapPhysics(slot: slot, parent: buildParent(ancestor));

  double _targetOf(ScrollMetrics position, Tolerance tolerance, double v) {
    final double slots = position.pixels / slot;
    final double target = v.abs() < tolerance.velocity
        ? slots.roundToDouble()
        : (v > 0 ? slots.ceilToDouble() : slots.floorToDouble());
    return (target * slot)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    // Out of range and not headed back in: the parent puts it back.
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final Tolerance tolerance = toleranceFor(position);
    final double target = _targetOf(position, tolerance, velocity);
    if (target != position.pixels) {
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        target,
        velocity,
        tolerance: tolerance,
      );
    }
    return null;
  }

  @override
  bool get allowImplicitScrolling => false;
}

/// One day chip: an optional relative badge, the weekday and the date. The
/// selected chip is filled with the action colour; the rest sit on the
/// surface colour with a hairline border, so the strip reads as a row of
/// days rather than as text.
class _DayTab extends StatelessWidget {
  const _DayTab({
    required this.width,
    required this.weekday,
    required this.date,
    required this.badge,
    required this.selected,
    required this.tokens,
    required this.onTap,
  });

  /// The chip's whole slot, its margin included.
  final double width;
  final String weekday;
  final String date;
  final String? badge;
  final bool selected;
  final AppTokens tokens;
  final VoidCallback onTap;

  /// The relative badge's height: 15 at normal size, and room for its
  /// 10px text, line height 1.1, once the reader's text is larger.
  static double badgeHeightFor(TextScaler scaler) {
    final double fitted = scaler.scale(AppFontSize.s10) * 1.1 + 4;
    return fitted > 15 ? fitted : 15;
  }

  @override
  Widget build(BuildContext context) {
    final String? relative = badge;
    final Color primaryText = selected ? tokens.onPrimary : tokens.textPrimary;
    // Full white on the selected chip: at 85% it read 3.7:1 (UI-02).
    final Color secondaryText = selected ? tokens.onPrimary : tokens.textMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs / 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.brMd,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            width: width - AppSpacing.xs,
            padding: const EdgeInsets.symmetric(
              vertical: 4,
              horizontal: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: selected ? tokens.primary : tokens.surface,
              borderRadius: AppRadius.brMd,
              border: Border.all(
                color: selected ? tokens.primary : tokens.controlBorder,
              ),
            ),
            // The strip grows with the reader's text size (heightFor), so
            // the three lines keep their size instead of scaling down to a
            // fixed height (UI-17).
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  height: badgeHeightFor(MediaQuery.textScalerOf(context)),
                  child: relative == null
                      ? null
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          alignment: Alignment.center,
                          // Script 162: a neutral tag -- yesterday, today and
                          // tomorrow are dates, not achievements, so no gold.
                          decoration: BoxDecoration(
                            color: tokens.surfaceHigh,
                            borderRadius: AppRadius.brSm,
                          ),
                          child: Text(
                            relative,
                            maxLines: 1,
                            // 13:1 or better on the raised surface in both
                            // themes (AAA).
                            style: TextStyle(
                              fontSize: AppFontSize.s10,
                              height: 1.1,
                              fontWeight: FontWeight.w800,
                              color: tokens.textPrimary,
                            ),
                          ),
                        ),
                ),
                Text(
                  weekday,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppFontSize.s13,
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
                    fontSize: AppFontSize.s10,
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
