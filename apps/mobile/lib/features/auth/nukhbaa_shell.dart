import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_tokens.dart';
import '../admin/admin_hub_screen.dart';
import '../history/prediction_history_screen.dart';
import '../leaderboards/leaderboards_screen.dart';
import '../fixture_prediction/current_month_fixtures_screen.dart';
import 'account_screen.dart';
import 'home_screen.dart';

/// The authenticated app shell. The five destinations are kept alive in an
/// IndexedStack so an in-progress prediction or scroll position survives tab
/// changes.
class NukhbaaShell extends ConsumerStatefulWidget {
  const NukhbaaShell({required this.user, super.key});

  final AuthenticatedUserDto user;

  @override
  ConsumerState<NukhbaaShell> createState() => _NukhbaaShellState();
}

class _NukhbaaShellState extends ConsumerState<NukhbaaShell> {
  int currentIndex = 0;

  List<Widget> get pages => <Widget>[
        HomeScreen(
          user: widget.user,
          onOpenMatches: () => setState(() => currentIndex = 1),
          onOpenPredictions: () => setState(() => currentIndex = 2),
          onOpenLeaderboards: () => setState(() => currentIndex = 3),
          onOpenAccount: () => setState(() => currentIndex = 4),
        ),
        const CurrentMonthFixturesScreen(),
        const PredictionHistoryScreen(),
        const LeaderboardsScreen(),
        AccountScreen(user: widget.user),
      ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: context.tokens.background,
        extendBody: true,
        body: IndexedStack(index: currentIndex, children: pages),
        bottomNavigationBar: NukhbaaBottomNav(
          index: currentIndex,
          onChanged: (index) => setState(() => currentIndex = index),
        ),
      ),
    );
  }
}

class NukhbaaBottomNav extends StatelessWidget {
  const NukhbaaBottomNav({
    required this.index,
    required this.onChanged,
    super.key,
  });

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.backgroundElevated.withValues(alpha: 0.96),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 70,
          child: Row(
            children: <Widget>[
              _item(
                context,
                icon: Icons.home_outlined,
                activeIcon: Icons.home_rounded,
                label: 'الرئيسية',
                destination: 0,
              ),
              _item(
                context,
                icon: Icons.sports_soccer_outlined,
                activeIcon: Icons.sports_soccer,
                label: 'المباريات',
                destination: 1,
              ),
              _item(
                context,
                icon: Icons.bolt_outlined,
                activeIcon: Icons.bolt_rounded,
                label: 'توقعاتي',
                destination: 2,
              ),
              _item(
                context,
                icon: Icons.leaderboard_outlined,
                activeIcon: Icons.leaderboard_rounded,
                label: 'المتصدرون',
                destination: 3,
              ),
              _item(
                context,
                icon: Icons.person_outline_rounded,
                activeIcon: Icons.person_rounded,
                label: 'الحساب',
                destination: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context, {
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int destination,
  }) {
    final tokens = context.tokens;
    final active = index == destination;
    final color = active ? tokens.primaryLight : tokens.textSecondary;
    return Expanded(
      child: InkWell(
        onTap: () => onChanged(destination),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(active ? activeIcon : icon, size: 22, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kept as a small compatibility entry point for older callers that opened
/// the admin shell directly. Authorization remains server-side and the
/// authenticated account route is the normal entry point.
class NukhbaaAdminShortcut extends StatelessWidget {
  const NukhbaaAdminShortcut({super.key});

  @override
  Widget build(BuildContext context) => const AdminHubScreen();
}