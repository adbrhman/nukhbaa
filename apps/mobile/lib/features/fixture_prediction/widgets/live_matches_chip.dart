/// The "live" chip in the matches app bar. It pulses — and is tappable —
/// only while at least one fixture is actually in play; otherwise it sits
/// quiet and disabled rather than disappearing, so its absence is never
/// mistaken for a loading state.
///
/// "In play" is a **time estimate, not a server fact**: the feed carries a
/// kickoff instant and nothing else — no `live` / `finished` status — so
/// [liveWindow] below is the whole definition. Approved as option (أ) over
/// adding a real status field, which would have reached the contracts, the
/// routes and the database. If a status field ever lands, this constant and
/// [isFixtureLive] are the only two things that should change.
library;

import 'package:flutter/material.dart';

import '../../../core/design/app_motion.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../l10n/app_localizations.dart';

/// How long after kickoff a fixture is still treated as in play — a full
/// match plus half-time and stoppage, rounded up.
const Duration liveWindow = Duration(minutes: 120);

/// Whether a fixture kicking off at [kickoffAt] (an ISO-8601 instant, or
/// `null` when unscheduled) is in play right now.
bool isFixtureLive(String? kickoffAt) {
  if (kickoffAt == null) return false;
  final DateTime? kickoff = DateTime.tryParse(kickoffAt)?.toUtc();
  if (kickoff == null) return false;
  final DateTime now = DateTime.now().toUtc();
  if (!now.isAfter(kickoff)) return false;
  return now.difference(kickoff) < liveWindow;
}

/// The chip itself.
class LiveMatchesChip extends StatefulWidget {
  /// Creates the chip.
  const LiveMatchesChip({
    required this.hasLive,
    required this.selected,
    required this.onTap,
    super.key,
  });

  /// Whether any fixture is in play. Drives the pulse and the enabled state.
  final bool hasLive;

  /// Whether the live-only filter is currently on.
  final bool selected;

  /// Toggles the live-only filter.
  final VoidCallback onTap;

  @override
  State<LiveMatchesChip> createState() => _LiveMatchesChipState();
}

class _LiveMatchesChipState extends State<LiveMatchesChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.hasLive) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant LiveMatchesChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hasLive == oldWidget.hasLive) return;
    if (widget.hasLive) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final bool enabled = widget.hasLive;
    final Color dotColor = enabled ? tokens.error : tokens.textMuted;
    final Color foreground = widget.selected
        ? tokens.onPrimary
        : enabled
        ? tokens.textPrimary
        : tokens.textMuted;

    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.selected,
      label: l10n.fixturesLiveLabel,
      child: GestureDetector(
        key: const Key('currentMonthFixtures.live'),
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: ShapeDecoration(
            shape: const StadiumBorder(),
            color: widget.selected
                ? tokens.primary
                : tokens.textPrimary.withValues(alpha: 0.08),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              FadeTransition(
                // Never fades to nothing: the dot stays legible at its
                // dimmest, so the pulse reads as a heartbeat rather than
                // as the chip flickering in and out.
                opacity: Tween<double>(
                  begin: 0.35,
                  end: 1,
                ).animate(_pulse),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                l10n.fixturesLiveLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
