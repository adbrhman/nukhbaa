library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_breakpoints.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../auth/session_controller.dart';
import 'admin_nav_counts.dart';
import 'admin_sections.dart';
import 'screens/sections/admin_analytics_section.dart';
import 'screens/sections/admin_home_section.dart';
import 'screens/sections/admin_predictions_section.dart';
import 'screens/sections/announcement_section.dart';
import 'screens/sections/admin_counted_fixtures_section.dart';
import 'screens/sections/audit_log_section.dart';
import 'screens/sections/champion_admin_section.dart';
import 'screens/sections/cup_champions_admin_section.dart';
import 'screens/sections/error_log_section.dart';
import 'screens/sections/admin_monthly_competitions_section.dart';
import 'screens/sections/admin_support_section.dart';
import 'screens/sections/fixtures_admin_section.dart';
import 'screens/sections/club_crests_section.dart';
import 'screens/sections/hidden_accounts_section.dart';
import 'screens/sections/h2h_admin_section.dart';
import 'screens/sections/ledger_lookup_section.dart';
import 'screens/sections/new_players_section.dart';
import 'screens/sections/person_links_section.dart';
import 'screens/sections/results_scoring_section.dart';
import 'screens/sections/shared_devices_section.dart';
import 'screens/sections/user_names_section.dart';
import 'screens/sections/user_sanction_section.dart';

String adminSectionLabel(AdminSection section, AppLocalizations l10n) {
  return switch (section) {
    AdminSection.dashboard => l10n.adminDashboardTab,
    AdminSection.monthlyCompetitions => l10n.adminMonthlyCompetitionsTab,
    AdminSection.fixtures => 'المباريات',
    AdminSection.predictions => l10n.adminPredictionsTab,
    AdminSection.resultsScoring => l10n.adminResultsScoringTab,
    AdminSection.users => l10n.adminUsersTab,
    AdminSection.announcements => 'إرسال إشعار',
    AdminSection.support => 'رسائل الدعم',
    AdminSection.ledger => 'سجل النقاط',
    AdminSection.analytics => 'التحليلات',
    AdminSection.audit => l10n.adminAuditLogTab,
    AdminSection.errorLog => 'سجل الأخطاء',
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
  // script 124: fourteen entries. The calls sit with the matches they are
  // for; user names and counted matches are tabs of their partners.
  (
    title: 'المباريات والنتائج',
    sections: [
      AdminSection.fixtures,
      AdminSection.resultsScoring,
      AdminSection.predictions,
    ],
  ),
  (
    title: 'المسابقات والترتيب',
    sections: [
      AdminSection.monthlyCompetitions,
      AdminSection.champions,
      AdminSection.h2hLeague,
    ],
  ),
  (
    title: 'اللاعبون والتواصل',
    sections: [
      AdminSection.users,
      AdminSection.ledger,
      AdminSection.announcements,
      AdminSection.support,
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

/// Two related sections under one menu entry (script 124: tabbed): the
/// tabs on top, each section below as it was on its own page.
class AdminTabbedSection extends StatelessWidget {
  const AdminTabbedSection({super.key, required this.name, required this.tabs});

  /// Keys the tab bar (`admin.<name>.tabs`) and each tab.
  final String name;

  /// Each tab's label and its section.
  final List<(String, Widget)> tabs;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return DefaultTabController(
      length: tabs.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TabBar(
            key: Key('admin.$name.tabs'),
            labelColor: t.primaryText,
            unselectedLabelColor: t.textSecondary,
            indicatorColor: t.primary,
            dividerColor: t.border,
            tabs: <Widget>[
              for (int i = 0; i < tabs.length; i++)
                Tab(key: Key('admin.$name.tab.$i'), text: tabs[i].$1),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                for (final (String, Widget) tab in tabs) tab.$2,
              ],
            ),
          ),
        ],
      ),
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
      // script 266: the club crests, a tab for the owner admin alone.
      AdminSection.monthlyCompetitions => const AdminCompetitionsSection(),
      AdminSection.audit => const AuditLogSection(),
      AdminSection.errorLog => const ErrorLogSection(),
      AdminSection.analytics => const AdminAnalyticsSection(),
      // script 124: tabs -- the accounts, then their names; script 259:
      // the owner admin's hidden accounts, for him alone.
      AdminSection.users => const AdminUsersSection(),
      AdminSection.announcements => const AnnouncementSection(),
      AdminSection.support => const AdminSupportSection(),
      AdminSection.ledger => const LedgerLookupSection(),
      AdminSection.fixtures => const FixturesAdminSection(),
      // script 124: tabs -- recording results, then the counted matches.
      AdminSection.resultsScoring => const AdminTabbedSection(
        name: 'results',
        tabs: <(String, Widget)>[
          ('تسجيل النتائج', ResultsScoringSection()),
          ('المحتسبة', AdminCountedFixturesSection()),
        ],
      ),
      AdminSection.predictions => const AdminPredictionsSection(),
      // script 241: tabs -- the month's champion, then the Elite Cup's.
      AdminSection.champions => const AdminTabbedSection(
        name: 'champions',
        tabs: <(String, Widget)>[
          ('بطل الشهر', ChampionAdminSection()),
          ('كأس النخبة', CupChampionsAdminSection()),
        ],
      ),
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

/// The competitions section; for the owner admin alone, with a second tab:
/// the club crests the app may show (script 266). Any other admin sees the
/// competitions as before, and the server refuses him the crests anyway
/// (`admin.owner_only`).
class AdminCompetitionsSection extends ConsumerWidget {
  /// Creates the section.
  const AdminCompetitionsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool owner = isOwnerAdminSession(
      ref.watch(sessionControllerProvider).value,
    );
    if (!owner) return const AdminMonthlyCompetitionsSection();
    return const AdminTabbedSection(
      name: 'competitions',
      tabs: <(String, Widget)>[
        ('المسابقات', AdminMonthlyCompetitionsSection()),
        ('الشعارات', ClubCrestsSection()),
      ],
    );
  }
}

/// The users section's tabs: the accounts, their names, the shared phones
/// and the new players; and for the owner admin alone, the accounts he hid
/// (script 259) and the people he linked (script 264). Any other admin
/// never sees those tabs, and the server refuses him anyway
/// (`admin.owner_only`).
class AdminUsersSection extends ConsumerWidget {
  /// Creates the section.
  const AdminUsersSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool owner = isOwnerAdminSession(
      ref.watch(sessionControllerProvider).value,
    );
    return AdminTabbedSection(
      name: 'users',
      tabs: <(String, Widget)>[
        ('الحسابات', const UserSanctionSection()),
        ('الأسماء', const UserNamesSection()),
        // script 200: the phones played with several accounts.
        ('الأجهزة', const SharedDevicesSection()),
        // script 202: who joined this week, and a message to each.
        ('الجدد', const NewPlayersSection()),
        if (owner) ('المخفيون', const HiddenAccountsSection()),
        // script 264: one person behind several accounts, linked by him.
        if (owner) ('الأشخاص', const PersonLinksSection()),
      ],
    );
  }
}
