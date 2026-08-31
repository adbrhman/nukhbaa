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
  const KickoffCountdown({required this.kickoffAt, super.key});

  /// The fixture's kickoff time as an ISO-8601 string, or `null`.
  final String? kickoffAt;

  @override
  State<KickoffCountdown> createState() => _KickoffCountdownState();
}

class _KickoffCountdownState extends State<KickoffCountdown> {
  Timer? _timer;
  DateTime? _kickoff;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _resync();
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
    _timer?.cancel();
    super.dispose();
  }

  void _resync() {
    _timer?.cancel();
    _kickoff = _parse(widget.kickoffAt);
    _tick();
    if (_kickoff != null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
  }

  DateTime? _parse(String? raw) =>
      raw == null ? null : DateTime.tryParse(raw)?.toUtc();

  void _tick() {
    final kickoff = _kickoff;
    if (kickoff == null) return;
    final next = kickoff.difference(DateTime.now().toUtc());
    if (next.isNegative) {
      _timer?.cancel();
      if (mounted) setState(() => _remaining = Duration.zero);
      return;
    }
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
    return '$h:$m:$s';
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
