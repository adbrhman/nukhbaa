library;

import 'package:flutter/material.dart';

import '../../core/design/app_breakpoints.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../l10n/app_localizations.dart';
import 'admin_sections.dart';
import 'screens/sections/admin_coming_soon_section.dart';
import 'screens/sections/admin_dashboard_section.dart';
import 'screens/sections/audit_log_section.dart';
import 'screens/sections/fixture_schedule_section.dart';
import 'screens/sections/admin_monthly_competitions_section.dart';
import 'screens/sections/ledger_lookup_section.dart';
import 'screens/sections/results_scoring_section.dart';
import 'screens/sections/user_sanction_section.dart';

String adminSectionLabel(AdminSection section, AppLocalizations l10n) {
  return switch (section) {
    AdminSection.dashboard => l10n.adminDashboardTab,
    AdminSection.monthlyCompetitions => l10n.adminMonthlyCompetitionsTab,
    AdminSection.fixtures => l10n.adminFixturesTab,
    AdminSection.predictions => l10n.adminPredictionsTab,
    AdminSection.dailyDoubles => l10n.adminDailyDoublesTab,
    AdminSection.resultsScoring => l10n.adminResultsScoringTab,
    AdminSection.leaderboards => l10n.adminLeaderboardsTab,
    AdminSection.users => l10n.adminUsersTab,
    AdminSection.competitions => l10n.adminCompetitionsTab,
    AdminSection.teams => l10n.adminTeamsTab,
    AdminSection.social => l10n.adminSocialTab,
    AdminSection.notifications => l10n.adminNotificationsTab,
    AdminSection.reportsAnalytics => l10n.adminReportsAnalyticsTab,
    AdminSection.ledger => l10n.adminLedgerLookupTab,
    AdminSection.audit => l10n.adminAuditLogTab,
    AdminSection.systemHealth => l10n.adminSystemHealthTab,
    AdminSection.rolesPermissions => l10n.adminRolesPermissionsTab,
    AdminSection.settings => l10n.adminSettingsTab,
  };
}

const List<({String title, List<AdminSection> sections})> _adminNavGroups = [
  (title: 'نظرة عامة', sections: [AdminSection.dashboard]),
  (
    title: 'المسابقات والمباريات',
    sections: [
      AdminSection.monthlyCompetitions,
      AdminSection.competitions,
      AdminSection.fixtures,
      AdminSection.predictions,
      AdminSection.resultsScoring,
      AdminSection.dailyDoubles,
    ],
  ),
  (
    title: 'النقاط والترتيب',
    sections: [AdminSection.leaderboards, AdminSection.ledger],
  ),
  (
    title: 'المستخدمون والتفاعل',
    sections: [
      AdminSection.users,
      AdminSection.teams,
      AdminSection.social,
      AdminSection.notifications,
    ],
  ),
  (
    title: 'التحليلات والأمان',
    sections: [
      AdminSection.reportsAnalytics,
      AdminSection.audit,
      AdminSection.systemHealth,
    ],
  ),
  (
    title: 'الإدارة',
    sections: [AdminSection.rolesPermissions, AdminSection.settings],
  ),
];

/// قائمة التنقّل المشتركة بين الشريط الجانبي الدائم (سطح المكتب/اللوحي)
/// والـDrawer المنبثق (الجوال). لا تملك Scaffold أو حالة خاصة بها —
/// [selected]/[onSelect] يُمرَّران من المالك (AdminHubScreen أو AdminShell).
class AdminNavList extends StatelessWidget {
  const AdminNavList({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final AdminSection selected;
  final ValueChanged<AdminSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens t = context.tokens;

    return ListView(
      key: const Key('admin.shell.navList'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      children: [
        for (final group in _adminNavGroups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Text(
              group.title,
              style: context.text.labelSmall?.copyWith(
                color: t.textMuted,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ),
          for (final AdminSection section in group.sections)
            ListTile(
              key: Key('admin.shell.nav.${section.name}'),
              leading: Icon(
                section.icon,
                color: section == selected ? t.primary : t.textSecondary,
              ),
              title: Text(
                adminSectionLabel(section, l10n),
                style: context.text.bodyMedium?.copyWith(
                  color: section == selected ? t.primary : t.textPrimary,
                  fontWeight: section == selected
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
              selected: section == selected,
              selectedTileColor: t.primary.withValues(alpha: 0.08),
              onTap: () => onSelect(section),
            ),
        ],
      ],
    );
  }
}

/// جسم لوحة الأدمن حسب القسم المختار. على سطح المكتب/اللوحي يعرض شريطاً
/// جانبياً دائماً بجانب المحتوى؛ على الجوال يعرض المحتوى فقط — التنقّل
/// عبر Drawer يديره [AdminHubScreen] (المالك الوحيد لحالة `selected`).
class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.selected, required this.onSelect});

  final AdminSection selected;
  final ValueChanged<AdminSection> onSelect;

  Widget _bodyFor(AdminSection section, AppLocalizations l10n) {
    return switch (section) {
      AdminSection.dashboard => AdminDashboardSection(onNavigate: onSelect),
      AdminSection.monthlyCompetitions =>
        const AdminMonthlyCompetitionsSection(),
      AdminSection.audit => const AuditLogSection(),
      AdminSection.users => const UserSanctionSection(),
      AdminSection.ledger => const LedgerLookupSection(),
      AdminSection.fixtures => const FixtureScheduleSection(),
      AdminSection.resultsScoring => const ResultsScoringSection(),
      _ => AdminComingSoonSection(title: adminSectionLabel(section, l10n)),
    };
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens t = context.tokens;
    final bool isMobile = AppBreakpoints.isMobile(context);

    final Widget body = Padding(
      key: const Key('admin.shell.body'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: _bodyFor(selected, l10n),
    );

    if (isMobile) return body;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          key: const Key('admin.shell.sidebar'),
          width: 240,
          child: Material(
            color: t.surface,
            child: AdminNavList(selected: selected, onSelect: onSelect),
          ),
        ),
        VerticalDivider(width: 1, color: t.border),
        Expanded(child: body),
      ],
    );
  }
}
