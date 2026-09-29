/// The champions of the monthly contests (migration 0077): the list every
/// player reads, the admin's crowning preview and the crowning command.
library;

/// One crowned champion, as `GET /champions` lists them.
final class MonthChampionDto {
  /// Creates the row.
  const MonthChampionDto({
    required this.seasonId,
    required this.seasonLabel,
    required this.userId,
    required this.displayName,
    required this.points,
    required this.exactCount,
    required this.decidedCount,
    required this.referralPoints,
    required this.crownedAt,
    required this.celebrateUntil,
    this.photoUrl,
    this.avatarUrl,
    this.prize,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory MonthChampionDto.fromJson(Map<String, Object?> json) =>
      MonthChampionDto(
        seasonId: (json['season_id'] as String?) ?? '',
        seasonLabel: (json['season_label'] as String?) ?? '',
        userId: (json['user_id'] as String?) ?? '',
        displayName: (json['display_name'] as String?) ?? '',
        points: (json['points'] as int?) ?? 0,
        exactCount: (json['exact_count'] as int?) ?? 0,
        decidedCount: (json['decided_count'] as int?) ?? 0,
        referralPoints: (json['referral_points'] as int?) ?? 0,
        crownedAt: (json['crowned_at'] as String?) ?? '',
        celebrateUntil: (json['celebrate_until'] as String?) ?? '',
        photoUrl: json['photo_url'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        prize: json['prize'] as String?,
      );

  /// The month.
  final String seasonId;

  /// Its label (`09/2026`).
  final String seasonLabel;

  /// The champion.
  final String userId;

  /// The champion's display name.
  final String displayName;

  /// Prediction points on the final board.
  final int points;

  /// Exact scorelines.
  final int exactCount;

  /// Decided fixtures (the accuracy's denominator).
  final int decidedCount;

  /// The month's invitation points (a tie-break only).
  final int referralPoints;

  /// When the month was crowned (ISO-8601 UTC).
  final String crownedAt;

  /// Until when the celebration is shown (ISO-8601 UTC).
  final String celebrateUntil;

  /// The celebration picture (server-relative), or null without one.
  final String? photoUrl;

  /// The champion's own profile picture (server-relative), or null.
  final String? avatarUrl;

  /// What the champion wins ("150 ريال سعودي"), or null without one.
  final String? prize;

  /// Exact scorelines over decided fixtures, rounded, or null when nothing
  /// was decided -- the same accuracy the boards show.
  int? get accuracyPercent =>
      decidedCount <= 0 ? null : (exactCount * 100 / decidedCount).round();

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'season_id': seasonId,
    'season_label': seasonLabel,
    'user_id': userId,
    'display_name': displayName,
    'points': points,
    'exact_count': exactCount,
    'decided_count': decidedCount,
    'referral_points': referralPoints,
    'crowned_at': crownedAt,
    'celebrate_until': celebrateUntil,
    if (photoUrl != null) 'photo_url': photoUrl,
    if (avatarUrl != null) 'avatar_url': avatarUrl,
    if (prize != null) 'prize': prize,
  };
}

/// `GET /champions`: every crowned champion, newest crowning first.
final class MonthChampionsDto {
  /// Creates the list.
  const MonthChampionsDto({
    required this.champions,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory MonthChampionsDto.fromJson(Map<String, Object?> json) =>
      MonthChampionsDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        champions: [
          for (final Object? c in (json['champions'] as List<Object?>?) ?? [])
            if (c is Map<String, Object?>) MonthChampionDto.fromJson(c),
        ],
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The champions, newest crowning first.
  final List<MonthChampionDto> champions;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'champions': [for (final MonthChampionDto c in champions) c.toJson()],
  };
}

/// One line of a month's final board in the admin's crowning preview.
final class ChampionCandidateDto {
  /// Creates the line.
  const ChampionCandidateDto({
    required this.rank,
    required this.userId,
    required this.displayName,
    required this.points,
    required this.exactCount,
    required this.decidedCount,
    required this.referralPoints,
    this.avatarUrl,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory ChampionCandidateDto.fromJson(Map<String, Object?> json) =>
      ChampionCandidateDto(
        rank: (json['rank'] as int?) ?? 0,
        userId: (json['user_id'] as String?) ?? '',
        displayName: (json['display_name'] as String?) ?? '',
        points: (json['points'] as int?) ?? 0,
        exactCount: (json['exact_count'] as int?) ?? 0,
        decidedCount: (json['decided_count'] as int?) ?? 0,
        referralPoints: (json['referral_points'] as int?) ?? 0,
        avatarUrl: json['avatar_url'] as String?,
      );

  /// The place on the final board (level players share it).
  final int rank;

  /// The player.
  final String userId;

  /// The player's display name.
  final String displayName;

  /// Prediction points.
  final int points;

  /// Exact scorelines.
  final int exactCount;

  /// Decided fixtures.
  final int decidedCount;

  /// The month's invitation points.
  final int referralPoints;

  /// The player's profile picture (server-relative), or null.
  final String? avatarUrl;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'rank': rank,
    'user_id': userId,
    'display_name': displayName,
    'points': points,
    'exact_count': exactCount,
    'decided_count': decidedCount,
    'referral_points': referralPoints,
    if (avatarUrl != null) 'avatar_url': avatarUrl,
  };
}

/// `GET /admin/champions/{seasonId}`: what the admin sees before crowning.
final class ChampionCandidatesDto {
  /// Creates the preview.
  const ChampionCandidatesDto({
    required this.seasonId,
    required this.seasonLabel,
    required this.ended,
    required this.unscoredFixtures,
    required this.crowned,
    required this.candidates,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory ChampionCandidatesDto.fromJson(Map<String, Object?> json) =>
      ChampionCandidatesDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        seasonId: (json['season_id'] as String?) ?? '',
        seasonLabel: (json['season_label'] as String?) ?? '',
        ended: (json['ended'] as bool?) ?? false,
        unscoredFixtures: (json['unscored_fixtures'] as int?) ?? 0,
        crowned: [
          for (final Object? id in (json['crowned'] as List<Object?>?) ?? [])
            if (id is String) id,
        ],
        candidates: [
          for (final Object? c in (json['candidates'] as List<Object?>?) ?? [])
            if (c is Map<String, Object?>) ChampionCandidateDto.fromJson(c),
        ],
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The month.
  final String seasonId;

  /// Its label (`09/2026`).
  final String seasonLabel;

  /// Whether the month is over.
  final bool ended;

  /// How many of its fixtures still have no result.
  final int unscoredFixtures;

  /// The players already crowned (empty until the month is crowned).
  final List<String> crowned;

  /// The top of the final board; everyone ranked first is included.
  final List<ChampionCandidateDto> candidates;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'season_id': seasonId,
    'season_label': seasonLabel,
    'ended': ended,
    'unscored_fixtures': unscoredFixtures,
    'crowned': crowned,
    'candidates': [for (final ChampionCandidateDto c in candidates) c.toJson()],
  };
}

/// The body of `POST /admin/champions/{seasonId}`: the one or two players to
/// crown, whether to crown although some fixture has no result yet, and the
/// prize the champion wins.
final class CrownChampionsDto {
  /// Creates the body.
  const CrownChampionsDto({
    required this.userIds,
    this.force = false,
    this.prize,
  });

  /// The prize text, or null when the field is missing or not a string.
  static String? prizeOf(Map<String, Object?> json) {
    final Object? raw = json['prize'];
    return raw is String ? raw : null;
  }

  /// The chosen players, or null when the field is missing or is not a list
  /// of strings -- the use-case then refuses it rather than guessing.
  static List<String>? userIdsOf(Map<String, Object?> json) {
    final Object? raw = json['user_ids'];
    if (raw is! List<Object?>) {
      return null;
    }
    final out = <String>[];
    for (final Object? id in raw) {
      if (id is! String) {
        return null;
      }
      out.add(id);
    }
    return out;
  }

  /// Whether the admin confirmed crowning with unscored fixtures; anything
  /// but `true` reads as no.
  static bool forceOf(Map<String, Object?> json) => json['force'] == true;

  /// The chosen players.
  final List<String> userIds;

  /// Crown although some fixture has no result yet.
  final bool force;

  /// What the champion wins, or null for none.
  final String? prize;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'user_ids': userIds,
    'force': force,
    if (prize != null) 'prize': prize,
  };
}
