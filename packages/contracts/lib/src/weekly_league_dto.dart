/// One member's line on the weekly-league table (P2-4).
///
/// Keys the member by user id and carries the [displayName] and
/// [avatarUrl] the server resolved for the row (P2-7b): the table is a
/// projection of the server's ranking, and the client never orders, sums
/// or promotes anyone (Axioms 2/5). [rank] is 1-based and distinct -- the
/// tie-break chain is a total order, so no two members share a place.
/// Versioned through the enclosing [MyWeeklyLeagueDto].
final class WeeklyLeagueEntryDto {
  /// Creates a table line.
  const WeeklyLeagueEntryDto({
    required this.rank,
    required this.userId,
    required this.displayName,
    required this.points,
    required this.exactCount,
    required this.decidedCount,
    required this.projectedOutcome,
    required this.isMe,
    this.avatarUrl,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory WeeklyLeagueEntryDto.fromJson(Map<String, Object?> json) {
    return WeeklyLeagueEntryDto(
      rank: (json['rank'] as int?) ?? 0,
      userId: (json['user_id'] as String?) ?? '',
      displayName: (json['display_name'] as String?) ?? '',
      points: (json['points'] as int?) ?? 0,
      exactCount: (json['exact_count'] as int?) ?? 0,
      decidedCount: (json['decided_count'] as int?) ?? 0,
      projectedOutcome: (json['projected_outcome'] as String?) ?? 'held',
      isMe: (json['is_me'] as bool?) ?? false,
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  /// The member's 1-based place in the group.
  final int rank;

  /// The platform user this line belongs to (UUID string).
  final String userId;

  /// The platform-owned display name of the member, or an empty string when
  /// the server holds no profile for them (the client then draws its own
  /// neutral label). Part of the payload from its first version, so no
  /// reader meets a version-1 body without it.
  final String displayName;

  /// Points earned inside the week: scored fixture points plus streak
  /// bonuses.
  final int points;

  /// Exact scorelines called right inside the week.
  final int exactCount;

  /// Fixtures of the week decided for this member.
  final int decidedCount;

  /// What the week would do to this member if it closed now: `promoted`,
  /// `held` or `relegated`. The server applies every rule, including that a
  /// member who scored nothing is never promoted; the client only draws it.
  final String projectedOutcome;

  /// Whether this line is the caller's own.
  final bool isMe;

  /// The member's profile picture, as a **server-relative** URL, or null
  /// when they have none. Relative because the server sits behind a proxy
  /// and does not know its own public origin; the client resolves it
  /// against the API base it used for this very request. The `v` query
  /// parameter is the picture's version, so a replaced picture is a
  /// different URL and no device keeps serving the old bytes.
  final String? avatarUrl;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'rank': rank,
    'user_id': userId,
    'display_name': displayName,
    'points': points,
    'exact_count': exactCount,
    'decided_count': decidedCount,
    'projected_outcome': projectedOutcome,
    'is_me': isMe,
    'avatar_url': avatarUrl,
  };

  @override
  bool operator ==(Object other) =>
      other is WeeklyLeagueEntryDto &&
      other.rank == rank &&
      other.userId == userId &&
      other.displayName == displayName &&
      other.points == points &&
      other.exactCount == exactCount &&
      other.decidedCount == decidedCount &&
      other.projectedOutcome == projectedOutcome &&
      other.isMe == isMe &&
      other.avatarUrl == avatarUrl;

  @override
  int get hashCode => Object.hash(
    rank,
    userId,
    displayName,
    points,
    exactCount,
    decidedCount,
    projectedOutcome,
    isMe,
    avatarUrl,
  );
}

/// Response body of `GET /me/weekly-league`.
///
/// The caller's own group for the Riyadh week that is open now, ranked. Tier
/// names are not carried: [tier] is the plain number 1..5 and the mobile
/// l10n names the rung, so renaming a tier never touches the wire.
///
/// Computed on every request from the same points the monthly board reads;
/// nothing weekly is stored, so there is no cached standing to go stale.
final class MyWeeklyLeagueDto {
  /// Creates the reading.
  const MyWeeklyLeagueDto({
    required this.weekStart,
    required this.weekEnd,
    required this.tier,
    required this.groupIndex,
    required this.myRank,
    required this.promotionZone,
    required this.relegationZone,
    required this.entries,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating older schema versions.
  factory MyWeeklyLeagueDto.fromJson(Map<String, Object?> json) {
    final raw = (json['entries'] as List<Object?>?) ?? const <Object?>[];
    return MyWeeklyLeagueDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      weekStart: (json['week_start'] as String?) ?? '',
      weekEnd: (json['week_end'] as String?) ?? '',
      tier: (json['tier'] as int?) ?? 1,
      groupIndex: (json['group_index'] as int?) ?? 0,
      myRank: (json['my_rank'] as int?) ?? 0,
      promotionZone: (json['promotion_zone'] as int?) ?? 0,
      relegationZone: (json['relegation_zone'] as int?) ?? 0,
      entries: raw
          .map(
            (e) => WeeklyLeagueEntryDto.fromJson(
              (e! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The Monday that opens the week, as `YYYY-MM-DD` (Riyadh).
  ///
  /// A plain date, not a timestamp: the week boundary is the server's, and
  /// an instant would invite the client to re-derive it in its own zone.
  final String weekStart;

  /// The Sunday that closes the week (inclusive), as `YYYY-MM-DD` (Riyadh).
  final String weekEnd;

  /// The tier the group plays in, 1 (lowest) to 5 (highest).
  final int tier;

  /// 0-based position of the group among the groups of its tier and week.
  final int groupIndex;

  /// The caller's 1-based rank in [entries].
  final int myRank;

  /// How many places from the top move up. Zero in the top tier and in a
  /// group too small to move anyone.
  final int promotionZone;

  /// How many places from the bottom move down. Zero in the bottom tier and
  /// in a group too small to move anyone.
  final int relegationZone;

  /// Every member, best first.
  final List<WeeklyLeagueEntryDto> entries;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'week_start': weekStart,
    'week_end': weekEnd,
    'tier': tier,
    'group_index': groupIndex,
    'my_rank': myRank,
    'promotion_zone': promotionZone,
    'relegation_zone': relegationZone,
    'entries': [for (final e in entries) e.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is MyWeeklyLeagueDto &&
      other.weekStart == weekStart &&
      other.weekEnd == weekEnd &&
      other.tier == tier &&
      other.groupIndex == groupIndex &&
      other.myRank == myRank &&
      other.promotionZone == promotionZone &&
      other.relegationZone == relegationZone &&
      _listEquals(other.entries, entries) &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    weekStart,
    weekEnd,
    tier,
    groupIndex,
    myRank,
    promotionZone,
    relegationZone,
    Object.hashAll(entries),
    schemaVersion,
  );

  static bool _listEquals(
    List<WeeklyLeagueEntryDto> a,
    List<WeeklyLeagueEntryDto> b,
  ) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
