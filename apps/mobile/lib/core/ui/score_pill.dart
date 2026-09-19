import 'package:flutter/material.dart';

import '../design/app_radius.dart';
import '../design/app_spacing.dart';
import '../design/app_tokens.dart';

/// The "home - away" label of a scoreline, ordered to match the two
/// team columns drawn beside it.
///
/// Every scoreboard row lists the home team first and lets the ambient
/// [Directionality] place it: in Arabic (RTL) the home team is on the
/// RIGHT and the away team on the LEFT. The label itself is always drawn
/// left-to-right, so its first number must belong to whichever team is on
/// the left: the away team in RTL, the home team in LTR. Writing
/// `'$home - $away'` unconditionally put the home score under the away
/// team in Arabic (a 2-0 home win read as 0-2 against the crests).
String orientedScoreLabel(BuildContext context, int home, int away) =>
    Directionality.of(context) == TextDirection.rtl
    ? '$away - $home'
    : '$home - $away';

class ScorePill extends StatelessWidget {
  const ScorePill({required this.home, required this.away, super.key});

  final int home;
  final int away;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: AppRadius.brSm,
        border: Border.all(color: tokens.border),
      ),
      child: Text(
        orientedScoreLabel(context, home, away),
        // Two LTR digit runs around a neutral separator: without an
        // explicit direction the Arabic (RTL) paragraph reorders them and
        // a 2-0 prediction reads as 0-2 on screen. The label is therefore
        // always drawn left-to-right, and orientedScoreLabel decides which
        // score comes first so it sits under its own team.
        textDirection: TextDirection.ltr,
        style: TextStyle(
          color: tokens.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
