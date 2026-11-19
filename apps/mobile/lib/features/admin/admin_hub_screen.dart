library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_breakpoints.dart';
import '../../core/design/app_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../auth/session_controller.dart';
import 'admin_nav_counts.dart';
import 'admin_sections.dart';
import 'admin_shell.dart';
import 'screens/sections/hidden_accounts_section.dart';

/// نقطة الدخول العليا للوحة الأدمن. تملك القسم المختار [_selected] وتمرّره
/// إلى [AdminShell] (الجسم دائماً) و[AdminNavList] (داخل Drawer على الجوال
/// فقط — إضافة `drawer:` لـScaffold تُظهر أيقونة القائمة تلقائياً في AppBar).
class AdminHubScreen extends ConsumerStatefulWidget {
  const AdminHubScreen({super.key, this.initialSection});

  /// The section opened first; the home page when null (a push about the
  /// support inbox opens «رسائل الدعم», script 167). An owner seat's home
  /// page is «الإدارة العامة للمالك» (script 288).
  final AdminSection? initialSection;

  @override
  ConsumerState<AdminHubScreen> createState() => _AdminHubScreenState();
}

class _AdminHubScreenState extends ConsumerState<AdminHubScreen> {
  // NK288_08
  /// Where the panel opens and where back returns: the owners' page for an
  /// owner seat ([owner]), the home page for anyone else.
  static AdminSection _home(bool owner) =>
      owner ? AdminSection.owner : AdminSection.dashboard;

  late AdminSection _selected =
      widget.initialSection ??
      _home(isOwnerAdminSession(ref.read(sessionControllerProvider).value));

  void _select(AdminSection section) {
    if (section == _selected) return;
    setState(() => _selected = section);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens t = context.tokens;
    final bool isMobile = AppBreakpoints.isMobile(context);
    final bool owner = isOwnerAdminSession(
      ref.watch(sessionControllerProvider).value,
    );
    final AdminSection home = _home(owner);

    // script 124: back from a section opens the home page; only from the
    // home page does it leave the panel.
    return PopScope<Object?>(
      canPop: _selected == home,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) _select(home);
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
                        owner: owner,
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
