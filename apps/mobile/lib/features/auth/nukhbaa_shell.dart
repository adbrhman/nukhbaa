import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_tokens.dart';
import '../../core/providers.dart';
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

  /// PERF: IndexedStack builds every child on the first frame, so all five
  /// tabs used to fire their reads at launch -- the predictions tab alone
  /// issues one scores request per row, for a tab nobody has opened. A tab
  /// is built the first time it is selected and kept alive from then on,
  /// which preserves the scroll position and in-progress prediction the
  /// IndexedStack was chosen for, without paying for unopened tabs.
  final Set<int> _built = <int>{0};

  void _select(int index) {
    setState(() {
      currentIndex = index;
      _built.add(index);
    });
  }

  @override
  void initState() {
    super.initState();
    // Fire-and-forget, and only once the user is signed in: the token is
    // bound to an account server-side, so registering before sign-in would
    // have nobody to bind it to. Never awaited -- registration must not
    // delay the first frame.
    unawaited(ref.read(pushTokenServiceProvider).registerCurrentDevice());
  }

  /// The number of destinations in the bottom bar.
  static const int tabCount = 5;

  /// One destination, built on demand. Index order is the bottom bar's.
  Widget _pageAt(int index) => switch (index) {
    0 => HomeScreen(
      user: widget.user,
      onOpenMatches: () => _select(1),
      onOpenAccount: () => _select(4),
    ),
    1 => const CurrentMonthFixturesScreen(),
    2 => const PredictionHistoryScreen(),
    3 => LeaderboardsScreen(
      userDisplayName: widget.user.displayName,
      userId: widget.user.userId,
    ),
    _ => AccountScreen(user: widget.user),
  };

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: context.tokens.background,
        extendBody: true,
        body: IndexedStack(
          index: currentIndex,
          children: <Widget>[
            for (int i = 0; i < tabCount; i++)
              if (_built.contains(i)) _pageAt(i) else const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: NukhbaaBottomNav(
          index: currentIndex,
          onChanged: _select,
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
                navKey: const Key('nav.item.home'),
                destination: 0,
              ),
              _item(
                context,
                icon: Icons.sports_soccer_outlined,
                activeIcon: Icons.sports_soccer,
                label: 'المباريات',
                navKey: const Key('nav.item.fixtures'),
                destination: 1,
              ),
              _item(
                context,
                icon: Icons.bolt_outlined,
                activeIcon: Icons.bolt_rounded,
                label: 'توقعاتي',
                navKey: const Key('nav.item.predictions'),
                destination: 2,
              ),
              _item(
                context,
                icon: Icons.leaderboard_outlined,
                activeIcon: Icons.leaderboard_rounded,
                label: 'المتصدرون',
                navKey: const Key('nav.item.leaders'),
                destination: 3,
              ),
              _item(
                context,
                icon: Icons.person_outline_rounded,
                activeIcon: Icons.person_rounded,
                label: 'الحساب',
                navKey: const Key('nav.item.account'),
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
    required Key navKey,
  }) {
    final tokens = context.tokens;
    final active = index == destination;
    final color = active ? tokens.primaryLight : tokens.textSecondary;
    return Expanded(
      child: InkWell(
        key: navKey,
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
