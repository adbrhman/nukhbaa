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
import '../../core/ui/brand_mark.dart';
import '../competition/competition_providers.dart';
import '../fixture_prediction/current_month_fixtures_providers.dart';
import '../history/prediction_history_providers.dart';
import '../leaderboards/champions_providers.dart';
import '../admin/admin_hub_screen.dart';
import '../groups/groups_providers.dart';
import '../groups/join_group_screen.dart';
import '../h2h/h2h_screen.dart';
import '../leaderboards/leaderboards_screen.dart';
import '../notifications/notifications_providers.dart';
import '../notifications/notifications_screen.dart';
import '../fixture_prediction/current_month_fixtures_screen.dart';
import 'account_screen.dart';
import 'home_screen.dart';
import 'launch_invite.dart';

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

  /// Whether this run already opened the invitation its address carried:
  /// the shell is built again at every sign-in.
  static bool _launchInviteOpened = false;

  /// Opens the league invitation the app's address carries (the links
  /// players share open the web build): the league's join page with its
  /// code filled in, one tap to join.
  Future<void> _openLaunchInvite() async {
    if (_launchInviteOpened) return;
    final String? league = launchInviteFrom(Uri.base).league;
    if (league == null) return;
    _launchInviteOpened = true;
    // After the frame being built.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => JoinGroupScreen(initialCode: league),
      ),
    );
    if (mounted) ref.invalidate(myGroupsProvider);
  }

  /// Opens what a tapped push is about (see push_link.dart): its tab, and
  /// for the inbox the inbox itself on top of the home tab.
  void _openLink(String link) {
    final int? tab = shellTabForLink(link);
    if (tab == null || !mounted) {
      return;
    }
    // P3-8: the open rate per push. Never awaited: the tap must not wait.
    unawaited(ref.read(authApiProvider).reportPushOpened(link: link));
    _select(tab);
    if (link == PushLinks.inbox) {
      unawaited(
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
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

  /// Reads the bell's count again
  /// whenever a notification may have arrived without the app seeing it: the
  /// app came back to the foreground from the launcher rather than from the
  /// push, or a push arrived while it was open, which Android shows no
  /// banner for. The count then stays until the inbox is opened.
  void _refreshBell() {
    if (!mounted) return;
    ref.invalidate(unreadCountProvider);
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
    // A shared league link opens on its invitation (the web build).
    unawaited(_openLaunchInvite());
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
    2 => H2hScreen(onOpenMatches: () => _select(1)),
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
                      // A kept-alive tab out of sight stops its tickers.
                      // IndexedStack keeps them running (Visibility.maintain),
                      // so an animation on a hidden tab drew frames over the
                      // visible one -- and each was a full repaint, counted
                      // as slow on low-end phones (frame stats, 2026-10-07).
                      TickerMode(enabled: i == currentIndex, child: _pageAt(i))
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

  /// The middle disc carrying the brand mark: larger than the other glyphs,
  /// still inside the bar (script 158).
  static const double brandSize = 44;

  /// The fade behind the glyphs: clear at the top, [fadeMid] of the page
  /// colour by [fadeMidStop], the page colour itself from [fadeFullStop]
  /// down, where the labels sit.
  static const double fadeMid = 0.85;
  static const double fadeMidStop = 0.3;
  static const double fadeFullStop = 0.55;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // nk-nav-glow: a rounded bar closed by a thin blue rim that glows, the
    // page colour under it in the dark theme and a white card in the light
    // one. Opaque: at 96% the list scrolled under the bar read through it.
    // No fixed height: the five items share the tallest one's height, so
    // the bar grows with the system text size instead of overflowing at
    // x2.0 (UI-04).
    // nk-nav-float: no bar at all -- the glyphs float on the page, with no
    // band, rim or corners from edge to edge. The page scrolls under them
    // (the shell's `extendBody`); a fade into the page colour behind the
    // labels keeps them at 4.5:1 over whatever passes under (script 158).
    final Color page = tokens.background;
    return DecoratedBox(
      key: const Key('nav.fade'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            page.withValues(alpha: 0),
            page.withValues(alpha: fadeMid),
            page,
          ],
          stops: const <double>[0, fadeMidStop, fadeFullStop],
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: minHeight),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // The bar's order (2026-10-10, agreed with the players):
                  // home, the league, matches, leaders, account. Each item
                  // keeps its page index, so pushes and the screen-view
                  // names still find the page they name. Every glyph wears
                  // the brand mark, drawn as a vector at one corner of
                  // each (script 160), and the middle disc carries it.
                  _item(
                    context,
                    glyph: _NavGlyph(
                      icon: Icons.home_outlined,
                      activeIcon: Icons.home_rounded,
                      badgeKey: const Key('nav.badge.home'),
                      active: index == 0,
                    ),
                    label: 'الرئيسية',
                    navKey: const Key('nav.item.home'),
                    destination: 0,
                  ),
                  _item(
                    context,
                    glyph: _NavGlyph(
                      icon: Icons.shield_outlined,
                      activeIcon: Icons.shield_rounded,
                      badgeKey: const Key('nav.badge.h2h'),
                      active: index == 2,
                    ),
                    label: 'المواجهات',
                    navKey: const Key('nav.item.h2h'),
                    destination: 2,
                  ),
                  _item(
                    context,
                    glyph: _NavBrand(
                      key: const Key('nav.brand'),
                      size: brandSize,
                      badgeKey: const Key('nav.badge.fixtures'),
                      active: index == 1,
                    ),
                    label: 'المباريات',
                    navKey: const Key('nav.item.fixtures'),
                    destination: 1,
                  ),
                  _item(
                    context,
                    glyph: _NavGlyph(
                      icon: Icons.leaderboard_outlined,
                      activeIcon: Icons.leaderboard_rounded,
                      badgeKey: const Key('nav.badge.leaders'),
                      active: index == 3,
                    ),
                    label: 'المتصدرون',
                    navKey: const Key('nav.item.leaders'),
                    destination: 3,
                  ),
                  _item(
                    context,
                    glyph: _NavGlyph(
                      icon: Icons.person_outline_rounded,
                      activeIcon: Icons.person_rounded,
                      badgeKey: const Key('nav.badge.account'),
                      active: index == 4,
                    ),
                    label: 'الحساب',
                    navKey: const Key('nav.item.account'),
                    destination: 4,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context, {
    required Widget glyph,
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
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.xs,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                glyph,
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
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                // The open tab is underlined with a short glowing bar; the
                // others keep its room so every label sits on one line.
                Container(
                  key: active ? const Key('nav.indicator') : null,
                  width: 24,
                  height: 3,
                  decoration: active
                      ? BoxDecoration(
                          color: tokens.primary,
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: tokens.primary.withValues(alpha: 0.6),
                              blurRadius: 6,
                            ),
                          ],
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One glyph of the bar (script 160): the tab's icon -- outlined while
/// closed, filled in a soft blue pill while open -- with the brand mark,
/// a vector tile, at its top corner on the reading side's end. Every tab
/// wears it in the same place and size; on a picture of the logo scaled to
/// 12 px it read as a blurred blue square laid over the icon.
class _NavGlyph extends StatelessWidget {
  const _NavGlyph({
    required this.icon,
    required this.activeIcon,
    required this.badgeKey,
    required this.active,
  });

  final IconData icon;
  final IconData activeIcon;
  final Key badgeKey;
  final bool active;

  /// The pill behind the open tab's icon.
  static const Size pill = Size(54, 32);

  /// The icon itself.
  static const double iconSize = 24;

  /// The brand tile on the icon's corner.
  static const double badgeSize = 11;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final Color color = active ? tokens.primaryText : tokens.textSecondary;
    final Color pillColor = active
        ? tokens.primary.withValues(alpha: tokens.isDark ? 0.2 : 0.12)
        : tokens.primary.withValues(alpha: 0);
    // The ring is what sits behind the tile: the page, or the open pill.
    final Color ring = Color.alphaBlend(pillColor, tokens.background);
    return SizedBox.fromSize(
      size: pill,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: <Widget>[
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: pill.width,
            height: pill.height,
            decoration: BoxDecoration(
              color: pillColor,
              borderRadius: BorderRadius.circular(pill.height / 2),
            ),
          ),
          Icon(active ? activeIcon : icon, size: iconSize, color: color),
          // On the icon's top corner, cut out of it by a ring of the page
          // colour so the two never blur into one shape.
          PositionedDirectional(
            top: (pill.height - iconSize) / 2 - 4,
            end: (pill.width - iconSize) / 2 - 5,
            child: Container(
              key: badgeKey,
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(
                color: ring,
                borderRadius: BorderRadius.circular(4.5),
              ),
              child: const BrandMark(size: badgeSize),
            ),
          ),
        ],
      ),
    );
  }
}

/// The middle tab (script 160): a blue disc carrying the white brand mark,
/// in place of the ball with a picture of the logo laid on it. Inside the
/// bar, as since script 158; open, its rim lights and it glows.
class _NavBrand extends StatelessWidget {
  const _NavBrand({
    required this.size,
    required this.badgeKey,
    required this.active,
    super.key,
  });

  final double size;
  final Key badgeKey;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFF2F8FEA), kBrandMarkBlue, Color(0xFF1262B0)],
        ),
        border: Border.all(
          color: active
              ? tokens.primaryText
              : tokens.primary.withValues(alpha: 0.35),
          width: active ? 2 : 1,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: kBrandMarkBlue.withValues(alpha: active ? 0.55 : 0.22),
            blurRadius: active ? 14 : 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: BrandMark(key: badgeKey, size: size * 0.6, tile: false),
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
