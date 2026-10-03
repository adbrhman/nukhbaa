library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/app_localizations.dart';
import '../design/app_sizes.dart';
import '../design/app_spacing.dart';
import '../design/app_tokens.dart';
import '../error/error_presenter.dart';
import 'app_button.dart';
import 'app_empty_state.dart';
import 'app_snackbar.dart';

class AppErrorState extends StatelessWidget {
  const AppErrorState({super.key, this.message, this.onRetry, this.retryLabel});

  final String? message;
  final VoidCallback? onRetry;

  /// Defaults to the localized "Retry".
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;
    final String? problemCode = message == null
        ? null
        : ErrorPresenter.problemCodeIn(message!);

    // A live region: a screen reader announces the failure when it appears,
    // instead of leaving the reader on a screen that silently changed
    // (UI-30).
    return AppStateFrame(
      child: Semantics(
        container: true,
        liveRegion: true,
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
              message ?? l10n.error,
              textAlign: TextAlign.center,
              style: text.bodyLarge?.copyWith(color: tokens.textSecondary),
            ),
            if (problemCode != null) ...[
              const SizedBox(height: AppSpacing.md),
              TextButton.icon(
                key: const Key('error.copyProblemCode'),
                onPressed: () => unawaited(
                  Clipboard.setData(ClipboardData(text: problemCode)).then((_) {
                    // Copying is silent on most phones: say it happened.
                    if (context.mounted) {
                      AppSnackbar.show(
                        context,
                        l10n.problemCodeCopied,
                        tone: AppSnackTone.success,
                      );
                    }
                  }),
                ),
                icon: const Icon(Icons.copy_rounded),
                label: Text(l10n.problemCodeCopy),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: retryLabel ?? l10n.retry,
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
