library;

import 'package:flutter/material.dart';

/// كل قسم من أقسام لوحة تحكم الأدمن. القائمة مطابقة للهيكل المعتمد
/// (راجع قسم 9 من مرجع الاستمرارية). الأقسام التي لا تملك تنفيذاً فعلياً
/// بعد تعرض [AdminComingSoonSection] عبر [AdminShell._bodyFor].
///
/// ملاحظة: `ledger` (البحث في السجل المالي) محفوظة رغم غيابها عن الهيكل
/// المطلوب — ميزة حقيقية قائمة، لا تُحذف دون موافقة صريحة.
enum AdminSection {
  dashboard(icon: Icons.dashboard_rounded),
  monthlyCompetitions(icon: Icons.calendar_month_rounded),
  fixtures(icon: Icons.sports_soccer_rounded),
  predictions(icon: Icons.rule_folder_rounded),
  dailyDoubles(icon: Icons.bolt_rounded),
  resultsScoring(icon: Icons.scoreboard_rounded),
  leaderboards(icon: Icons.leaderboard_rounded),
  users(icon: Icons.people_alt_rounded),
  competitions(icon: Icons.emoji_events_rounded),
  teams(icon: Icons.groups_rounded),
  social(icon: Icons.forum_rounded),
  notifications(icon: Icons.notifications_rounded),
  reportsAnalytics(icon: Icons.insights_rounded),
  ledger(icon: Icons.account_balance_wallet_rounded),
  audit(icon: Icons.receipt_long_rounded),
  systemHealth(icon: Icons.health_and_safety_rounded),
  rolesPermissions(icon: Icons.admin_panel_settings_rounded),
  settings(icon: Icons.settings_rounded);

  const AdminSection({required this.icon});

  final IconData icon;
}
