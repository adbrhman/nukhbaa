library;

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../widgets/admin_ui_kit.dart';

/// عرض نائب لأي قسم أدمن لم يُنفَّذ بعد ضمن خطة الهيكل الكامل (قسم 9).
/// لا منطق عمل هنا؛ يُستبدل بالقسم الفعلي في دفعة مستقلة عند تنفيذه.
class AdminComingSoonSection extends StatelessWidget {
  const AdminComingSoonSection({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminSectionHeader(title: title),
        AdminEmptyState(
          icon: Icons.construction_rounded,
          title: l10n.adminSectionComingSoon,
        ),
      ],
    );
  }
}
