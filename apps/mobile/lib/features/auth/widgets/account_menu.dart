/// The grouped-list building blocks of the account tab and its settings
/// page: a rounded card holding rows separated by hairlines, each row an
/// icon, a title with an optional subtitle, and a forward chevron.
library;

import 'package:flutter/material.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_sizes.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/ui/forward_chevron.dart';

/// A rounded surface card stacking [children] with dividers between them.
class AccountMenuCard extends StatelessWidget {
  /// Creates the card.
  const AccountMenuCard({required this.children, super.key});

  /// The rows, top to bottom.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return Material(
      color: tokens.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.brLg,
        side: BorderSide(color: tokens.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int index = 0; index < children.length; index++) ...<Widget>[
            if (index > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: AppSpacing.lg,
                endIndent: AppSpacing.lg,
                color: tokens.border,
              ),
            children[index],
          ],
        ],
      ),
    );
  }
}

/// One tappable row: icon, title, optional subtitle, optional [trailing]
/// widget before the chevron.
class AccountMenuRow extends StatelessWidget {
  /// Creates the row.
  const AccountMenuRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final String? sub = subtitle;
    final Widget? tail = trailing;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, color: tokens.primary, size: AppSizes.iconLg),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    style: context.text.bodyLarge?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (sub != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: context.text.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (tail != null) ...<Widget>[
              tail,
              const SizedBox(width: AppSpacing.sm),
            ],
            ForwardChevron(color: tokens.textMuted),
          ],
        ),
      ),
    );
  }
}

/// A small caption above a group of cards.
class AccountSectionTitle extends StatelessWidget {
  /// Creates the caption.
  const AccountSectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(
        right: AppSpacing.xs,
        left: AppSpacing.xs,
        bottom: AppSpacing.sm,
      ),
      child: Text(
        title,
        style: context.text.titleSmall?.copyWith(
          color: tokens.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
