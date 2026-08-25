library;

import 'package:flutter/material.dart';

import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../l10n/app_localizations.dart';
import 'admin_shell.dart';

/// نقطة الدخول العليا للوحة الأدمن. تعرض شريط عنوان وصفاً من عدّادات KPI
/// (قيمها 0 مؤقتاً حتى تُربط بمزوّدات فعلية)، ثم [AdminShell] كجسم يتولى
/// التنقّل المتجاوب بين الأقسام الستة.
class AdminHubScreen extends StatelessWidget {
  const AdminHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens t = context.tokens;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(title: Text(l10n.adminDashboard)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: const _AdminKpiRow(),
          ),
          const Expanded(child: AdminShell()),
        ],
      ),
    );
  }
}

/// صف عدّادات موجزة أعلى اللوحة. القيم 0 مؤقتاً حسب توصيف الجزء 3؛
/// تُربط لاحقاً بمزوّدات Riverpod فعلية عند توفرها.
class _AdminKpiRow extends StatelessWidget {
  const _AdminKpiRow();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens t = context.tokens;

    final List<(IconData, String, int)> kpis = <(IconData, String, int)>[
      (Icons.people_alt_rounded, l10n.adminUsersTab, 0),
      (Icons.receipt_long_rounded, l10n.adminAuditLogTab, 0),
    ];

    return Row(
      children: [
        for (final (IconData icon, String label, int value) in kpis) ...[
          Expanded(
            child: Container(
              key: const Key('admin.hub.kpi'),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: t.primary, size: 20),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '$value',
                    style: context.text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: t.textPrimary,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelSmall?.copyWith(
                      color: t.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (kpis.last != (icon, label, value))
            const SizedBox(width: AppSpacing.sm),
        ],
      ],
    );
  }
}
