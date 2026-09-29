/// Tells the app when the Riyadh day turns over, so a screen left open does
/// not keep showing yesterday -- or, on the 1st, last month.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

/// Calls [onTurnover] when the Riyadh day changes: at 00:00 Riyadh while the
/// app is open, and when the player comes back to the app after a midnight
/// passed in between.
///
/// The Riyadh day is the app's day everywhere (the month runs 00:00 to 00:00
/// Riyadh, migration 0076), so the turnover is computed in UTC+3 -- Riyadh
/// has no daylight saving -- and never from the device's own zone.
///
/// A device clock can run a little ahead of the server's; a refresh that
/// lands a few seconds early would read the old month again. So the turnover
/// fires a few seconds after midnight and once more two minutes later.
final class RiyadhDayTurnover with WidgetsBindingObserver {
  /// Creates the watcher; [now] replaces the clock in tests.
  RiyadhDayTurnover({required this.onTurnover, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// What to do when the day changes.
  final VoidCallback onTurnover;

  final DateTime Function() _now;
  Timer? _timer;
  Timer? _followUp;
  DateTime? _day;

  static const Duration _riyadh = Duration(hours: 3);

  /// How long after midnight the first refresh runs.
  static const Duration settle = Duration(seconds: 5);

  /// When the second refresh runs, after the first.
  static const Duration followUp = Duration(minutes: 2);

  /// The Riyadh calendar day of [instant], as a UTC date.
  static DateTime riyadhDayOf(DateTime instant) {
    final DateTime r = instant.toUtc().add(_riyadh);
    return DateTime.utc(r.year, r.month, r.day);
  }

  /// The next 00:00 Riyadh after [instant], in UTC.
  static DateTime nextRiyadhMidnight(DateTime instant) =>
      riyadhDayOf(instant).add(const Duration(days: 1)).subtract(_riyadh);

  /// Starts watching.
  void start() {
    _day = riyadhDayOf(_now());
    WidgetsBinding.instance.addObserver(this);
    _arm();
  }

  /// Stops watching; nothing fires afterwards.
  void stop() {
    _timer?.cancel();
    _followUp?.cancel();
    _timer = null;
    _followUp = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  void _arm() {
    _timer?.cancel();
    final DateTime now = _now().toUtc();
    _timer = Timer(nextRiyadhMidnight(now).difference(now) + settle, _check);
  }

  void _check() {
    final DateTime day = riyadhDayOf(_now());
    if (day != _day) {
      _day = day;
      onTurnover();
      _followUp?.cancel();
      _followUp = Timer(followUp, onTurnover);
    }
    _arm();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }
}
