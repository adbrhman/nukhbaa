library;

import 'package:flutter/material.dart';
import '../design/app_sizes.dart';
import '../design/app_spacing.dart';
import '../design/app_tokens.dart';
import 'app_button.dart';

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;

    return AppStateFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AppSizes.iconStateLg, color: tokens.textMuted),
            const SizedBox(height: AppSpacing.xl),
          ],
          Text(
            title,
            textAlign: TextAlign.center,
            style: text.titleLarge?.copyWith(color: tokens.textPrimary),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: tokens.textSecondary),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: actionLabel!,
              onPressed: onAction,
              expand: false,
              size: AppButtonSize.medium,
            ),
          ],
        ],
      ),
    );
  }
}

/// Centres a state's content in the space it is given, and scrolls when the
/// content is taller than that space -- at large text sizes, or a phone held
/// in landscape -- instead of overflowing (UI-30). Shared by
/// [AppEmptyState] and the error state.
class AppStateFrame extends StatelessWidget {
  const AppStateFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.hasBoundedHeight
                  ? constraints.maxHeight
                  : 0,
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.x3l),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
