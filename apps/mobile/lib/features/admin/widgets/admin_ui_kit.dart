library;

import 'package:flutter/material.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';

class AdminSectionHeader extends StatelessWidget {
  const AdminSectionHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: context.text.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle!,
              style: context.text.bodySmall?.copyWith(color: t.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class AdminCard extends StatelessWidget {
  const AdminCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
        boxShadow: t.shadowSm,
      ),
      child: child,
    );
  }
}

class AdminTextField extends StatelessWidget {
  const AdminTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.prefixIcon,
    this.keyboardType,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String hint;
  final IconData? prefixIcon;
  final TextInputType? keyboardType;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      enabled: enabled,
      style: context.text.bodyMedium?.copyWith(color: t.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: prefixIcon == null
            ? null
            : Icon(prefixIcon, color: t.textSecondary, size: 20),
        filled: true,
        fillColor: t.surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.primary, width: 1.5),
        ),
      ),
    );
  }
}

class AdminPrimaryButton extends StatelessWidget {
  const AdminPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.loading = false,
    required this.onPressed,
  });

  final String label;
  final IconData? icon;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: t.primary,
        foregroundColor: t.onPrimary,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onPressed,
      child: loading
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: t.onPrimary),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Text(label),
              ],
            ),
    );
  }
}

class AdminSecondaryButton extends StatelessWidget {
  const AdminSecondaryButton({
    super.key,
    required this.label,
    this.icon,
    this.loading = false,
    required this.onPressed,
  });

  final String label;
  final IconData? icon;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.primary,
        side: BorderSide(color: t.primary.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onPressed,
      child: loading
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: t.primary),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Text(label),
              ],
            ),
    );
  }
}

class AdminErrorBanner extends StatelessWidget {
  const AdminErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: t.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: t.error, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(message, style: context.text.bodySmall?.copyWith(color: t.error)),
          ),
        ],
      ),
    );
  }
}

class AdminSuccessBanner extends StatelessWidget {
  const AdminSuccessBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: t.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline_rounded, color: t.primary, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(message, style: context.text.bodySmall?.copyWith(color: t.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class AdminEmptyState extends StatelessWidget {
  const AdminEmptyState({super.key, required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: [
          Icon(icon, size: 32, color: t.textMuted),
          const SizedBox(height: AppSpacing.sm),
          Text(title, style: context.text.bodyMedium?.copyWith(color: t.textMuted)),
        ],
      ),
    );
  }
}

class AdminListRow extends StatelessWidget {
  const AdminListRow({
    super.key,
    required this.leadingIcon,
    required this.leadingColor,
    required this.title,
    this.trailing,
  });

  final IconData leadingIcon;
  final Color leadingColor;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(leadingIcon, color: leadingColor, size: 20),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodyMedium?.copyWith(color: t.textPrimary),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}
