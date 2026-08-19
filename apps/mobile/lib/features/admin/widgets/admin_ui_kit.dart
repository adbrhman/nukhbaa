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
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: t.onPrimary,
              ),
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
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: t.primary,
              ),
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
  const AdminErrorBanner({super.key, required this.message, this.debugDetail});

  final String message;

  /// TEMP DIAGNOSTIC — remove once the transient-error root cause behind
  /// "We could not reach the server" is confirmed and fixed at its source.
  /// Renders [AppError.kind]/[AppError.code] beneath [message] so a real
  /// network failure (api_client.network_unreachable/timeout) can be told
  /// apart from a decoded server-side transient (e.g. scoring.*), which
  /// ErrorPresenter otherwise collapses into the same sentence. Never
  /// includes the bearer token or any response body.
  final String? debugDetail;

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: context.text.bodySmall?.copyWith(color: t.error),
                ),
                if (debugDetail != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    debugDetail!,
                    style: context.text.labelSmall?.copyWith(
                      color: t.textMuted,
                    ),
                  ),
                ],
              ],
            ),
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
            child: Text(
              message,
              style: context.text.bodySmall?.copyWith(color: t.textPrimary),
            ),
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
          Text(
            title,
            style: context.text.bodyMedium?.copyWith(color: t.textMuted),
          ),
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
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

/// زر موحّد لاختيار تاريخ ووقت (يفتح showDatePicker ثم showTimePicker)،
/// ويعرض القيمة المنسّقة أو نص بديل قبل الاختيار.
class AdminDateTimeField extends StatelessWidget {
  const AdminDateTimeField({
    super.key,
    required this.value,
    required this.onChanged,
    required this.placeholder,
    this.enabled = true,
    this.icon = Icons.event_outlined,
  });

  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final String placeholder;
  final bool enabled;
  final IconData icon;

  static String format(DateTime local) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _pick(BuildContext context) async {
    final DateTime now = DateTime.now();
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: value ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (date == null || !context.mounted) return;
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: value == null
          ? TimeOfDay.fromDateTime(now)
          : TimeOfDay.fromDateTime(value!),
    );
    if (time == null) return;
    onChanged(
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminSecondaryButton(
      label: value == null ? placeholder : format(value!),
      icon: icon,
      onPressed: enabled ? () => _pick(context) : null,
    );
  }
}
