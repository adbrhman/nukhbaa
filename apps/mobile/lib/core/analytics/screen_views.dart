/// Which screens a player opens (migration 0093): the baseline every display
/// feature (badges, insights, the elite card, groups, duels) is measured
/// against.
///
/// A screen says its name by implementing [NamedScreen]. [ScreenViewObserver]
/// sees every route the app's navigator pushes, finds the [NamedScreen] at
/// the top of the new route once it is built, and counts one open in
/// [ScreenViewLog]. The bottom-bar tabs are not routes, so the shell counts
/// them itself. [ScreenViewReporter] sends the counts in one request when
/// the app goes to the background, and keeps them for the next time when the
/// request fails.
///
/// Only names and counts leave the device: nothing about what was on the
/// screen.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A screen whose opens are counted under [screenName], one of
/// [ScreenNames.all].
abstract interface class NamedScreen {
  /// The name this screen's opens are counted under.
  String get screenName;
}

/// The screen names the server knows. Mirrors `ScreenName` in the domain
/// package; the two sets must stay equal.
abstract final class ScreenNames {
  static const String home = 'home';
  static const String matches = 'matches';
  static const String predictions = 'predictions';
  static const String leaderboard = 'leaderboard';
  static const String account = 'account';
  static const String notifications = 'notifications';
  static const String duels = 'duels';
  static const String duelAccept = 'duel_accept';
  static const String duelCreate = 'duel_create';
  static const String predictionReactions = 'prediction_reactions';
  static const String groups = 'groups';
  static const String groupFeed = 'group_feed';
  static const String groupLeaderboard = 'group_leaderboard';
  static const String groupCreate = 'group_create';
  static const String groupJoin = 'group_join';
  static const String badges = 'badges';
  static const String insights = 'insights';
  static const String invite = 'invite';
  static const String hallOfFame = 'hall_of_fame';
  static const String champions = 'champions';
  static const String seasonLeaderboard = 'season_leaderboard';
  static const String predictionsBoard = 'predictions_board';
  static const String eliteCard = 'elite_card';
  static const String myPoints = 'my_points';
  static const String mySeasons = 'my_seasons';
  static const String seasonRecord = 'season_record';
  static const String rules = 'rules';
  static const String settings = 'settings';
  static const String notificationSettings = 'notification_settings';
  static const String favoriteTeams = 'favorite_teams';
  static const String fixturePrediction = 'fixture_prediction';
  static const String ledger = 'ledger';

  /// The bottom-bar tabs, in the bar's order.
  static const List<String> tabs = <String>[
    home,
    matches,
    predictions,
    leaderboard,
    account,
  ];

  /// Every name above.
  static const Set<String> all = <String>{
    home,
    matches,
    predictions,
    leaderboard,
    account,
    notifications,
    duels,
    duelAccept,
    duelCreate,
    predictionReactions,
    groups,
    groupFeed,
    groupLeaderboard,
    groupCreate,
    groupJoin,
    badges,
    insights,
    invite,
    hallOfFame,
    champions,
    seasonLeaderboard,
    predictionsBoard,
    eliteCard,
    myPoints,
    mySeasons,
    seasonRecord,
    rules,
    settings,
    notificationSettings,
    favoriteTeams,
    fixturePrediction,
    ledger,
  };
}

/// Opens counted since the last report, per screen name.
class ScreenViewLog {
  final Map<String, int> _opens = <String, int>{};

  /// The most opens of one screen one report may claim (the server's
  /// limit); counting stops there until the next report.
  static const int maxOpensPerScreen = 1000;

  /// The counts not yet reported.
  Map<String, int> get pending => Map<String, int>.unmodifiable(_opens);

  /// Counts one open of [screen]. A name outside [ScreenNames.all] is
  /// ignored.
  void record(String screen) {
    if (!ScreenNames.all.contains(screen)) return;
    _add(screen, 1);
  }

  /// Hands over every count and starts again from nothing.
  Map<String, int> drain() {
    final Map<String, int> out = Map<String, int>.of(_opens);
    _opens.clear();
    return out;
  }

  /// Puts back counts a failed report took, adding them to any counted
  /// since.
  void restore(Map<String, int> opens) {
    opens.forEach(_add);
  }

  void _add(String screen, int count) {
    _opens[screen] = math.min((_opens[screen] ?? 0) + count, maxOpensPerScreen);
  }
}

/// Counts one open of the [NamedScreen] at the top of every route the
/// navigator pushes. Dialogs and screens without a name count nothing.
class ScreenViewObserver extends NavigatorObserver {
  /// Creates an observer that counts into [log].
  ScreenViewObserver(this._log);

  final ScreenViewLog _log;

  /// How deep under a route's root the search goes. A page sits a few
  /// elements down; a bottom sheet's content a few dozen, under the sheet's
  /// themes, animation and Material.
  static const int maxDepth = 96;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _countWhenBuilt(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) _countWhenBuilt(newRoute);
  }

  void _countWhenBuilt(Route<dynamic> route) {
    if (route is! ModalRoute<dynamic>) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final String? name = screenNameOf(route);
      if (name != null) _log.record(name);
    });
  }

  /// The name of the first [NamedScreen] under [route]'s root, searched
  /// level by level, or null when the route is not built or has none.
  static String? screenNameOf(ModalRoute<dynamic> route) {
    final BuildContext? root = route.subtreeContext;
    if (root == null || !root.mounted) return null;
    List<BuildContext> level = <BuildContext>[root];
    for (int depth = 0; depth < maxDepth && level.isNotEmpty; depth++) {
      final List<BuildContext> next = <BuildContext>[];
      for (final BuildContext context in level) {
        if (context.widget case final NamedScreen named) {
          return named.screenName;
        }
        context.visitChildElements(next.add);
      }
      level = next;
    }
    return null;
  }
}

/// Sends the counted opens once each time the app leaves the foreground.
class ScreenViewReporter with WidgetsBindingObserver {
  /// Creates a reporter that hands [log]'s counts to [send], which answers
  /// whether the server kept them.
  ///
  /// A local or test build ([enabled] false) never sends, so a developer's
  /// taps never reach the production numbers.
  ScreenViewReporter({
    required ScreenViewLog log,
    required Future<bool> Function(Map<String, int> opens) send,
    this.enabled = true,
  }) : _log = log,
       _send = send;

  final ScreenViewLog _log;
  final Future<bool> Function(Map<String, int> opens) _send;

  /// Whether reports are sent at all.
  final bool enabled;

  bool _started = false;
  bool _sending = false;

  /// Starts listening for the app leaving the foreground.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
  }

  /// Stops listening. Counts not yet sent stay in the log.
  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(flush());
    }
  }

  /// Sends what was counted since the last report. A failed send puts the
  /// counts back for the next one. Never throws.
  Future<void> flush() async {
    if (!enabled || _sending) return;
    final Map<String, int> opens = _log.drain();
    if (opens.isEmpty) return;
    _sending = true;
    bool kept;
    try {
      kept = await _send(opens);
    } on Object catch (_) {
      kept = false;
    } finally {
      _sending = false;
    }
    if (!kept) _log.restore(opens);
  }
}

/// The app's one log of screen opens.
final Provider<ScreenViewLog> screenViewLogProvider = Provider<ScreenViewLog>(
  (Ref ref) => ScreenViewLog(),
);

/// The one observer the app's navigator counts opens through.
final Provider<ScreenViewObserver> screenViewObserverProvider =
    Provider<ScreenViewObserver>(
      (Ref ref) => ScreenViewObserver(ref.watch(screenViewLogProvider)),
    );
