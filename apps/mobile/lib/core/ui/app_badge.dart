library;

import 'package:flutter/material.dart';
import '../design/app_spacing.dart';
import '../design/app_tokens.dart';

enum AppBadgeTone { primary, gold, success, danger, muted, neutral }

class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    this.tone = AppBadgeTone.neutral,
    this.icon,
  });

  final String       label;
  final AppBadgeTone tone;
  final IconData?    icon;

  static const double _pillRadius = 999;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final TextTheme  text  = context.text;

    final (Color bg, Color fg) = switch (tone) {
      AppBadgeTone.primary => (
          tokens.primary.withValues(alpha: 0.14),
          tokens.primary,
        ),
      AppBadgeTone.gold => (
          tokens.gold.withValues(alpha: 0.16),
          tokens.gold,
        ),
      AppBadgeTone.success => (
          tokens.primary.withValues(alpha: 0.14),
          tokens.primaryLight,
        ),
      AppBadgeTone.danger => (
          tokens.error.withValues(alpha: 0.14),
          tokens.error,
        ),
      AppBadgeTone.muted   => (tokens.surfaceHigh,     tokens.textMuted),
      AppBadgeTone.neutral => (tokens.surfaceElevated, tokens.textSecondary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical:   AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color:        bg,
        borderRadius: BorderRadius.circular(_pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(label, style: text.labelSmall?.copyWith(color: fg)),
        ],
      ),
    );
  }
}
