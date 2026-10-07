/// The "live" chip in the matches app bar. Its dot is red — and the chip
/// tappable — only while at least one fixture is actually in play;
/// otherwise it sits quiet and disabled rather than disappearing, so its
/// absence is never mistaken for a loading state.
///
/// The dot is steady. It used to pulse forever (a repeating controller):
/// the shell keeps the matches tab alive in an IndexedStack, so through
/// every match the app drew sixty frames a second, on whatever tab was
/// open, for a dot -- and each frame repainted the whole screen. On a
/// low-end phone those frames were what the slow-frame figure counted.
///
/// "In play" is a **time estimate, not a server fact**: the feed carries a
/// kickoff instant and nothing else — no `live` / `finished` status — so
/// [liveWindow] below is the whole definition. Approved as option (أ) over
/// adding a real status field, which would have reached the contracts, the
/// routes and the database. If a status field ever lands, this constant and
/// [isFixtureLive] are the only two things that should change.
library;

import 'package:flutter/material.dart';

import '../../../core/design/app_typography.dart';
import '../../../core/design/app_motion.dart';
import '../../../core/design/app_sizes.dart';
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
class LiveMatchesChip extends StatelessWidget {
  /// Creates the chip.
  const LiveMatchesChip({
    required this.hasLive,
    required this.selected,
    required this.onTap,
    super.key,
  });

  /// Whether any fixture is in play. Drives the red dot and the enabled
  /// state.
  final bool hasLive;

  /// Whether the live-only filter is currently on.
  final bool selected;

  /// Toggles the live-only filter.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final bool enabled = hasLive;
    final Color dotColor = enabled ? tokens.error : tokens.textMuted;
    final Color foreground = selected
        ? tokens.onPrimary
        : enabled
        ? tokens.textPrimary
        : tokens.textMuted;

    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: l10n.fixturesLiveLabel,
      // An InkWell, not a bare GestureDetector: on the web it takes keyboard
      // focus (Tab, then Enter) and shows the pointer hand (UI-25).
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const Key('currentMonthFixtures.live'),
          customBorder: const StadiumBorder(),
          onTap: enabled ? onTap : null,
          // A full 48 touch target around the 32px pill (UI-16).
          child: SizedBox(
            height: AppSizes.minTouchTarget,
            child: Center(
              widthFactor: 1,
              child: AnimatedContainer(
                duration: AppMotion.fast,
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                decoration: ShapeDecoration(
                  shape: const StadiumBorder(),
                  color: selected
                      ? tokens.primary
                      : tokens.textPrimary.withValues(alpha: 0.08),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      key: const Key('currentMonthFixtures.live.dot'),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dotColor,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      l10n.fixturesLiveLabel,
                      style: TextStyle(
                        fontSize: AppFontSize.s13,
                        fontWeight: FontWeight.w700,
                        color: foreground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
