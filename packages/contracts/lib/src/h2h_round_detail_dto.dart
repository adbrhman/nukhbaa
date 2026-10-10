/// Wire shapes of one head-to-head round in detail
/// (`GET /me/h2h-league/rounds/{n}`, migration 0100).
///
/// Every number is server-produced (Axioms 2/5). The opponent's side is the
/// server's to reveal: a pick of theirs arrives only once that fixture has
/// kicked off (the same lock that closes predictions, `FixtureLock` against
/// the server clock); until then [H2hRoundFixtureDto.theirs] is null and
/// [H2hRoundFixtureDto.theirsHidden] is true. The opponent's counts are
/// over kicked-off fixtures only, for the same reason.
library;

List<Map<String, Object?>> _maps(Object? raw) => [
  for (final e in (raw as List<Object?>?) ?? const <Object?>[])
    (e! as Map<Object?, Object?>).cast<String, Object?>(),
];

Map<String, Object?>? _map(Object? raw) =>
    raw == null ? null : (raw as Map<Object?, Object?>).cast<String, Object?>();

/// One player's prediction for one fixture of the round.
final class H2hPickDto {
  /// Creates a pick.
  const H2hPickDto({
    required this.homeGoals,
    required this.awayGoals,
    required this.isDouble,
    this.points,
    this.exact = false,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hPickDto.fromJson(Map<String, Object?> json) => H2hPickDto(
    homeGoals: (json['home_goals'] as int?) ?? 0,
    awayGoals: (json['away_goals'] as int?) ?? 0,
    isDouble: (json['is_double'] as bool?) ?? false,
    points: json['points'] as int?,
    exact: (json['exact'] as bool?) ?? false,
  );

  /// The predicted home goals.
  final int homeGoals;

  /// The predicted away goals.
  final int awayGoals;

  /// Whether the player doubled this fixture.
  final bool isDouble;

  /// The points the server scored for it (the double included), or null
  /// while the fixture has no score yet.
  final int? points;

  /// Whether it hit the exact scoreline.
  final bool exact;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'home_goals': homeGoals,
    'away_goals': awayGoals,
    'is_double': isDouble,
    'points': points,
    'exact': exact,
  };
}

/// One fixture of the round.
final class H2hRoundFixtureDto {
  /// Creates a fixture line.
  const H2hRoundFixtureDto({
    required this.fixtureId,
    required this.homeTeam,
    required this.awayTeam,
    required this.state,
    required this.theirsHidden,
    this.homeTeamId,
    this.awayTeamId,
    this.kickoffAt,
    this.homeGoals,
    this.awayGoals,
    this.mine,
    this.theirs,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hRoundFixtureDto.fromJson(Map<String, Object?> json) {
    final Map<String, Object?>? mine = _map(json['mine']);
    final Map<String, Object?>? theirs = _map(json['theirs']);
    return H2hRoundFixtureDto(
      fixtureId: (json['fixture_id'] as String?) ?? '',
      homeTeam: (json['home_team'] as String?) ?? '',
      awayTeam: (json['away_team'] as String?) ?? '',
      homeTeamId: json['home_team_id'] as String?,
      awayTeamId: json['away_team_id'] as String?,
      kickoffAt: json['kickoff_at'] as String?,
      state: (json['state'] as String?) ?? 'not_started',
      homeGoals: json['home_goals'] as int?,
      awayGoals: json['away_goals'] as int?,
      mine: mine == null ? null : H2hPickDto.fromJson(mine),
      theirs: theirs == null ? null : H2hPickDto.fromJson(theirs),
      theirsHidden: (json['theirs_hidden'] as bool?) ?? false,
    );
  }

  /// The fixture (UUID string).
  final String fixtureId;

  /// The home team's name.
  final String homeTeam;

  /// The away team's name.
  final String awayTeam;

  /// The home team's catalogue id, when known.
  final String? homeTeamId;

  /// The away team's catalogue id, when known.
  final String? awayTeamId;

  /// The kickoff, ISO-8601 UTC, or null when none is registered.
  final String? kickoffAt;

  /// `not_started`, `live`, `finished`, or `void` (moved off the round day
  /// or hidden: it counts for neither side).
  final String state;

  /// The final home goals, once a result is recorded.
  final int? homeGoals;

  /// The final away goals, once a result is recorded.
  final int? awayGoals;

  /// The caller's pick, or null when they did not predict it.
  final H2hPickDto? mine;

  /// The opponent's pick: null before kickoff, when they did not predict
  /// it, or when the caller plays the group average.
  final H2hPickDto? theirs;

  /// True while the opponent's pick is withheld because the fixture has not
  /// kicked off.
  final bool theirsHidden;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'fixture_id': fixtureId,
    'home_team': homeTeam,
    'away_team': awayTeam,
    'home_team_id': homeTeamId,
    'away_team_id': awayTeamId,
    'kickoff_at': kickoffAt,
    'state': state,
    'home_goals': homeGoals,
    'away_goals': awayGoals,
    'mine': mine?.toJson(),
    'theirs': theirs?.toJson(),
    'theirs_hidden': theirsHidden,
  };
}

/// One side's counts over the round.
final class H2hSideTotalsDto {
  /// Creates the counts.
  const H2hSideTotalsDto({
    required this.predicted,
    required this.exact,
    required this.doubles,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hSideTotalsDto.fromJson(Map<String, Object?> json) =>
      H2hSideTotalsDto(
        predicted: (json['predicted'] as int?) ?? 0,
        exact: (json['exact'] as int?) ?? 0,
        doubles: (json['doubles'] as int?) ?? 0,
      );

  /// Fixtures predicted (for the opponent: kicked-off fixtures only).
  final int predicted;

  /// Exact scorelines hit.
  final int exact;

  /// Fixtures doubled (for the opponent: kicked-off fixtures only).
  final int doubles;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'predicted': predicted,
    'exact': exact,
    'doubles': doubles,
  };
}

/// Response body of `GET /me/h2h-league/rounds/{n}`.
final class MyH2hRoundDto {
  /// Creates the reading.
  const MyH2hRoundDto({
    required this.round,
    required this.day,
    required this.status,
    required this.fixtureCount,
    required this.mine,
    required this.fixtures,
    this.firstKickoff,
    this.opponentUserId,
    this.opponentName,
    this.opponentAvatarUrl,
    this.myPoints,
    this.opponentPoints,
    this.result,
    this.theirs,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating older schema versions.
  factory MyH2hRoundDto.fromJson(Map<String, Object?> json) {
    final Map<String, Object?>? theirs = _map(json['theirs']);
    return MyH2hRoundDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      round: (json['round'] as int?) ?? 0,
      day: (json['day'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'upcoming',
      fixtureCount: (json['fixture_count'] as int?) ?? 0,
      firstKickoff: json['first_kickoff'] as String?,
      opponentUserId: json['opponent_user_id'] as String?,
      opponentName: json['opponent_name'] as String?,
      opponentAvatarUrl: json['opponent_avatar_url'] as String?,
      myPoints: json['my_points'] as int?,
      opponentPoints: (json['opponent_points'] as num?)?.toDouble(),
      result: json['result'] as String?,
      mine: H2hSideTotalsDto.fromJson(_map(json['mine']) ?? const {}),
      theirs: theirs == null ? null : H2hSideTotalsDto.fromJson(theirs),
      fixtures: [
        for (final m in _maps(json['fixtures'])) H2hRoundFixtureDto.fromJson(m),
      ],
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// 1-based round of the month.
  final int round;

  /// The round's Riyadh day, `YYYY-MM-DD`.
  final String day;

  /// `open`, `upcoming`, `live`, `settled` or `voided`.
  final String status;

  /// Fixtures of the round (frozen once it started).
  final int fixtureCount;

  /// The round's first kickoff, ISO-8601 UTC, when known.
  final String? firstKickoff;

  /// The opponent, or null when the caller plays the group average.
  final String? opponentUserId;

  /// The opponent's display name.
  final String? opponentName;

  /// The opponent's picture, or null.
  final String? opponentAvatarUrl;

  /// The caller's points in the round; null before it starts.
  final int? myPoints;

  /// The opponent's points, or the group average; null before it starts.
  final double? opponentPoints;

  /// `win`, `draw` or `loss` so far; null before it starts or when void.
  final String? result;

  /// The caller's counts.
  final H2hSideTotalsDto mine;

  /// The opponent's counts over kicked-off fixtures, or null with the
  /// group average.
  final H2hSideTotalsDto? theirs;

  /// Every fixture of the round, by kickoff.
  final List<H2hRoundFixtureDto> fixtures;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'round': round,
    'day': day,
    'status': status,
    'fixture_count': fixtureCount,
    'first_kickoff': firstKickoff,
    'opponent_user_id': opponentUserId,
    'opponent_name': opponentName,
    'opponent_avatar_url': opponentAvatarUrl,
    'my_points': myPoints,
    'opponent_points': opponentPoints,
    'result': result,
    'mine': mine.toJson(),
    'theirs': theirs?.toJson(),
    'fixtures': [for (final f in fixtures) f.toJson()],
  };
}
