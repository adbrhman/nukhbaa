import 'package:flutter/material.dart';

import '../design/app_typography.dart';
import '../design/app_tokens.dart';

class StreakChip extends StatelessWidget {
  const StreakChip({required this.label, this.icon, super.key});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.isDark ? tokens.surfaceElevated : tokens.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      // The label wraps inside the space it is given instead of being
      // shrunk by a FittedBox around the chip, so it grows with the
      // system text like the rest of the screen (UI-17).
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 13, color: tokens.onPrimary),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: tokens.onPrimary,
                fontSize: AppFontSize.s12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
