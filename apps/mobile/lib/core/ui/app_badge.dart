library;

import 'package:flutter/material.dart';
import '../design/app_sizes.dart';
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

  final String label;
  final AppBadgeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;

    final (Color bg, Color fg) = switch (tone) {
      AppBadgeTone.primary => (
        tokens.primary.withValues(alpha: 0.14),
        tokens.primaryText,
      ),
      AppBadgeTone.gold => (tokens.gold.withValues(alpha: 0.16), tokens.gold),
      // Green means success and red means danger (2026-09-24), each in
      // the text shade made for its own container (UI-06).
      AppBadgeTone.success => (tokens.successContainer, tokens.successText),
      AppBadgeTone.danger => (tokens.errorContainer, tokens.errorText),
      AppBadgeTone.muted => (tokens.surfaceHigh, tokens.textMuted),
      AppBadgeTone.neutral => (tokens.surfaceElevated, tokens.textSecondary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AppSizes.iconInline, color: fg),
            const SizedBox(width: AppSpacing.xs),
          ],
          // Flexible: a long label at large text wraps inside the badge
          // instead of pushing it past its row (UI-36).
          Flexible(
            child: Text(label, style: text.labelSmall?.copyWith(color: fg)),
          ),
        ],
      ),
    );
  }
}
