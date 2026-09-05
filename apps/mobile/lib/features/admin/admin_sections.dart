library;

import 'package:flutter/material.dart';

/// كل قسم من أقسام لوحة تحكم الأدمن. القائمة تحوي الأقسام المنفَّذة فقط:
/// عشرة أقسام نائبة كانت تعرض «قيد التطوير» حُذفت بقرار صريح، فلا تظهر في
/// التنقّل ما لا يعمل. إعادة أي منها تعني إعادة قيمته هنا مع قسمه الفعلي.
///
/// ملاحظة: `ledger` (البحث في السجل المالي) محفوظة رغم غيابها عن الهيكل
/// المطلوب — ميزة حقيقية قائمة، لا تُحذف دون موافقة صريحة.
enum AdminSection {
  dashboard(icon: Icons.dashboard_rounded),
  monthlyCompetitions(icon: Icons.calendar_month_rounded),
  fixtures(icon: Icons.sports_soccer_rounded),
  predictions(icon: Icons.rule_folder_rounded),
  resultsScoring(icon: Icons.scoreboard_rounded),
  users(icon: Icons.people_alt_rounded),
  ledger(icon: Icons.account_balance_wallet_rounded),
  audit(icon: Icons.receipt_long_rounded);

  const AdminSection({required this.icon});

  final IconData icon;
}
