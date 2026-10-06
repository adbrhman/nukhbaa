/// One match in play, as the viewer stands in it.
final class LiveFixtureStandingDto {
  /// Creates the line.
  const LiveFixtureStandingDto({
    required this.fixtureId,
    required this.homeGoals,
    required this.awayGoals,
    required this.finished,
    this.minute,
    this.myPoints,
  });

  /// Deserializes from a JSON map; null when the line is unreadable.
  static LiveFixtureStandingDto? tryFromJson(Map<String, Object?> json) {
    final Object? id = json['fixture_id'];
    final Object? home = json['home_goals'];
    final Object? away = json['away_goals'];
    if (id is! String || home is! int || away is! int) return null;
    return LiveFixtureStandingDto(
      fixtureId: id,
      homeGoals: home,
      awayGoals: away,
      minute: json['minute'] as int?,
      finished: json['finished'] == true,
      myPoints: json['my_points'] as int?,
    );
  }

  /// The match.
  final String fixtureId;

  /// The running score.
  final int homeGoals;

  /// The running score.
  final int awayGoals;

  /// The match minute, when the provider reports one.
  final int? minute;

  /// The provider says it is over; its result is not recorded yet.
  final bool finished;

  /// What the viewer's prediction would earn if the match ended now; null
  /// when they did not predict it.
  final int? myPoints;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'fixture_id': fixtureId,
    'home_goals': homeGoals,
    'away_goals': awayGoals,
    'minute': minute,
    'finished': finished,
    'my_points': myPoints,
  };
}

/// One of the viewer's duels on a match in play.
final class LiveDuelStandingDto {
  /// Creates the line.
  const LiveDuelStandingDto({
    required this.fixtureId,
    required this.opponentName,
    required this.myPoints,
    required this.opponentPoints,
  });

  /// Deserializes from a JSON map; null when the line is unreadable.
  static LiveDuelStandingDto? tryFromJson(Map<String, Object?> json) {
    final Object? id = json['fixture_id'];
    final Object? mine = json['my_points'];
    final Object? theirs = json['opponent_points'];
    if (id is! String || mine is! int || theirs is! int) return null;
    return LiveDuelStandingDto(
      fixtureId: id,
      opponentName: (json['opponent_name'] as String?) ?? '',
      myPoints: mine,
      opponentPoints: theirs,
    );
  }

  /// The match.
  final String fixtureId;

  /// The other player.
  final String opponentName;

  /// What the viewer would earn if the match ended now.
  final int myPoints;

  /// What the other player would earn.
  final int opponentPoints;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'fixture_id': fixtureId,
    'opponent_name': opponentName,
    'my_points': myPoints,
    'opponent_points': opponentPoints,
  };
}

/// Body of `GET /seasons/{id}/live`: while the season's matches are in
/// play, what the viewer's predictions would earn if they ended now, their
/// place on the month board now and then, and their duels on those matches.
/// Graded on the server; nothing here is stored.
final class LiveStandingDto {
  /// Creates the answer.
  const LiveStandingDto({
    required this.fixtures,
    required this.duels,
    required this.pointsNow,
    required this.pointsIfEnded,
    required this.players,
    this.rankNow,
    this.rankIfEnded,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys; an unreadable
  /// line is left out.
  factory LiveStandingDto.fromJson(Map<String, Object?> json) {
    final Object? fixtures = json['fixtures'];
    final Object? duels = json['duels'];
    return LiveStandingDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      fixtures: <LiveFixtureStandingDto>[
        if (fixtures is List<Object?>)
          for (final Object? item in fixtures)
            if (item is Map<String, Object?>)
              ?LiveFixtureStandingDto.tryFromJson(item),
      ],
      duels: <LiveDuelStandingDto>[
        if (duels is List<Object?>)
          for (final Object? item in duels)
            if (item is Map<String, Object?>)
              ?LiveDuelStandingDto.tryFromJson(item),
      ],
      rankNow: json['rank_now'] as int?,
      rankIfEnded: json['rank_if_ended'] as int?,
      pointsNow: (json['points_now'] as int?) ?? 0,
      pointsIfEnded: (json['points_if_ended'] as int?) ?? 0,
      players: (json['players'] as int?) ?? 0,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The season's matches in play; empty when none is.
  final List<LiveFixtureStandingDto> fixtures;

  /// The viewer's duels on them.
  final List<LiveDuelStandingDto> duels;

  /// The viewer's place on the month board now; null when not on it.
  final int? rankNow;

  /// Their place if every match in play ended at its running score.
  final int? rankIfEnded;

  /// Their points now.
  final int pointsNow;

  /// Their points if every match in play ended now.
  final int pointsIfEnded;

  /// Players on the board if every match in play ended now.
  final int players;

  /// The schema version of this payload.
  final int schemaVersion;

  /// The line of [fixtureId], or null when it is not in play.
  LiveFixtureStandingDto? fixture(String fixtureId) {
    for (final LiveFixtureStandingDto f in fixtures) {
      if (f.fixtureId == fixtureId) return f;
    }
    return null;
  }

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'fixtures': [for (final f in fixtures) f.toJson()],
    'duels': [for (final d in duels) d.toJson()],
    'rank_now': rankNow,
    'rank_if_ended': rankIfEnded,
    'points_now': pointsNow,
    'points_if_ended': pointsIfEnded,
    'players': players,
  };
}
