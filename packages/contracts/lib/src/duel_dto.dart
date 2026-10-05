/// Body of `POST /duels/challenges`: the fixture to challenge on, and an
/// optional private target. A private challenge has capacity one.
final class CreateDuelChallengeRequestDto {
  /// Creates the request.
  const CreateDuelChallengeRequestDto({
    required this.seasonId,
    required this.fixtureId,
    this.capacity,
    this.targetUserId,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory CreateDuelChallengeRequestDto.fromJson(
    Map<String, Object?> json,
  ) => CreateDuelChallengeRequestDto(
    schemaVersion: (json['schema_version'] as int?) ?? 1,
    seasonId: json['season_id'] is String ? json['season_id'] as String : '',
    fixtureId: json['fixture_id'] is String ? json['fixture_id'] as String : '',
    capacity: json['capacity'] is int ? json['capacity'] as int : null,
    targetUserId: json['target_user_id'] is String
        ? json['target_user_id'] as String
        : null,
  );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The season the fixture belongs to.
  final String seasonId;

  /// The fixture to challenge on.
  final String fixtureId;

  /// Seats for an open challenge; omitted means the server default.
  final int? capacity;

  /// The invited player for a private challenge.
  final String? targetUserId;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'season_id': seasonId,
    'fixture_id': fixtureId,
    if (capacity != null) 'capacity': capacity,
    if (targetUserId != null) 'target_user_id': targetUserId,
  };
}

/// Body of `POST /duels/challenges/{id}/accept`: the accepting player's own
/// prediction, saved through the ordinary prediction path first.
final class AcceptDuelChallengeRequestDto {
  /// Creates the request.
  const AcceptDuelChallengeRequestDto({
    required this.homeGoals,
    required this.awayGoals,
    this.isDouble = false,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory AcceptDuelChallengeRequestDto.fromJson(Map<String, Object?> json) =>
      AcceptDuelChallengeRequestDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        homeGoals: json['home_goals'] is int ? json['home_goals'] as int : 0,
        awayGoals: json['away_goals'] is int ? json['away_goals'] as int : 0,
        isDouble: json['is_double'] == true,
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// Predicted home goals.
  final int homeGoals;

  /// Predicted away goals.
  final int awayGoals;

  /// Whether this prediction is the day's double.
  final bool isDouble;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'home_goals': homeGoals,
    'away_goals': awayGoals,
    'is_double': isDouble,
  };
}

/// A challenge as the caller sees it (`POST /duels/challenges`,
/// `GET /duels/codes/{code}`, and each entry of `GET /me/duels`).
///
/// [state] is one of `open`, `full`, `expired`, `cancelled`, `declined`.
final class DuelChallengeDto {
  /// Creates the challenge.
  const DuelChallengeDto({
    required this.id,
    required this.code,
    required this.seasonId,
    required this.fixtureId,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
    required this.challengerUserId,
    required this.challengerName,
    required this.isPrivate,
    required this.capacity,
    required this.acceptedCount,
    required this.state,
    required this.isMine,
    required this.isForMe,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory DuelChallengeDto.fromJson(Map<String, Object?> json) =>
      DuelChallengeDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        id: (json['id'] as String?) ?? '',
        code: (json['code'] as String?) ?? '',
        seasonId: (json['season_id'] as String?) ?? '',
        fixtureId: (json['fixture_id'] as String?) ?? '',
        homeTeam: (json['home_team'] as String?) ?? '',
        awayTeam: (json['away_team'] as String?) ?? '',
        kickoffAt: (json['kickoff_at'] as String?) ?? '',
        challengerUserId: (json['challenger_user_id'] as String?) ?? '',
        challengerName: (json['challenger_name'] as String?) ?? '',
        isPrivate: (json['is_private'] as bool?) ?? false,
        capacity: (json['capacity'] as int?) ?? 0,
        acceptedCount: (json['accepted_count'] as int?) ?? 0,
        state: (json['state'] as String?) ?? '',
        isMine: (json['is_mine'] as bool?) ?? false,
        isForMe: (json['is_for_me'] as bool?) ?? false,
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// Challenge id, used to accept, cancel or decline.
  final String id;

  /// Share code for the link.
  final String code;

  /// Season of the fixture.
  final String seasonId;

  /// The fixture.
  final String fixtureId;

  /// Home side name.
  final String homeTeam;

  /// Away side name.
  final String awayTeam;

  /// Kickoff, ISO-8601 UTC.
  final String kickoffAt;

  /// The challenger's account id.
  final String challengerUserId;

  /// The challenger's display name.
  final String challengerName;

  /// Whether it is reserved for one invited player.
  final bool isPrivate;

  /// Seats in total.
  final int capacity;

  /// Seats taken.
  final int acceptedCount;

  /// Derived state at the time of the answer.
  final String state;

  /// Whether the caller created it.
  final bool isMine;

  /// Whether the caller is its private target.
  final bool isForMe;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'id': id,
    'code': code,
    'season_id': seasonId,
    'fixture_id': fixtureId,
    'home_team': homeTeam,
    'away_team': awayTeam,
    'kickoff_at': kickoffAt,
    'challenger_user_id': challengerUserId,
    'challenger_name': challengerName,
    'is_private': isPrivate,
    'capacity': capacity,
    'accepted_count': acceptedCount,
    'state': state,
    'is_mine': isMine,
    'is_for_me': isForMe,
  };
}

/// The duel created by `POST /duels/challenges/{id}/accept`.
final class DuelDto {
  /// Creates the duel.
  const DuelDto({
    required this.id,
    required this.challengeId,
    required this.fixtureId,
    required this.acceptedAt,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory DuelDto.fromJson(Map<String, Object?> json) => DuelDto(
    schemaVersion: (json['schema_version'] as int?) ?? 1,
    id: (json['id'] as String?) ?? '',
    challengeId: (json['challenge_id'] as String?) ?? '',
    fixtureId: (json['fixture_id'] as String?) ?? '',
    acceptedAt: (json['accepted_at'] as String?) ?? '',
  );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// Duel id.
  final String id;

  /// The challenge it came from.
  final String challengeId;

  /// The fixture.
  final String fixtureId;

  /// Acceptance instant, ISO-8601 UTC.
  final String acceptedAt;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'id': id,
    'challenge_id': challengeId,
    'fixture_id': fixtureId,
    'accepted_at': acceptedAt,
  };
}

/// One duel in `GET /me/duels`, from the caller's side.
///
/// The opponent's goals are null before kickoff. Points and [outcome]
/// (`won`, `lost`, `draw`) are null until both official scores are final.
/// [state] is one of `upcoming`, `live`, `settled`.
final class DuelSummaryDto {
  /// Creates the summary.
  const DuelSummaryDto({
    required this.id,
    required this.challengeId,
    required this.fixtureId,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
    required this.acceptedAt,
    required this.isChallenger,
    required this.opponentUserId,
    required this.opponentName,
    required this.myIsDouble,
    required this.state,
    this.myHomeGoals,
    this.myAwayGoals,
    this.opponentHomeGoals,
    this.opponentAwayGoals,
    this.opponentIsDouble,
    this.myPoints,
    this.opponentPoints,
    this.outcome,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory DuelSummaryDto.fromJson(Map<String, Object?> json) => DuelSummaryDto(
    schemaVersion: (json['schema_version'] as int?) ?? 1,
    id: (json['id'] as String?) ?? '',
    challengeId: (json['challenge_id'] as String?) ?? '',
    fixtureId: (json['fixture_id'] as String?) ?? '',
    homeTeam: (json['home_team'] as String?) ?? '',
    awayTeam: (json['away_team'] as String?) ?? '',
    kickoffAt: (json['kickoff_at'] as String?) ?? '',
    acceptedAt: (json['accepted_at'] as String?) ?? '',
    isChallenger: (json['is_challenger'] as bool?) ?? false,
    opponentUserId: (json['opponent_user_id'] as String?) ?? '',
    opponentName: (json['opponent_name'] as String?) ?? '',
    myHomeGoals: json['my_home_goals'] as int?,
    myAwayGoals: json['my_away_goals'] as int?,
    myIsDouble: (json['my_is_double'] as bool?) ?? false,
    opponentHomeGoals: json['opponent_home_goals'] as int?,
    opponentAwayGoals: json['opponent_away_goals'] as int?,
    opponentIsDouble: json['opponent_is_double'] as bool?,
    state: (json['state'] as String?) ?? '',
    myPoints: json['my_points'] as int?,
    opponentPoints: json['opponent_points'] as int?,
    outcome: json['outcome'] as String?,
  );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// Duel id.
  final String id;

  /// The challenge it came from.
  final String challengeId;

  /// The fixture.
  final String fixtureId;

  /// Home side name.
  final String homeTeam;

  /// Away side name.
  final String awayTeam;

  /// Kickoff, ISO-8601 UTC.
  final String kickoffAt;

  /// Acceptance instant, ISO-8601 UTC.
  final String acceptedAt;

  /// Whether the caller created the challenge.
  final bool isChallenger;

  /// The opponent's account id.
  final String opponentUserId;

  /// The opponent's display name.
  final String opponentName;

  /// The caller's predicted home goals.
  final int? myHomeGoals;

  /// The caller's predicted away goals.
  final int? myAwayGoals;

  /// Whether the caller's prediction is the day's double.
  final bool myIsDouble;

  /// The opponent's predicted home goals, null before kickoff.
  final int? opponentHomeGoals;

  /// The opponent's predicted away goals, null before kickoff.
  final int? opponentAwayGoals;

  /// Whether the opponent's prediction is a double, null before kickoff.
  final bool? opponentIsDouble;

  /// Where the duel stands.
  final String state;

  /// The caller's official points, null until settled.
  final int? myPoints;

  /// The opponent's official points, null until settled.
  final int? opponentPoints;

  /// The result for the caller, null until settled.
  final String? outcome;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'id': id,
    'challenge_id': challengeId,
    'fixture_id': fixtureId,
    'home_team': homeTeam,
    'away_team': awayTeam,
    'kickoff_at': kickoffAt,
    'accepted_at': acceptedAt,
    'is_challenger': isChallenger,
    'opponent_user_id': opponentUserId,
    'opponent_name': opponentName,
    'my_home_goals': myHomeGoals,
    'my_away_goals': myAwayGoals,
    'my_is_double': myIsDouble,
    'opponent_home_goals': opponentHomeGoals,
    'opponent_away_goals': opponentAwayGoals,
    'opponent_is_double': opponentIsDouble,
    'state': state,
    'my_points': myPoints,
    'opponent_points': opponentPoints,
    'outcome': outcome,
  };
}

/// Body of `GET /me/duels`.
final class MyDuelsDto {
  /// Creates the answer.
  const MyDuelsDto({
    required this.challenges,
    required this.duels,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory MyDuelsDto.fromJson(Map<String, Object?> json) => MyDuelsDto(
    schemaVersion: (json['schema_version'] as int?) ?? 1,
    challenges: [
      for (final item in (json['challenges'] as List<Object?>?) ?? const [])
        if (item is Map<String, Object?>) DuelChallengeDto.fromJson(item),
    ],
    duels: [
      for (final item in (json['duels'] as List<Object?>?) ?? const [])
        if (item is Map<String, Object?>) DuelSummaryDto.fromJson(item),
    ],
  );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// Open challenges the caller created or was invited to privately.
  final List<DuelChallengeDto> challenges;

  /// The caller's duels, newest kickoff first.
  final List<DuelSummaryDto> duels;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'challenges': [for (final c in challenges) c.toJson()],
    'duels': [for (final d in duels) d.toJson()],
  };
}

/// One player who can be challenged by name (`GET /duels/players`).
final class DuelPlayerDto {
  /// Creates the entry.
  const DuelPlayerDto({required this.userId, required this.displayName});

  /// Deserializes from a JSON map, tolerating missing keys.
  factory DuelPlayerDto.fromJson(Map<String, Object?> json) => DuelPlayerDto(
    userId: json['user_id'] is String ? json['user_id'] as String : '',
    displayName: json['display_name'] is String
        ? json['display_name'] as String
        : '',
  );

  /// The account a private challenge targets.
  final String userId;

  /// The player's display name.
  final String displayName;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'user_id': userId,
    'display_name': displayName,
  };
}

/// Body of `GET /duels/players?q=NAME` (migration 0092).
final class DuelPlayersDto {
  /// Creates the answer.
  const DuelPlayersDto({
    required this.players,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory DuelPlayersDto.fromJson(Map<String, Object?> json) => DuelPlayersDto(
    schemaVersion: (json['schema_version'] as int?) ?? 1,
    players: [
      for (final item in (json['players'] as List<Object?>?) ?? const [])
        if (item is Map<String, Object?>) DuelPlayerDto.fromJson(item),
    ],
  );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// Matching players, exact name first; never the caller.
  final List<DuelPlayerDto> players;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'players': [for (final p in players) p.toJson()],
  };
}
