library;

import 'package:flutter/material.dart';
import '../design/app_motion.dart';
import '../design/app_radius.dart';
import '../design/app_spacing.dart';
import '../design/app_tokens.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.color,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final Color bg = color ?? tokens.surface;

    return Material(
      color: bg,
      borderRadius: AppRadius.brXl,
      child: InkWell(
        borderRadius: AppRadius.brXl,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.emphasizedOut,
          padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: AppRadius.brXl,
            border: Border.all(color: tokens.border),
          ),
          child: child,
        ),
      ),
    );
  }
}
