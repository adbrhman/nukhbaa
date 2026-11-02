/// "كيف تلعب؟" for signed-in users: the scoring rules, including how a
/// knockout match that goes to extra time or penalties is settled (the UEFA
/// Predict Six rule, adopted 2026-09-17). Only the exact score earns points
/// (3, or 6 on the day's one double); the right outcome alone earns 0, and
/// the page says so in those words (audit M-07).
///
/// With [RulesScreen.onAccept] it is the terms page a new account reads
/// once before the app opens (asked by the backup admin, 2026-11-02): the
/// competition for the prizes, without naming them, the conditions of
/// taking part, then the same rules, and an acceptance button.
library;

import 'package:flutter/material.dart';

import '../../core/analytics/screen_views.dart';
import '../../core/design/app_radius.dart';
import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../l10n/app_localizations.dart';

/// The rules page.
class RulesScreen extends StatelessWidget implements NamedScreen {
  @override
  String get screenName => ScreenNames.rules;

  /// Creates the page; with [onAccept], the terms page of a new account.
  const RulesScreen({super.key, this.onAccept});

  /// Called when a new account accepts the terms; null on the rules page
  /// opened from the settings.
  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens tokens = context.tokens;
    final VoidCallback? accept = onAccept;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        centerTitle: true,
        automaticallyImplyLeading: accept == null,
        title: Text(
          accept == null ? l10n.rulesTitle : 'الشروط والجوائز',
          key: const Key('rules.title'),
        ),
      ),
      bottomNavigationBar: accept == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: FilledButton(
                  key: const Key('rules.accept'),
                  onPressed: accept,
                  child: const Text('قرأت الشروط وأوافق'),
                ),
              ),
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
                  accept == null
                      ? l10n.rulesTagline
                      : 'توقّع، نافس، تصدّر النخبة '
                            'للمنافسة على الجوائز',
                  key: const Key('rules.tagline'),
                  textAlign: TextAlign.center,
                  style: context.text.bodyMedium?.copyWith(
                    color: tokens.textMuted,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (accept != null) ...<Widget>[
                  _RulesCard(
                    children: <Widget>[
                      _RuleRow(
                        key: const Key('rules.terms.champion'),
                        icon: Icons.emoji_events_rounded,
                        color: tokens.goldAccent,
                        label:
                            'صاحب المركز الأول في ترتيب الشهر '
                            'يُتوَّج بطلاً للشهر',
                      ),
                      _RuleRow(
                        key: const Key('rules.terms.name'),
                        icon: Icons.badge_outlined,
                        color: tokens.primary,
                        label:
                            'اسمك ثنائي، يظهر للاعبين في الترتيب، '
                            'ولا تستطيع تغييره بعد الحفظ',
                      ),
                      _RuleRow(
                        key: const Key('rules.terms.phone'),
                        icon: Icons.phone_android_rounded,
                        color: tokens.textSecondary,
                        label:
                            'حسابان من الهاتف نفسه لا '
                            'يتوقعان المباراة نفسها',
                      ),
                      _RuleRow(
                        key: const Key('rules.terms.suspended'),
                        icon: Icons.block_rounded,
                        color: tokens.textSecondary,
                        label:
                            'الحساب الموقوف لا ينال '
                            'نقاطاً ولا جوائز',
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
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
                      color: tokens.goldAccent,
                      label: l10n.rulesDoubleMatch,
                    ),
                    _RuleRow(
                      key: const Key('rules.soloExact'),
                      icon: Icons.workspace_premium_rounded,
                      color: tokens.goldAccent,
                      label: l10n.rulesSoloExact,
                    ),
                    _RuleRow(
                      key: const Key('rules.oneDouble'),
                      icon: Icons.today_rounded,
                      color: tokens.goldAccent,
                      label: l10n.rulesOneDoublePerDay,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _RulesCard(
                  children: <Widget>[
                    _RuleRow(
                      key: const Key('rules.lock'),
                      icon: Icons.lock_outline_rounded,
                      color: tokens.textSecondary,
                      label: l10n.rulesLockAtKickoff,
                    ),
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
                const SizedBox(height: AppSpacing.lg),
                _RulesCard(
                  children: <Widget>[
                    _RuleRow(
                      key: const Key('rules.month'),
                      icon: Icons.calendar_month_rounded,
                      color: tokens.primary,
                      label: l10n.rulesMonthStartsAtZero,
                    ),
                    _RuleRow(
                      key: const Key('rules.tieBreak'),
                      icon: Icons.format_list_numbered_rounded,
                      color: tokens.goldAccent,
                      label:
                          'عند تساوي النقاط يتقدم صاحب التوقعات الدقيقة '
                          'الأكثر، ثم صاحب الاتجاهات الصحيحة الأكثر، ثم '
                          'الأسبق انضماماً إلى مسابقة الشهر. لكل لاعب مركزه.',
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
