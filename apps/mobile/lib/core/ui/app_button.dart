library;

import 'package:flutter/material.dart';
import '../design/app_radius.dart';
import '../design/app_sizes.dart';
import '../design/app_spacing.dart';
import '../design/app_tokens.dart';

enum AppButtonVariant { primary, secondary, danger, text }

enum AppButtonSize { small, medium, large }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.large,
    this.icon,
    this.loading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? icon;
  final bool loading;
  final bool expand;

  double get _height => switch (size) {
    AppButtonSize.small => AppSizes.controlSm,
    AppButtonSize.medium => AppSizes.controlMd,
    AppButtonSize.large => AppSizes.controlLg,
  };

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;
    final bool disabled = loading || onPressed == null;

    final (Color bg, Color fg, Color? border) = switch (variant) {
      AppButtonVariant.primary => (tokens.primary, tokens.onPrimary, null),
      AppButtonVariant.danger => (tokens.error, tokens.onPrimary, null),
      AppButtonVariant.secondary => (
        Colors.transparent,
        tokens.textPrimary,
        tokens.border,
      ),
      AppButtonVariant.text => (Colors.transparent, tokens.primary, null),
    };

    final Widget child = loading
        ? SizedBox(
            height: AppSizes.progressSm,
            width: AppSizes.progressSm,
            child: CircularProgressIndicator(
              strokeWidth: AppSizes.progressStroke,
              color: fg,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: AppSizes.iconSm, color: fg),
                const SizedBox(width: AppSpacing.sm),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelLarge?.copyWith(color: fg),
                ),
              ),
            ],
          );

    return Semantics(
      button: true,
      enabled: !disabled,
      label: label,
      child: Opacity(
        opacity: disabled && !loading ? 0.5 : 1,
        child: Material(
          color: bg,
          borderRadius: AppRadius.brMd,
          child: InkWell(
            borderRadius: AppRadius.brMd,
            onTap: disabled ? null : onPressed,
            child: Container(
              height: _height,
              width: expand ? double.infinity : null,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              decoration: BoxDecoration(
                borderRadius: AppRadius.brMd,
                border: border != null ? Border.all(color: border) : null,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
