/// A player's points in one month for the admin's "سجل النقاط" (batch
/// 146b, `GET /admin/users/{id}/points?season=`): every movement of the
/// fixture ledger with its match's sides, the month's points as its board
/// counts them, and the streak bonuses, which count in the weekly league
/// only.
library;

/// One movement of a player's points.
final class PlayerPointEntryDto {
  /// Creates the movement.
  const PlayerPointEntryDto({
    required this.id,
    required this.fixtureId,
    required this.kind,
    required this.amount,
    required this.occurredAt,
    this.homeTeam,
    this.awayTeam,
  });

  /// Deserializes from a JSON map.
  factory PlayerPointEntryDto.fromJson(Map<String, Object?> json) =>
      PlayerPointEntryDto(
        id: json['id']! as String,
        fixtureId: json['fixture_id']! as String,
        homeTeam: json['home_team'] as String?,
        awayTeam: json['away_team'] as String?,
        kind: json['kind']! as String,
        amount: json['amount']! as int,
        occurredAt: json['occurred_at']! as String,
      );

  /// The ledger entry's id.
  final String id;

  /// The match it belongs to.
  final String fixtureId;

  /// The home side, when on file.
  final String? homeTeam;

  /// The away side, when on file.
  final String? awayTeam;

  /// `fixture_score`, `correction` or `streak_bonus`.
  final String kind;

  /// The points it moved (a correction may be negative).
  final int amount;

  /// When it was written, ISO-8601 UTC.
  final String occurredAt;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'id': id,
    'fixture_id': fixtureId,
    'home_team': homeTeam,
    'away_team': awayTeam,
    'kind': kind,
    'amount': amount,
    'occurred_at': occurredAt,
  };
}

/// A player's month.
final class PlayerMonthPointsDto {
  /// Creates the month.
  const PlayerMonthPointsDto({
    required this.played,
    required this.monthPoints,
    required this.streakBonus,
    required this.entries,
  });

  /// Deserializes from a JSON map.
  factory PlayerMonthPointsDto.fromJson(Map<String, Object?> json) {
    final Object? raw = json['entries'];
    return PlayerMonthPointsDto(
      played: json['played'] == true,
      monthPoints: json['month_points']! as int,
      streakBonus: json['streak_bonus']! as int,
      entries: <PlayerPointEntryDto>[
        if (raw is List<Object?>)
          for (final Object? e in raw)
            if (e is Map<String, Object?>) PlayerPointEntryDto.fromJson(e),
      ],
    );
  }

  /// Whether the player played in the month at all.
  final bool played;

  /// The month's points as its board counts them.
  final int monthPoints;

  /// The streak bonuses (the weekly league only).
  final int streakBonus;

  /// The movements, oldest first.
  final List<PlayerPointEntryDto> entries;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': 1,
    'played': played,
    'month_points': monthPoints,
    'streak_bonus': streakBonus,
    'entries': [for (final PlayerPointEntryDto e in entries) e.toJson()],
  };
}
