/// "كيف تلعب؟" for signed-in users: the scoring rules, including how a
/// knockout match that goes to extra time or penalties is settled (the UEFA
/// Predict Six rule, adopted 2026-09-17).
library;

import 'package:flutter/material.dart';

import '../../core/design/app_radius.dart';
import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../l10n/app_localizations.dart';

/// The rules page.
class RulesScreen extends StatelessWidget {
  /// Creates the page.
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        centerTitle: true,
        title: Text(l10n.rulesTitle, key: const Key('rules.title')),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.maxAccountWidth,
            ),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: <Widget>[
                Text(
                  l10n.rulesTagline,
                  textAlign: TextAlign.center,
                  style: context.text.bodyMedium?.copyWith(
                    color: tokens.textMuted,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _RulesCard(
                  children: <Widget>[
                    _RuleRow(
                      icon: Icons.sports_soccer_rounded,
                      color: tokens.textSecondary,
                      label: l10n.rulesPredictMajorLeagues,
                    ),
                    _RuleRow(
                      icon: Icons.check_circle_rounded,
                      color: tokens.primary,
                      label: l10n.rulesCorrectPrediction,
                    ),
                    _RuleRow(
                      icon: Icons.cancel_rounded,
                      color: tokens.textMuted,
                      label: l10n.rulesWrongPrediction,
                    ),
                    _RuleRow(
                      icon: Icons.star_rounded,
                      color: tokens.gold,
                      label: l10n.rulesDoubleMatch,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _RulesCard(
                  children: <Widget>[
                    _RuleRow(
                      icon: Icons.timer_outlined,
                      color: tokens.textSecondary,
                      label: l10n.rulesRegularTime,
                    ),
                    _RuleRow(
                      key: const Key('rules.knockout'),
                      icon: Icons.sports_score_rounded,
                      color: tokens.primary,
                      label: l10n.rulesKnockout,
                      detail: l10n.rulesKnockoutExample,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RulesCard extends StatelessWidget {
  const _RulesCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int index = 0; index < children.length; index++) ...<Widget>[
            if (index > 0) const SizedBox(height: AppSpacing.md),
            children[index],
          ],
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.icon,
    required this.color,
    required this.label,
    this.detail,
    super.key,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = context.tokens;
    final String? extra = detail;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: AppSizes.iconMd, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: context.text.bodyMedium?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (extra != null) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  extra,
                  style: context.text.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
