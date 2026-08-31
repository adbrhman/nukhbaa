library;

import 'package:flutter/material.dart';

import '../../core/design/app_breakpoints.dart';
import '../../core/design/app_tokens.dart';
import '../../l10n/app_localizations.dart';
import 'admin_sections.dart';
import 'admin_shell.dart';

/// نقطة الدخول العليا للوحة الأدمن. تملك القسم المختار [_selected] وتمرّره
/// إلى [AdminShell] (الجسم دائماً) و[AdminNavList] (داخل Drawer على الجوال
/// فقط — إضافة `drawer:` لـScaffold تُظهر أيقونة القائمة تلقائياً في AppBar).
class AdminHubScreen extends StatefulWidget {
  const AdminHubScreen({super.key});

  @override
  State<AdminHubScreen> createState() => _AdminHubScreenState();
}

class _AdminHubScreenState extends State<AdminHubScreen> {
  AdminSection _selected = AdminSection.dashboard;

  void _select(AdminSection section) {
    if (section == _selected) return;
    setState(() => _selected = section);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens t = context.tokens;
    final bool isMobile = AppBreakpoints.isMobile(context);

    return Scaffold(
      key: const Key('admin.hub.scaffold'),
      backgroundColor: t.background,
      appBar: AppBar(title: Text(adminSectionLabel(_selected, l10n))),
      drawer: isMobile
          ? Drawer(
              key: const Key('admin.hub.drawer'),
              child: SafeArea(
                // Builder يوفّر سياقاً أسفل الـDrawer/Scaffold كي يعمل
                // Navigator.pop هنا على إغلاق الـDrawer نفسه فقط، لا الشاشة.
                child: Builder(
                  builder: (BuildContext drawerContext) => AdminNavList(
                    selected: _selected,
                    onSelect: (AdminSection section) {
                      _select(section);
                      Navigator.of(drawerContext).pop();
                    },
                  ),
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: AdminShell(selected: _selected, onSelect: _select),
      ),
    );
  }
}
