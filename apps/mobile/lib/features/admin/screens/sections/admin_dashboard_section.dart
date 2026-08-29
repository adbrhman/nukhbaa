library;

import 'package:flutter/material.dart';

import '../../../../core/design/app_spacing.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../widgets/admin_ui_kit.dart';

/// قسم "الرئيسية" في لوحة الأدمن. منقول حرفياً من `_AdminKpiRow` القديمة
/// في `AdminHubScreen` (القيم 0 مؤقتاً حتى تُربط بمزوّدات فعلية) —
/// بلا تعديل منطقي، فقط تغيير الموضع ليكون قسماً ضمن الشريط الجانبي.
class AdminDashboardSection extends StatelessWidget {
  const AdminDashboardSection({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminSectionHeader(title: l10n.adminDashboardTab),
        const _AdminKpiRow(),
      ],
    );
  }
}

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
