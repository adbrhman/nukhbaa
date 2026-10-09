library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_breakpoints.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../l10n/app_localizations.dart';
import 'admin_nav_counts.dart';
import 'admin_sections.dart';
import 'screens/sections/admin_analytics_section.dart';
import 'screens/sections/admin_home_section.dart';
import 'screens/sections/admin_predictions_section.dart';
import 'screens/sections/announcement_section.dart';
import 'screens/sections/admin_counted_fixtures_section.dart';
import 'screens/sections/audit_log_section.dart';
import 'screens/sections/champion_admin_section.dart';
import 'screens/sections/error_log_section.dart';
import 'screens/sections/admin_monthly_competitions_section.dart';
import 'screens/sections/fixtures_admin_section.dart';
import 'screens/sections/h2h_admin_section.dart';
import 'screens/sections/ledger_lookup_section.dart';
import 'screens/sections/referral_admin_section.dart';
import 'screens/sections/results_scoring_section.dart';
import 'screens/sections/user_names_section.dart';
import 'screens/sections/user_sanction_section.dart';

String adminSectionLabel(AdminSection section, AppLocalizations l10n) {
  return switch (section) {
    AdminSection.dashboard => l10n.adminDashboardTab,
    AdminSection.monthlyCompetitions => l10n.adminMonthlyCompetitionsTab,
    AdminSection.fixtures => 'المباريات',
    AdminSection.predictions => l10n.adminPredictionsTab,
    AdminSection.resultsScoring => l10n.adminResultsScoringTab,
    AdminSection.countedFixtures => l10n.adminCountedFixturesTab,
    AdminSection.users => l10n.adminUsersTab,
    AdminSection.userNames => 'أسماء المستخدمين',
    AdminSection.announcements => 'إرسال إشعار',
    AdminSection.ledger => 'سجل النقاط',
    AdminSection.analytics => 'التحليلات',
    AdminSection.audit => l10n.adminAuditLogTab,
    AdminSection.errorLog => 'سجل الأخطاء',
    AdminSection.referrals => 'نظام الدعوات',
    AdminSection.champions => 'الترتيب والأبطال',
    AdminSection.h2hLeague => 'دوري المواجهات',
  };
}

/// The menu: one entry per administrative domain, never per action (add,
/// edit, delete and hide are buttons inside "المباريات"). Only sections
/// that exist are listed; a domain with nothing built yet has no entry.
///
/// Ordered by the admin's day (2026-10-07): the home entry alone at the top
/// with no group title, then matches, competitions, players, the system.
/// No group holds a single entry.
const List<({String? title, List<AdminSection> sections})> _adminNavGroups = [
  (title: null, sections: [AdminSection.dashboard]),
  (
    title: 'المباريات والنتائج',
    sections: [
      AdminSection.fixtures,
      AdminSection.resultsScoring,
      AdminSection.countedFixtures,
    ],
  ),
  (
    title: 'المسابقات والترتيب',
    sections: [
      AdminSection.monthlyCompetitions,
      AdminSection.champions,
      AdminSection.h2hLeague,
      AdminSection.predictions,
    ],
  ),
  (
    title: 'اللاعبون والتواصل',
    sections: [
      AdminSection.users,
      AdminSection.userNames,
      AdminSection.referrals,
      AdminSection.ledger,
      AdminSection.announcements,
    ],
  ),
  (
    title: 'النظام',
    sections: [
      AdminSection.analytics,
      AdminSection.audit,
      AdminSection.errorLog,
    ],
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
    this.counts = const <AdminSection, int>{},
  });

  final AdminSection selected;
  final ValueChanged<AdminSection> onSelect;

  /// How many things wait in each section ([adminNavCountsProvider]);
  /// an entry with no count shows none.
  final Map<AdminSection, int> counts;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens t = context.tokens;

    return ListView(
      key: const Key('admin.shell.navList'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      children: [
        for (final group in _adminNavGroups) ...[
          if (group.title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              // 12px and no tracking: letter spacing pulls joined Arabic
              // letters apart (app_typography.dart, UI-38), and 11px was too
              // small to read (UI-37).
              child: Text(
                group.title!,
                style: context.text.labelMedium?.copyWith(
                  color: t.textSecondary,
                  fontWeight: FontWeight.w800,
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
                  color: section == selected ? t.primaryText : t.textPrimary,
                  fontWeight: section == selected
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
              selected: section == selected,
              selectedTileColor: t.primary.withValues(alpha: 0.08),
              trailing: (counts[section] ?? 0) > 0
                  ? Badge(
                      key: Key('admin.shell.nav.${section.name}.count'),
                      label: Text(
                        counts[section]! > 99 ? '99+' : '${counts[section]}',
                      ),
                    )
                  : null,
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

  Widget _bodyFor(AdminSection section) {
    return switch (section) {
      AdminSection.dashboard => AdminHomeSection(onNavigate: onSelect),
      AdminSection.monthlyCompetitions =>
        const AdminMonthlyCompetitionsSection(),
      AdminSection.audit => const AuditLogSection(),
      AdminSection.errorLog => const ErrorLogSection(),
      AdminSection.analytics => const AdminAnalyticsSection(),
      AdminSection.users => const UserSanctionSection(),
      AdminSection.userNames => const UserNamesSection(),
      AdminSection.announcements => const AnnouncementSection(),
      AdminSection.ledger => const LedgerLookupSection(),
      AdminSection.fixtures => const FixturesAdminSection(),
      AdminSection.resultsScoring => const ResultsScoringSection(),
      AdminSection.predictions => const AdminPredictionsSection(),
      AdminSection.countedFixtures => const AdminCountedFixturesSection(),
      AdminSection.referrals => const ReferralAdminSection(),
      AdminSection.champions => const ChampionAdminSection(),
      AdminSection.h2hLeague => const H2hAdminSection(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool isMobile = AppBreakpoints.isMobile(context);

    final Widget body = Padding(
      key: const Key('admin.shell.body'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: _bodyFor(selected),
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
            child: Consumer(
              builder: (context, ref, _) => AdminNavList(
                selected: selected,
                onSelect: onSelect,
                counts: ref.watch(adminNavCountsProvider),
              ),
            ),
          ),
        ),
        VerticalDivider(width: 1, color: t.border),
        Expanded(child: body),
      ],
    );
  }
}
