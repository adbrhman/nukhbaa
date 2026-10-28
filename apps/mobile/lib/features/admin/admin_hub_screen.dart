library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_breakpoints.dart';
import '../../core/design/app_tokens.dart';
import '../../l10n/app_localizations.dart';
import 'admin_nav_counts.dart';
import 'admin_sections.dart';
import 'admin_shell.dart';

/// نقطة الدخول العليا للوحة الأدمن. تملك القسم المختار [_selected] وتمرّره
/// إلى [AdminShell] (الجسم دائماً) و[AdminNavList] (داخل Drawer على الجوال
/// فقط — إضافة `drawer:` لـScaffold تُظهر أيقونة القائمة تلقائياً في AppBar).
class AdminHubScreen extends StatefulWidget {
  const AdminHubScreen({super.key, this.initialSection});

  /// The section opened first; the home page when null (a push about the
  /// support inbox opens «رسائل الدعم», script 167).
  final AdminSection? initialSection;

  @override
  State<AdminHubScreen> createState() => _AdminHubScreenState();
}

class _AdminHubScreenState extends State<AdminHubScreen> {
  late AdminSection _selected = widget.initialSection ?? AdminSection.dashboard;

  void _select(AdminSection section) {
    if (section == _selected) return;
    setState(() => _selected = section);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens t = context.tokens;
    final bool isMobile = AppBreakpoints.isMobile(context);

    // script 124: back from a section opens the home page; only from the
    // home page does it leave the panel.
    return PopScope<Object?>(
      canPop: _selected == AdminSection.dashboard,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) _select(AdminSection.dashboard);
      },
      child: Scaffold(
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
                    builder: (BuildContext drawerContext) => Consumer(
                      builder: (context, ref, _) => AdminNavList(
                        counts: ref.watch(adminNavCountsProvider),
                        selected: _selected,
                        onSelect: (AdminSection section) {
                          _select(section);
                          Navigator.of(drawerContext).pop();
                        },
                      ),
                    ),
                  ),
                ),
              )
            : null,
        body: SafeArea(
          child: AdminShell(selected: _selected, onSelect: _select),
        ),
      ),
    );
  }
}
