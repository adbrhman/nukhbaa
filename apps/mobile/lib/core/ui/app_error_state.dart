library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../design/app_sizes.dart';
import '../design/app_spacing.dart';
import '../design/app_tokens.dart';
import '../error/error_presenter.dart';
import 'app_button.dart';

class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    this.message,
    this.onRetry,
    this.retryLabel = 'إعادة المحاولة',
  });

  final String? message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;
    final String? problemCode = message == null
        ? null
        : ErrorPresenter.problemCodeIn(message!);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x3l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: AppSizes.iconStateLg,
              color: tokens.error,
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              message ?? 'حدث خطأ ما',
              textAlign: TextAlign.center,
              style: text.bodyLarge?.copyWith(color: tokens.textSecondary),
            ),
            if (problemCode != null) ...[
              const SizedBox(height: AppSpacing.md),
              TextButton.icon(
                key: const Key('error.copyProblemCode'),
                onPressed: () {
                  unawaited(
                    Clipboard.setData(ClipboardData(text: problemCode)),
                  );
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('نسخ رمز المشكلة'),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: retryLabel,
                onPressed: onRetry,
                expand: false,
                size: AppButtonSize.medium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
