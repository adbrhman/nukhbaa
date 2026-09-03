import 'package:flutter/material.dart';

import '../design/app_radius.dart';
import '../design/app_spacing.dart';
import '../design/app_tokens.dart';

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
        '$home - $away',
        style: TextStyle(
          color: tokens.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
