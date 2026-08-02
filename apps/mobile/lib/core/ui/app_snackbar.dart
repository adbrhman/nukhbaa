library;

import 'package:flutter/material.dart';
import '../design/app_spacing.dart';
import '../design/app_tokens.dart';

enum AppSnackTone { success, error, neutral }

abstract final class AppSnackbar {
  static void show(
    BuildContext context,
    String message, {
    AppSnackTone tone = AppSnackTone.neutral,
  }) {
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;

    final (Color accent, IconData icon) = switch (tone) {
      AppSnackTone.success => (tokens.primaryLight, Icons.check_circle_outline),
      AppSnackTone.error => (tokens.error, Icons.error_outline_rounded),
      AppSnackTone.neutral => (
        tokens.textSecondary,
        Icons.info_outline_rounded,
      ),
    };

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, size: 20, color: accent),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  message,
                  style: text.bodyMedium?.copyWith(color: tokens.textPrimary),
                ),
              ),
            ],
          ),
        ),
      );
  }
}
