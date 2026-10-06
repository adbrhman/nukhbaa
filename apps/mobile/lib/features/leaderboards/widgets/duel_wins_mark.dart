/// The duels a player won this month, beside their name on the leaderboard
/// (phase 1 of the plan): the duels icon and the count. A record, never a
/// rank -- duels carry no points (decided 2026-10-06).
library;

import 'package:flutter/material.dart';

import '../../../core/design/app_sizes.dart';
import '../../../core/design/app_tokens.dart';

/// "Won N duels", in Arabic with its plural forms.
String duelWinsLabel(int wins) => switch (wins) {
  1 => 'فاز في مواجهة واحدة',
  2 => 'فاز في مواجهتين',
  >= 3 && <= 10 => 'فاز في $wins مواجهات',
  _ => 'فاز في $wins مواجهة',
};

/// The mark itself; the board shows it only for a player with wins.
class DuelWinsMark extends StatelessWidget {
  /// Creates the mark for [wins] duels won.
  const DuelWinsMark({required this.wins, super.key});

  /// Duels won this month.
  final int wins;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Tooltip(
      message: duelWinsLabel(wins),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.compare_arrows_rounded,
            size: AppSizes.iconInline,
            color: t.primaryText,
          ),
          const SizedBox(width: 2),
          Text(
            '$wins',
            style: context.text.labelSmall?.copyWith(
              color: t.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
