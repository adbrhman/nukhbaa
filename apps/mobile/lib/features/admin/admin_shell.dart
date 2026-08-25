library;

import 'package:flutter/material.dart';

import '../../core/design/app_breakpoints.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../l10n/app_localizations.dart';
import 'admin_sections.dart';
import 'screens/sections/audit_log_section.dart';
import 'screens/sections/fixture_schedule_section.dart';
import 'screens/sections/ledger_lookup_section.dart';
import 'screens/sections/results_scoring_section.dart';
import 'screens/sections/user_sanction_section.dart';

/// الغلاف المتجاوب للوحة الأدمن: يعرض قسماً واحداً من [AdminSection] في كل
/// مرة، مع تنقّل عبر NavigationRail على الأجهزة اللوحية والمكتبية،
/// و NavigationBar سفلي على الجوال. لا يحمل أي حالة عمل خاصة به؛ كل قسم
/// يدير حالته الخاصة عبر Riverpod.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  AdminSection _selected = AdminSection.audit;

  String _labelFor(AdminSection section, AppLocalizations l10n) {
    return switch (section) {
      AdminSection.audit => l10n.adminAuditLogTab,
      AdminSection.users => l10n.adminUsersTab,
      AdminSection.ledger => l10n.adminLedgerLookupTab,
      AdminSection.fixtures => l10n.adminFixturesTab,
      AdminSection.resultsScoring => l10n.adminResultsScoringTab,
    };
  }

  Widget _bodyFor(AdminSection section) {
    return switch (section) {
      AdminSection.audit => const AuditLogSection(),
      AdminSection.users => const UserSanctionSection(),
      AdminSection.ledger => const LedgerLookupSection(),
      AdminSection.fixtures => const FixtureScheduleSection(),
      AdminSection.resultsScoring => const ResultsScoringSection(),
    };
  }

  void _select(AdminSection section) {
    if (section == _selected) return;
    setState(() => _selected = section);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens t = context.tokens;
    final bool isMobile = AppBreakpoints.isMobile(context);

    final Widget body = Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: _bodyFor(_selected),
    );

    if (isMobile) {
      return Scaffold(
        backgroundColor: t.background,
        body: SafeArea(child: body),
        bottomNavigationBar: NavigationBar(
          key: const Key('admin.shell.bottomNav'),
          selectedIndex: AdminSection.values.indexOf(_selected),
          onDestinationSelected: (int index) =>
              _select(AdminSection.values[index]),
          destinations: [
            for (final AdminSection section in AdminSection.values)
              NavigationDestination(
                icon: Icon(section.icon),
                label: _labelFor(section, l10n),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NavigationRail(
              key: const Key('admin.shell.rail'),
              selectedIndex: AdminSection.values.indexOf(_selected),
              onDestinationSelected: (int index) =>
                  _select(AdminSection.values[index]),
              labelType: NavigationRailLabelType.all,
              backgroundColor: t.surface,
              destinations: [
                for (final AdminSection section in AdminSection.values)
                  NavigationRailDestination(
                    icon: Icon(section.icon),
                    label: Text(_labelFor(section, l10n)),
                  ),
              ],
            ),
            VerticalDivider(width: 1, color: t.border),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}
