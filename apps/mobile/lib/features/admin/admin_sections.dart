library;

import 'package:flutter/material.dart';

enum AdminSection {
  audit(icon: Icons.receipt_long_rounded),
  users(icon: Icons.people_alt_rounded),
  ledger(icon: Icons.account_balance_wallet_rounded),
  fixtures(icon: Icons.sports_soccer_rounded),
  resultsScoring(icon: Icons.scoreboard_rounded);

  const AdminSection({required this.icon});

  final IconData icon;
}
