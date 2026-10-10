/// Wire shapes of every match of one round in the caller's head-to-head
/// group (`GET /me/h2h-league/rounds/{n}/matches`, migration 0100).
///
/// Every number is server-produced (Axioms 2/5). No prediction of anybody
/// crosses this wire: only the pairs, the stored points of each side (which
/// exist only for fixtures already played) and which side the round shows
/// ahead. While a round is live that is by points alone, never by whether a
/// player has predicted.
library;

List<Map<String, Object?>> _maps(Object? raw) => [
  for (final e in (raw as List<Object?>?) ?? const <Object?>[])
    (e! as Map<Object?, Object?>).cast<String, Object?>(),
];

/// One match of the round: two members, or a member against the group
/// average when the opposite seat is empty.
final class H2hGroupMatchDto {
  /// Creates a match.
  const H2hGroupMatchDto({
    required this.homeUserId,
    required this.homeName,
    this.homeAvatarUrl,
    this.homeIsMe = false,
    this.homePoints,
    this.awayUserId,
    this.awayName,
    this.awayAvatarUrl,
    this.awayIsMe = false,
    this.awayPoints,
    this.winner,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hGroupMatchDto.fromJson(Map<String, Object?> json) =>
      H2hGroupMatchDto(
        homeUserId: (json['home_user_id'] as String?) ?? '',
        homeName: (json['home_name'] as String?) ?? '',
        homeAvatarUrl: json['home_avatar_url'] as String?,
        homeIsMe: (json['home_is_me'] as bool?) ?? false,
        homePoints: json['home_points'] as int?,
        awayUserId: json['away_user_id'] as String?,
        awayName: json['away_name'] as String?,
        awayAvatarUrl: json['away_avatar_url'] as String?,
        awayIsMe: (json['away_is_me'] as bool?) ?? false,
        awayPoints: (json['away_points'] as num?)?.toDouble(),
        winner: json['winner'] as String?,
      );

  /// The first member (the caller, when the caller plays this match).
  final String homeUserId;

  /// The first member's display name.
  final String homeName;

  /// The first member's picture, or null.
  final String? homeAvatarUrl;

  /// Whether the first member is the caller.
  final bool homeIsMe;

  /// The first member's points in the round; null before it starts and
  /// when it is void.
  final int? homePoints;

  /// The second member, or null when the first plays the group average.
  final String? awayUserId;

  /// The second member's display name; null with the group average.
  final String? awayName;

  /// The second member's picture, or null.
  final String? awayAvatarUrl;

  /// Whether the second member is the caller.
  final bool awayIsMe;

  /// The second member's points, or the group average; null as
  /// [homePoints] is.
  final double? awayPoints;

  /// `home`, `away` or `draw`: who the round shows ahead (final once it is
  /// settled, so far while live, by points alone); `none` for a settled
  /// round both members lost; null before it starts and when void.
  final String? winner;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'home_user_id': homeUserId,
    'home_name': homeName,
    'home_avatar_url': homeAvatarUrl,
    'home_is_me': homeIsMe,
    'home_points': homePoints,
    'away_user_id': awayUserId,
    'away_name': awayName,
    'away_avatar_url': awayAvatarUrl,
    'away_is_me': awayIsMe,
    'away_points': awayPoints,
    'winner': winner,
  };
}

/// Response body of `GET /me/h2h-league/rounds/{n}/matches`.
final class H2hGroupRoundDto {
  /// Creates the reading.
  const H2hGroupRoundDto({
    required this.round,
    required this.day,
    required this.status,
    required this.matches,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating older schema versions.
  factory H2hGroupRoundDto.fromJson(Map<String, Object?> json) =>
      H2hGroupRoundDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        round: (json['round'] as int?) ?? 0,
        day: (json['day'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'upcoming',
        matches: [
          for (final m in _maps(json['matches'])) H2hGroupMatchDto.fromJson(m),
        ],
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// 1-based round of the month.
  final int round;

  /// The round's Riyadh day, `YYYY-MM-DD`.
  final String day;

  /// `open`, `upcoming`, `live`, `settled` or `voided`.
  final String status;

  /// Every match of the round in the caller's group, the caller's first.
  final List<H2hGroupMatchDto> matches;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'round': round,
    'day': day,
    'status': status,
    'matches': [for (final m in matches) m.toJson()],
  };
}
