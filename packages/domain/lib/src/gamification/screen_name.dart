/// The screens whose opens the app reports (migration 0093): a closed
/// vocabulary, so the weekly usage view reads one name per feature.
///
/// The app keeps a mirror of these names (`ScreenNames` in
/// `apps/mobile/lib/core/analytics/screen_views.dart`); the two sets must
/// stay equal. A name this set does not know is dropped by the server, so
/// an app that is newer than the server never fails its report.
abstract final class ScreenName {
  /// The home tab.
  static const String home = 'home';

  /// The matches tab.
  static const String matches = 'matches';

  /// The "my predictions" tab.
  static const String predictions = 'predictions';

  /// The leaderboard tab.
  static const String leaderboard = 'leaderboard';

  /// The account tab.
  static const String account = 'account';

  /// The notifications inbox.
  static const String notifications = 'notifications';

  /// The Duels page.
  static const String duels = 'duels';

  /// The sheet that accepts a duel challenge with a prediction.
  static const String duelAccept = 'duel_accept';

  /// The sheet that creates a duel challenge.
  static const String duelCreate = 'duel_create';

  /// The sheet of reactions on one prediction of the board (0094).
  static const String predictionReactions = 'prediction_reactions';

  /// The player's groups.
  static const String groups = 'groups';

  /// One group's activity feed.
  static const String groupFeed = 'group_feed';

  /// One group's leaderboard.
  static const String groupLeaderboard = 'group_leaderboard';

  /// Creating a group.
  static const String groupCreate = 'group_create';

  /// Joining a group by code.
  static const String groupJoin = 'group_join';

  /// The player's badges.
  static const String badges = 'badges';

  /// The "learn from your predictions" insights.
  static const String insights = 'insights';

  /// Inviting friends.
  static const String invite = 'invite';

  /// The hall of fame.
  static const String hallOfFame = 'hall_of_fame';

  /// The record of monthly champions.
  static const String champions = 'champions';

  /// One season's full leaderboard.
  static const String seasonLeaderboard = 'season_leaderboard';

  /// Every player's predictions for the day's started fixtures.
  static const String predictionsBoard = 'predictions_board';

  /// The shareable elite card.
  static const String eliteCard = 'elite_card';

  /// The player's points.
  static const String myPoints = 'my_points';

  /// The player's seasons.
  static const String mySeasons = 'my_seasons';

  /// One season's record.
  static const String seasonRecord = 'season_record';

  /// The competition rules.
  static const String rules = 'rules';

  /// Account settings.
  static const String settings = 'settings';

  /// Notification settings.
  static const String notificationSettings = 'notification_settings';

  /// Favourite teams.
  static const String favoriteTeams = 'favorite_teams';

  /// One fixture's prediction page.
  static const String fixturePrediction = 'fixture_prediction';

  /// The points ledger.
  static const String ledger = 'ledger';

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
