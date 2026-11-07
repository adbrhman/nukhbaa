/// The way into the Hall of Fame, drawn on the leaderboard tab where every
/// player sees it (the crown in the header was too easy to miss).
library;

import 'package:flutter/material.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../l10n/app_localizations.dart';
import 'trophy_cup.dart';

/// A full-width card: the gold cup, the hall's name, what is inside, a chevron.
class HallEntryCard extends StatelessWidget {
  /// Creates the card; [onTap] opens the hall.
  const HallEntryCard({required this.onTap, super.key});

  /// Opens the Hall of Fame.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    return Material(
      color: t.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.brLg,
        side: BorderSide(color: t.gold.withValues(alpha: 0.55)),
      ),
      child: InkWell(
        key: const Key('leaderboards.hall.entry'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: <Widget>[
                TrophyCup(light: t.goldAccent, dark: t.gold, size: 40),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l10n.hallOfFame,
                        style: context.text.titleSmall?.copyWith(
                          color: t.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        l10n.hallEntrySubtitle,
                        style: context.text.labelMedium?.copyWith(
                          color: t.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  rtl ? Icons.chevron_left : Icons.chevron_right,
                  color: t.gold,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
