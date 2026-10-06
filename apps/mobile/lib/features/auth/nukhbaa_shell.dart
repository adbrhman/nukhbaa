import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/screen_views.dart';
import '../../core/design/app_typography.dart';
import '../../core/design/app_sizes.dart';
import '../../core/design/app_spacing.dart';
import '../../core/design/app_tokens.dart';
import '../../core/notifications/push_link.dart';
import '../../core/perf/frame_reporter.dart';
import '../../core/providers.dart';
import '../../core/time/riyadh_day_turnover.dart';
import '../competition/competition_providers.dart';
import '../fixture_prediction/current_month_fixtures_providers.dart';
import '../history/prediction_history_providers.dart';
import '../leaderboards/champions_providers.dart';
import '../admin/admin_hub_screen.dart';
import '../duels/duels_providers.dart';
import '../duels/duels_screen.dart';
import '../history/prediction_history_screen.dart';
import '../leaderboards/leaderboards_screen.dart';
import '../notifications/notifications_providers.dart';
import '../notifications/notifications_screen.dart';
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

class _NukhbaaShellState extends ConsumerState<NukhbaaShell>
    with WidgetsBindingObserver {
  int currentIndex = 0;

  /// PERF: IndexedStack builds every child on the first frame, so all five
  /// tabs used to fire their reads at launch -- the predictions tab alone
  /// issues one scores request per row, for a tab nobody has opened. A tab
  /// is built the first time it is selected and kept alive from then on,
  /// which preserves the scroll position and in-progress prediction the
  /// IndexedStack was chosen for, without paying for unopened tabs.
  final Set<int> _built = <int>{0};

  void _select(int index) {
    // The tabs are not routes, so the navigator's observer never sees
    // them: a switch to another tab is counted here (migration 0093).
    if (index != currentIndex) {
      ref.read(screenViewLogProvider).record(ScreenNames.tabs[index]);
    }
    setState(() {
      currentIndex = index;
      _built.add(index);
    });
  }

  /// Opens what a tapped push is about (see push_link.dart): its tab, and
  /// for the inbox the inbox itself on top of the home tab. A duel push
  /// opens the Duels page, and `duel:CODE` that challenge's accept sheet.
  void _openLink(String link) {
    final int? tab = shellTabForLink(link);
    if (tab == null || !mounted) {
      return;
    }
    // P3-8: the open rate per push. Never awaited: the tap must not wait.
    unawaited(
      ref
          .read(authApiProvider)
          .reportPushOpened(link: pushOpenNameForLink(link)),
    );
    _select(tab);
    if (link == PushLinks.inbox) {
      unawaited(
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
        ),
      );
    } else if (pushOpenNameForLink(link) == PushLinks.duel) {
      final String? code = duelCodeForLink(link);
      unawaited(
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder: (_) => DuelsScreen(openCode: code)),
        ),
      );
    }
  }

  /// At 00:00 Riyadh the month (on the 1st) and the day change under an app
  /// that stayed open: the reads that name "now" are read again, so the
  /// leaderboard lands in the new month (the server enrols the player on
  /// that read) and the celebration starts, without a restart.
  late final RiyadhDayTurnover _turnover = RiyadhDayTurnover(
    onTurnover: _onNewDay,
  );

  void _onNewDay() {
    if (!mounted) return;
    ref.invalidate(activeSeasonsProvider);
    ref.invalidate(currentMonthFixturesProvider);
    ref.invalidate(monthChampionsProvider);
    ref.invalidate(myFixturePredictionsProvider);
  }

  /// Reads the bell's count (and the duels a push may be about) again
  /// whenever a notification may have arrived without the app seeing it: the
  /// app came back to the foreground from the launcher rather than from the
  /// push, or a push arrived while it was open, which Android shows no
  /// banner for. The count then stays until the inbox is opened.
  void _refreshBell() {
    if (!mounted) return;
    ref.invalidate(unreadCountProvider);
    ref.invalidate(myDuelsProvider);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshBell();
  }

  @override
  void initState() {
    super.initState();
    _turnover.start();
    WidgetsBinding.instance.addObserver(this);
    // Every session opens on the home tab.
    ref.read(screenViewLogProvider).record(ScreenNames.home);
    // Fire-and-forget, and only once the user is signed in: the token is
    // bound to an account server-side, so registering before sign-in would
    // have nobody to bind it to. Never awaited -- registration must not
    // delay the first frame.
    unawaited(ref.read(pushTokenServiceProvider).registerCurrentDevice());
    // A push says where it should open: the tap that launched the app, then
    // every later one while it runs.
    unawaited(
      ref
          .read(pushTokenServiceProvider)
          .listenForOpenedPushes(_openLink, onForegroundPush: _refreshBell),
    );
    // The device's own clock offset, for notification timing only -- no day
    // boundary is derived from it. Re-sent on every start because an offset
    // carries no daylight-saving rule, and sent on web too, unlike the push
    // token: the web build is where the iPhone users are.
    unawaited(
      ref
          .read(authApiProvider)
          .reportTimeZoneOffset(
            offsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
          ),
    );
    // Frame smoothness from every device (migration 0070): one report per
    // session, sent when the app leaves the foreground. The API is taken
    // now, so a report never reaches for ref after the shell is gone.
    final authApi = ref.read(authApiProvider);
    _frames = FrameReporter(
      send: (report) async {
        await authApi.reportFrames(report);
      },
      build: const String.fromEnvironment('NUKHBA_BUILD_SHA'),
      platform: FrameReporter.currentPlatform,
    )..start();
    // Which screens were opened (migration 0093): one report each time the
    // app leaves the foreground; a failed one is kept for the next. A local
    // or test build (no commit sha) never reports.
    _screens = ScreenViewReporter(
      log: ref.read(screenViewLogProvider),
      send: (Map<String, int> opens) async =>
          (await authApi.reportScreenViews(opens)).isOk,
      enabled: const String.fromEnvironment('NUKHBA_BUILD_SHA').isNotEmpty,
    )..start();
  }

  late final FrameReporter _frames;

  late final ScreenViewReporter _screens;

  @override
  void dispose() {
    _turnover.stop();
    WidgetsBinding.instance.removeObserver(this);
    _frames.stop();
    _screens.stop();
    super.dispose();
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

  /// Android's back button on any tab but home returns to the home tab;
  /// only from home does it leave the app. One back press on the matches or
  /// leaderboard tab used to close the app outright.
  void _onBack(bool didPop, Object? result) {
    if (didPop || currentIndex == 0) return;
    _select(0);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: currentIndex == 0,
      onPopInvokedWithResult: _onBack,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: context.tokens.background,
          extendBody: true,
          // On a tablet the tabs keep a phone-like reading width, centred,
          // instead of stretching cards and tables edge to edge. A phone is
          // narrower than the cap, so nothing changes there.
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSizes.maxContentWidth,
              ),
              child: IndexedStack(
                index: currentIndex,
                children: <Widget>[
                  for (int i = 0; i < tabCount; i++)
                    if (_built.contains(i))
                      _pageAt(i)
                    else
                      const SizedBox.shrink(),
                ],
              ),
            ),
          ),
          bottomNavigationBar: NukhbaaBottomNav(
            index: currentIndex,
            onChanged: _select,
          ),
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

  /// The bar's height at normal text size; it grows with larger text.
  static const double minHeight = 70;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // Opaque, closed by a hairline on top: at 96% the list scrolled under
    // the bar read through it. No fixed height: the five items share the
    // tallest one's height, so the bar grows with the system text size
    // instead of overflowing at x2.0 (UI-04).
    return Material(
      color: tokens.backgroundElevated,
      shape: Border(top: BorderSide(color: tokens.border)),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minHeight),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
    // Blue made for text: primaryLight was 4.49:1 on the light bar (UI-03).
    final color = active ? tokens.primaryText : tokens.textSecondary;
    return Expanded(
      // A screen reader hears which tab is the current one (UI-04).
      child: Semantics(
        container: true,
        button: true,
        selected: active,
        child: InkWell(
          key: navKey,
          onTap: () => onChanged(destination),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.sm,
              horizontal: AppSpacing.xs,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(active ? activeIcon : icon, size: 22, color: color),
                const SizedBox(height: AppSpacing.xs),
                // 12px, from 10: the smallest label the bar may carry.
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: AppFontSize.s12,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
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
