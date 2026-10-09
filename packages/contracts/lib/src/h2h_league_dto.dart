/// Wire shapes of the monthly head-to-head league (migration 0100).
///
/// Every number is server-produced (Axioms 2/5): the client draws the table,
/// the matches and the zones, and never ranks, sums or promotes anyone.
/// Days cross the wire as plain `YYYY-MM-DD` Riyadh dates; instants (a first
/// kickoff) as ISO-8601 UTC.
library;

List<Map<String, Object?>> _maps(Object? raw) => [
  for (final e in (raw as List<Object?>?) ?? const <Object?>[])
    (e! as Map<Object?, Object?>).cast<String, Object?>(),
];

/// One member's line on the group table.
final class H2hStandingDto {
  /// Creates a table line.
  const H2hStandingDto({
    required this.rank,
    required this.userId,
    required this.displayName,
    required this.played,
    required this.won,
    required this.drawn,
    required this.lost,
    required this.leaguePoints,
    required this.pointsFor,
    required this.exactCount,
    required this.form,
    required this.isMe,
    this.avatarUrl,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hStandingDto.fromJson(Map<String, Object?> json) => H2hStandingDto(
    rank: (json['rank'] as int?) ?? 0,
    userId: (json['user_id'] as String?) ?? '',
    displayName: (json['display_name'] as String?) ?? '',
    played: (json['played'] as int?) ?? 0,
    won: (json['won'] as int?) ?? 0,
    drawn: (json['drawn'] as int?) ?? 0,
    lost: (json['lost'] as int?) ?? 0,
    leaguePoints: (json['league_points'] as int?) ?? 0,
    pointsFor: (json['points_for'] as int?) ?? 0,
    exactCount: (json['exact_count'] as int?) ?? 0,
    form: [
      for (final r in (json['form'] as List<Object?>?) ?? const <Object?>[])
        r.toString(),
    ],
    isMe: (json['is_me'] as bool?) ?? false,
    avatarUrl: json['avatar_url'] as String?,
  );

  /// 1-based, distinct.
  final int rank;

  /// The member (UUID string).
  final String userId;

  /// The member's display name, or empty when the server holds none.
  final String displayName;

  /// Rounds played.
  final int played;

  /// Rounds won.
  final int won;

  /// Rounds drawn.
  final int drawn;

  /// Rounds lost.
  final int lost;

  /// Three a win, one a draw.
  final int leaguePoints;

  /// Prediction points over the settled rounds.
  final int pointsFor;

  /// Exact scorelines over the settled rounds.
  final int exactCount;

  /// The last results, oldest first: `win`, `draw` or `loss`.
  final List<String> form;

  /// Whether this line is the caller's own.
  final bool isMe;

  /// The member's picture as a server-relative URL, or null.
  final String? avatarUrl;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'rank': rank,
    'user_id': userId,
    'display_name': displayName,
    'played': played,
    'won': won,
    'drawn': drawn,
    'lost': lost,
    'league_points': leaguePoints,
    'points_for': pointsFor,
    'exact_count': exactCount,
    'form': form,
    'is_me': isMe,
    'avatar_url': avatarUrl,
  };
}

/// One round of the month as the caller plays it.
final class H2hRoundViewDto {
  /// Creates a round view.
  const H2hRoundViewDto({
    required this.round,
    required this.day,
    required this.status,
    required this.fixtureCount,
    this.opponentUserId,
    this.opponentName,
    this.opponentAvatarUrl,
    this.myPoints,
    this.opponentPoints,
    this.result,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hRoundViewDto.fromJson(Map<String, Object?> json) =>
      H2hRoundViewDto(
        round: (json['round'] as int?) ?? 0,
        day: (json['day'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'upcoming',
        fixtureCount: (json['fixture_count'] as int?) ?? 0,
        opponentUserId: json['opponent_user_id'] as String?,
        opponentName: json['opponent_name'] as String?,
        opponentAvatarUrl: json['opponent_avatar_url'] as String?,
        myPoints: json['my_points'] as int?,
        opponentPoints: (json['opponent_points'] as num?)?.toDouble(),
        result: json['result'] as String?,
      );

  /// 1-based round of the month.
  final int round;

  /// The round's Riyadh day, `YYYY-MM-DD`.
  final String day;

  /// `upcoming`, `live`, `settled` or `voided`.
  final String status;

  /// The round's fixtures: frozen once it started.
  final int fixtureCount;

  /// The opponent, or null when the caller plays the group average.
  final String? opponentUserId;

  /// The opponent's display name, or null with the average.
  final String? opponentName;

  /// The opponent's picture, or null.
  final String? opponentAvatarUrl;

  /// The caller's points in the round; null while upcoming or voided.
  final int? myPoints;

  /// The opponent's points, or the group average; null while upcoming.
  final double? opponentPoints;

  /// `win`, `draw` or `loss` so far; null while upcoming or voided.
  final String? result;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'round': round,
    'day': day,
    'status': status,
    'fixture_count': fixtureCount,
    'opponent_user_id': opponentUserId,
    'opponent_name': opponentName,
    'opponent_avatar_url': opponentAvatarUrl,
    'my_points': myPoints,
    'opponent_points': opponentPoints,
    'result': result,
  };
}

/// Response body of `GET /me/h2h-league`.
final class MyH2hLeagueDto {
  /// Creates the reading.
  const MyH2hLeagueDto({
    required this.state,
    required this.monthStart,
    required this.startsOn,
    required this.isPilot,
    required this.myRank,
    required this.promotionZone,
    required this.relegationZone,
    required this.standings,
    required this.rounds,
    this.division,
    this.groupIndex,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating older schema versions.
  factory MyH2hLeagueDto.fromJson(Map<String, Object?> json) => MyH2hLeagueDto(
    schemaVersion: (json['schema_version'] as int?) ?? 1,
    state: (json['state'] as String?) ?? 'not_started',
    monthStart: (json['month_start'] as String?) ?? '',
    startsOn: (json['starts_on'] as String?) ?? '',
    isPilot: (json['is_pilot'] as bool?) ?? false,
    division: json['division'] as int?,
    groupIndex: json['group_index'] as int?,
    myRank: (json['my_rank'] as int?) ?? 0,
    promotionZone: (json['promotion_zone'] as int?) ?? 0,
    relegationZone: (json['relegation_zone'] as int?) ?? 0,
    standings: [
      for (final m in _maps(json['standings'])) H2hStandingDto.fromJson(m),
    ],
    rounds: [
      for (final m in _maps(json['rounds'])) H2hRoundViewDto.fromJson(m),
    ],
  );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// `not_started`, `draw_pending`, `not_in_draw` or `open`.
  final String state;

  /// The month, `YYYY-MM-DD` of its first day.
  final String monthStart;

  /// The day the league opens to everyone, `YYYY-MM-DD`.
  final String startsOn;

  /// Whether the caller plays the hidden pilot month.
  final bool isPilot;

  /// The caller's division 1..4, when open.
  final int? division;

  /// 0-based group of the division, when open.
  final int? groupIndex;

  /// The caller's rank on the table, 0 when not open.
  final int myRank;

  /// Places from the top that go up if the month ended now.
  final int promotionZone;

  /// Places from the bottom that go down if the month ended now.
  final int relegationZone;

  /// The group table over settled rounds, best first.
  final List<H2hStandingDto> standings;

  /// Every approved round of the month, oldest first.
  final List<H2hRoundViewDto> rounds;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'state': state,
    'month_start': monthStart,
    'starts_on': startsOn,
    'is_pilot': isPilot,
    'division': division,
    'group_index': groupIndex,
    'my_rank': myRank,
    'promotion_zone': promotionZone,
    'relegation_zone': relegationZone,
    'standings': [for (final s in standings) s.toJson()],
    'rounds': [for (final r in rounds) r.toJson()],
  };
}

/// One approved round, as an admin sees it.
final class H2hRoundDto {
  /// Creates a round.
  const H2hRoundDto({
    required this.id,
    required this.round,
    required this.day,
    required this.fixtureCount,
    required this.automatic,
    required this.locked,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hRoundDto.fromJson(Map<String, Object?> json) => H2hRoundDto(
    id: (json['id'] as String?) ?? '',
    round: (json['round'] as int?) ?? 0,
    day: (json['day'] as String?) ?? '',
    fixtureCount: (json['fixture_count'] as int?) ?? 0,
    automatic: (json['automatic'] as bool?) ?? false,
    locked: (json['locked'] as bool?) ?? false,
  );

  /// The round's id (UUID string).
  final String id;

  /// 1-based number in the month.
  final int round;

  /// The round's Riyadh day, `YYYY-MM-DD`.
  final String day;

  /// Fixtures of the day (frozen once locked).
  final int fixtureCount;

  /// Whether the system approved it.
  final bool automatic;

  /// Whether its first match kicked off and its list is frozen.
  final bool locked;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'id': id,
    'round': round,
    'day': day,
    'fixture_count': fixtureCount,
    'automatic': automatic,
    'locked': locked,
  };
}

/// A day an admin may approve next.
final class H2hCandidateDayDto {
  /// Creates a candidate.
  const H2hCandidateDayDto({
    required this.day,
    required this.fixtureCount,
    required this.firstKickoff,
    required this.kind,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hCandidateDayDto.fromJson(Map<String, Object?> json) =>
      H2hCandidateDayDto(
        day: (json['day'] as String?) ?? '',
        fixtureCount: (json['fixture_count'] as int?) ?? 0,
        firstKickoff: (json['first_kickoff'] as String?) ?? '',
        kind: (json['kind'] as String?) ?? 'regular',
      );

  /// The Riyadh day, `YYYY-MM-DD`.
  final String day;

  /// Fixtures of the day.
  final int fixtureCount;

  /// The first kickoff, ISO-8601 UTC.
  final String firstKickoff;

  /// `regular` (six or more) or `fill` (five).
  final String kind;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'day': day,
    'fixture_count': fixtureCount,
    'first_kickoff': firstKickoff,
    'kind': kind,
  };
}

/// Response body of `GET /admin/h2h/rounds`.
final class H2hRoundsOverviewDto {
  /// Creates an overview.
  const H2hRoundsOverviewDto({
    required this.monthStart,
    required this.drawn,
    required this.isPilot,
    required this.rounds,
    required this.candidates,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hRoundsOverviewDto.fromJson(
    Map<String, Object?> json,
  ) => H2hRoundsOverviewDto(
    monthStart: (json['month_start'] as String?) ?? '',
    drawn: (json['drawn'] as bool?) ?? false,
    isPilot: (json['is_pilot'] as bool?) ?? false,
    rounds: [for (final m in _maps(json['rounds'])) H2hRoundDto.fromJson(m)],
    candidates: [
      for (final m in _maps(json['candidates'])) H2hCandidateDayDto.fromJson(m),
    ],
  );

  /// The month, `YYYY-MM-DD` of its first day.
  final String monthStart;

  /// Whether the month was drawn.
  final bool drawn;

  /// Whether the drawn month is the pilot.
  final bool isPilot;

  /// The approved rounds, in order.
  final List<H2hRoundDto> rounds;

  /// The days that may become the next round, in date order.
  final List<H2hCandidateDayDto> candidates;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'month_start': monthStart,
    'drawn': drawn,
    'is_pilot': isPilot,
    'rounds': [for (final r in rounds) r.toJson()],
    'candidates': [for (final c in candidates) c.toJson()],
  };
}

/// Request body of `POST /admin/h2h/rounds`: `{"day": "YYYY-MM-DD"}`.
final class H2hApproveRoundRequestDto {
  /// Creates a request.
  const H2hApproveRoundRequestDto({required this.day});

  /// Deserializes from a JSON map; a missing day is an empty string.
  factory H2hApproveRoundRequestDto.fromJson(Map<String, Object?> json) =>
      H2hApproveRoundRequestDto(day: (json['day'] as String?) ?? '');

  /// The Riyadh day to approve, `YYYY-MM-DD`.
  final String day;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {'day': day};
}

/// Response body of `POST /admin/h2h/pilot`.
final class H2hPilotStartedDto {
  /// Creates a result.
  const H2hPilotStartedDto({required this.seated});

  /// Deserializes from a JSON map.
  factory H2hPilotStartedDto.fromJson(Map<String, Object?> json) =>
      H2hPilotStartedDto(seated: (json['seated'] as int?) ?? 0);

  /// Seats the pilot draw handed out.
  final int seated;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {'seated': seated};
}
