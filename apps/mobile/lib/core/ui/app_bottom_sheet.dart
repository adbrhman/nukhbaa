library;

import 'package:flutter/material.dart';
import '../design/app_breakpoints.dart';
import '../design/app_spacing.dart';
import '../design/app_tokens.dart';

abstract final class AppBottomSheet {
  static const double contentMax = AppBreakpoints.tablet;

  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    String? title,
    bool isScrollControlled = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      constraints: const BoxConstraints(maxWidth: contentMax),
      builder: (context) {
        final AppTokens tokens = context.tokens;
        final TextTheme text = context.text;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: AppSpacing.xxl,
              right: AppSpacing.xxl,
              top: AppSpacing.sm,
              bottom: AppSpacing.xxl + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null) ...[
                  Text(
                    title,
                    style: text.headlineSmall?.copyWith(
                      color: tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                Builder(builder: builder),
              ],
            ),
          ),
        );
      },
    );
  }
}
