library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../design/app_sizes.dart';
import '../design/app_spacing.dart';
import '../design/app_tokens.dart';
import '../error/error_presenter.dart';

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
      // Green is success across the app, not the action blue (UI-23).
      AppSnackTone.success => (tokens.success, Icons.check_circle_outline),
      AppSnackTone.error => (tokens.error, Icons.error_outline_rounded),
      AppSnackTone.neutral => (
        tokens.textSecondary,
        Icons.info_outline_rounded,
      ),
    };

    // A message with a problem code offers to copy it, for the player to
    // send to the admins (migration 0087).
    final String? problemCode = ErrorPresenter.problemCodeIn(message);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          action: problemCode == null
              ? null
              : SnackBarAction(
                  label: 'نسخ الرمز',
                  onPressed: () {
                    unawaited(
                      Clipboard.setData(ClipboardData(text: problemCode)),
                    );
                  },
                ),
          content: Row(
            children: [
              Icon(icon, size: AppSizes.iconMd, color: accent),
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
