library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../design/app_sizes.dart';
import '../design/app_spacing.dart';
import '../design/app_tokens.dart';

class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.validator,
    this.keyboardType,
    this.obscure = false,
    this.enabled = true,
    this.prefixIcon,
    this.textInputAction,
    this.onFieldSubmitted,
    this.inputFormatters,
    this.autofillHints,
    this.fieldKey,
  });

  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final bool obscure;
  final bool enabled;
  final IconData? prefixIcon;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final Key? fieldKey;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _obscured = widget.obscure;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final TextTheme text = context.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: text.labelMedium?.copyWith(color: tokens.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        TextFormField(
          key: widget.fieldKey,
          controller: widget.controller,
          validator: widget.validator,
          keyboardType: widget.keyboardType,
          obscureText: _obscured,
          enabled: widget.enabled,
          textInputAction: widget.textInputAction,
          onFieldSubmitted: widget.onFieldSubmitted,
          inputFormatters: widget.inputFormatters,
          autofillHints: widget.autofillHints,
          style: text.bodyLarge?.copyWith(color: tokens.textPrimary),
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: widget.prefixIcon != null
                ? Icon(
                    widget.prefixIcon,
                    color: tokens.textMuted,
                    size: AppSizes.iconMd,
                  )
                : null,
            suffixIcon: widget.obscure
                ? IconButton(
                    tooltip: _obscured ? 'Show password' : 'Hide password',
                    icon: Icon(
                      _obscured
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: tokens.textMuted,
                      size: AppSizes.iconMd,
                    ),
                    onPressed: () => setState(() => _obscured = !_obscured),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}
