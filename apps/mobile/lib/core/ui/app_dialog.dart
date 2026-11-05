library;

import 'package:flutter/material.dart';
import '../design/app_spacing.dart';
import 'app_button.dart';

abstract final class AppDialog {
  static Future<bool?> confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    required String cancelLabel,
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actionsPadding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          // Stacked, the confirm first: side by side the two buttons were 46
          // dp tall and a long label ("Sign out") ended in an ellipsis on a
          // 384 dp phone (Accessibility Scanner, 2026-11-05, script 215).
          actions: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppButton(
                  label: confirmLabel,
                  variant: destructive
                      ? AppButtonVariant.danger
                      : AppButtonVariant.primary,
                  size: AppButtonSize.medium,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: cancelLabel,
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.medium,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
