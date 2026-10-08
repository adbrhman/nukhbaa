library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_providers.dart';
import 'admin_sections.dart';
import 'screens/sections/admin_home_section.dart';

/// How many things wait in each admin section (2026-10-08), for the counts
/// beside the menu entries. Built from the very sources and functions the
/// home page's «يحتاج تدخلك» uses, so the menu and the home page never
/// disagree: matches over with no result, invitations held for review, new
/// errors, and ended months with players and no champion.
///
/// A source not loaded yet, or that failed, adds no count: the home page is
/// where a failed read is said.
Map<AdminSection, int> adminNavCounts({
  required AdminDashboardSnapshot? dashboard,
  required AdminAttention? attention,
  required AdminMonthPulse? month,
  required DateTime now,
}) {
  final Map<AdminSection, int> counts = <AdminSection, int>{};
  void put(AdminSection section, int? count) {
    if (count != null && count > 0) counts[section] = count;
  }

  put(
    AdminSection.resultsScoring,
    dashboard == null
        ? null
        : fixturesAwaitingResult(dashboard.currentMonthFixtures, now).length,
  );
  put(AdminSection.referrals, attention?.heldReferrals);
  put(AdminSection.errorLog, attention?.freshErrors);
  put(AdminSection.champions, month?.uncrowned.length);
  return counts;
}

/// [adminNavCounts] over the live providers. A plain provider: no code
/// generation.
final adminNavCountsProvider = Provider<Map<AdminSection, int>>((ref) {
  return adminNavCounts(
    dashboard: ref.watch(adminDashboardProvider).value,
    attention: ref.watch(adminAttentionProvider).value,
    month: ref.watch(adminMonthPulseProvider).value,
    now: DateTime.now(),
  );
});
