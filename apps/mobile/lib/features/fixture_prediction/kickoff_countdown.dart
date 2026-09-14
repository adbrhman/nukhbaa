/// An isolated per-fixture kickoff countdown (Matches screen redesign,
/// `docs/project-context.md`). Owns its own 1-second [Timer] and rebuilds
/// only itself, never the surrounding fixture card — so ~15-20 simultaneous
/// cards on `CurrentMonthFixturesScreen` don't each force a full-card
/// rebuild (including the score inputs) every second.
///
/// Renders nothing (`SizedBox.shrink`) once kickoff has passed, or when
/// [kickoffAt] is `null`/unparsable (Axiom 3 nullability) — the parent
/// card's own lock logic stays the single source of truth for "closed";
/// this widget only ever shows live "time remaining" text while a fixture
/// is still open, so the two can never disagree.
///
/// Default: one independent [Timer.periodic] per instance — the simplest,
/// most isolated option. If real-device measurement later shows
/// battery/perf pressure from many concurrent timers on one screen, this
/// can be swapped for a single shared app-level ticker without changing
/// the constructor contract ([kickoffAt] in, a [Text] out).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/design/app_tokens.dart';
import '../../l10n/app_localizations.dart';

/// Shows the time remaining until [kickoffAt], updating every second.
class KickoffCountdown extends StatefulWidget {
  /// Creates a countdown to [kickoffAt] (an ISO-8601 UTC string, or `null`
  /// when the fixture carries no kickoff time).
  const KickoffCountdown({
    required this.kickoffAt,
    this.timePrefix = '',
    super.key,
  });

  /// The fixture's kickoff time as an ISO-8601 string, or `null`.
  final String? kickoffAt;

  /// Prepended only to the sub-day `HH:MM:SS` form. The day form is a full
  /// phrase on its own ("in 2 days"), while a bare clock needs a
  /// preposition inside a sentence ("starts in 05:12:33").
  final String timePrefix;

  @override
  State<KickoffCountdown> createState() => _KickoffCountdownState();
}

class _KickoffCountdownState extends State<KickoffCountdown>
    with WidgetsBindingObserver {
  Timer? _timer;
  DateTime? _kickoff;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resync();
  }

  /// PERF: the tab stays mounted inside the shell's IndexedStack and the
  /// timer kept firing while the app was in the background. Nothing can be
  /// read there, so the clock stops and resynchronises on resume.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resync();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void didUpdateWidget(covariant KickoffCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kickoffAt != widget.kickoffAt) {
      _resync();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  void _resync() {
    _timer?.cancel();
    _kickoff = _parse(widget.kickoffAt);
    _tick();
  }

  /// PERF: seconds are only ever drawn under a day (above that the text is
  /// "in 3 days", which a one-second rebuild redraws identically 86,400
  /// times a day, per card). The interval is therefore re-derived on every
  /// tick from what is left, and the timer is a self-rescheduling one-shot
  /// rather than a fixed periodic one.
  Duration _interval(Duration remaining) => remaining.inDays > 0
      ? const Duration(minutes: 1)
      : const Duration(seconds: 1);

  DateTime? _parse(String? raw) =>
      raw == null ? null : DateTime.tryParse(raw)?.toUtc();

  void _tick() {
    final kickoff = _kickoff;
    if (kickoff == null) return;
    final next = kickoff.difference(DateTime.now().toUtc());
    _timer?.cancel();
    if (next.isNegative) {
      if (mounted) setState(() => _remaining = Duration.zero);
      return;
    }
    _timer = Timer(_interval(next), _tick);
    if (mounted) setState(() => _remaining = next);
  }

  String _format(AppLocalizations l10n) {
    final d = _remaining;
    if (d.inDays > 0) {
      return l10n.kickoffCountdownDays(d.inDays);
    }
    final h = d.inHours.remainder(24).toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${widget.timePrefix}$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_kickoff == null || _remaining == Duration.zero) {
      return const SizedBox.shrink();
    }
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    return Text(
      _format(l10n),
      key: const Key('kickoffCountdown.text'),
      style: TextStyle(color: tokens.textSecondary, fontSize: 12),
    );
  }
}
