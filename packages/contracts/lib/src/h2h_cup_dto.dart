/// `GET /me/h2h-cup`: the caller's Elite Cup of the head-to-head league
/// (NK185, migration 0190) -- whether the caller qualified, the path he
/// plays, its stages with their days, pairs and results, and its title.
///
/// Names, days and the figures that decided a pair only: nobody's
/// prediction crosses this wire.
library;

/// A player of the caller's path.
final class H2hCupPlayerDto {
  /// Creates the player.
  const H2hCupPlayerDto({
    required this.userId,
    required this.displayName,
    required this.groupNumber,
    required this.isMe,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hCupPlayerDto.fromJson(Map<String, Object?> json) =>
      H2hCupPlayerDto(
        userId: (json['user_id'] as String?) ?? '',
        displayName: (json['display_name'] as String?) ?? '',
        groupNumber: (json['group_number'] as int?) ?? 0,
        isMe: (json['is_me'] as bool?) ?? false,
      );

  /// The player.
  final String userId;

  /// The display name; empty when the player has no profile.
  final String displayName;

  /// The elite group the player qualified from (1 to 4; 0 when unknown).
  final int groupNumber;

  /// Whether this is the caller.
  final bool isMe;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'user_id': userId,
    'display_name': displayName,
    'group_number': groupNumber,
    'is_me': isMe,
  };
}

/// One pair of a stage.
final class H2hCupPairDto {
  /// Creates the pair.
  const H2hCupPairDto({
    required this.slot,
    required this.home,
    required this.away,
    required this.isMine,
    required this.decided,
    this.outcome,
    this.winnerUserId,
    this.homePoints,
    this.awayPoints,
    this.homeExact,
    this.awayExact,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hCupPairDto.fromJson(Map<String, Object?> json) => H2hCupPairDto(
    slot: (json['slot'] as int?) ?? 0,
    home: _player(json['home']),
    away: _player(json['away']),
    isMine: (json['is_mine'] as bool?) ?? false,
    decided: (json['decided'] as bool?) ?? false,
    outcome: json['outcome'] as String?,
    winnerUserId: json['winner_user_id'] as String?,
    homePoints: json['home_points'] as int?,
    awayPoints: json['away_points'] as int?,
    homeExact: json['home_exact'] as int?,
    awayExact: json['away_exact'] as int?,
  );

  /// The pair's slot.
  final int slot;

  /// The first side.
  final H2hCupPlayerDto home;

  /// The second side.
  final H2hCupPlayerDto away;

  /// Whether the caller is one of the two.
  final bool isMine;

  /// Whether the pair has a result.
  final bool decided;

  /// How it was decided: `points`, `exact`, `league`, `walkover` or
  /// `both_absent`; null until decided.
  final String? outcome;

  /// The winner, or null when undecided or when both lost.
  final String? winnerUserId;

  /// The first side's prediction points on the stage's fixtures.
  final int? homePoints;

  /// The second side's prediction points on the stage's fixtures.
  final int? awayPoints;

  /// The first side's exact scorelines.
  final int? homeExact;

  /// The second side's exact scorelines.
  final int? awayExact;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'slot': slot,
    'home': home.toJson(),
    'away': away.toJson(),
    'is_mine': isMine,
    'decided': decided,
    if (outcome != null) 'outcome': outcome,
    if (winnerUserId != null) 'winner_user_id': winnerUserId,
    if (homePoints != null) 'home_points': homePoints,
    if (awayPoints != null) 'away_points': awayPoints,
    if (homeExact != null) 'home_exact': homeExact,
    if (awayExact != null) 'away_exact': awayExact,
  };
}

/// One stage of the caller's path.
final class H2hCupStageDto {
  /// Creates the stage.
  const H2hCupStageDto({
    required this.round,
    required this.cupDay,
    required this.expectedDay,
    required this.phase,
    required this.attempt,
    required this.pairs,
    this.day,
    this.fixtureCount,
    this.bye,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hCupStageDto.fromJson(Map<String, Object?> json) => H2hCupStageDto(
    round: (json['round'] as String?) ?? '',
    cupDay: (json['cup_day'] as int?) ?? 0,
    expectedDay: (json['expected_day'] as int?) ?? 0,
    phase: (json['phase'] as String?) ?? 'waiting',
    attempt: (json['attempt'] as int?) ?? 1,
    day: json['day'] as String?,
    fixtureCount: json['fixture_count'] as int?,
    pairs: [
      for (final Object? p in (json['pairs'] as List<Object?>?) ?? [])
        if (p is Map<String, Object?>) H2hCupPairDto.fromJson(p),
    ],
    bye: json['bye'] is Map<String, Object?>
        ? H2hCupPlayerDto.fromJson(json['bye']! as Map<String, Object?>)
        : null,
  );

  /// `semi` or `final`.
  final String round;

  /// The cup day, 1 to 4.
  final int cupDay;

  /// The league day it is expected on when nothing is late: 20 to 23.
  final int expectedDay;

  /// `waiting`, `scheduled`, `live`, `decided` or `skipped`.
  final String phase;

  /// 1, or more for a stage carried to another day.
  final int attempt;

  /// The Riyadh day of its fixtures (`YYYY-MM-DD`), null before it has one.
  final String? day;

  /// The fixtures the day held when the stage was given it.
  final int? fixtureCount;

  /// Its pairs, by slot: empty before it is given a day.
  final List<H2hCupPairDto> pairs;

  /// The qualifier left without a pair (three qualifiers), or null.
  final H2hCupPlayerDto? bye;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'round': round,
    'cup_day': cupDay,
    'expected_day': expectedDay,
    'phase': phase,
    'attempt': attempt,
    if (day != null) 'day': day,
    if (fixtureCount != null) 'fixture_count': fixtureCount,
    'pairs': [for (final H2hCupPairDto p in pairs) p.toJson()],
    if (bye != null) 'bye': bye!.toJson(),
  };
}

/// The title of the caller's path.
final class H2hCupTitleDto {
  /// Creates the title.
  const H2hCupTitleDto({required this.how, this.champion, this.runnerUp});

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hCupTitleDto.fromJson(Map<String, Object?> json) => H2hCupTitleDto(
    how: (json['how'] as String?) ?? '',
    champion: json['champion'] is Map<String, Object?>
        ? H2hCupPlayerDto.fromJson(json['champion']! as Map<String, Object?>)
        : null,
    runnerUp: json['runner_up'] is Map<String, Object?>
        ? H2hCupPlayerDto.fromJson(json['runner_up']! as Map<String, Object?>)
        : null,
  );

  /// `final`, `walkover` or `vacant`.
  final String how;

  /// The champion, or null when vacant.
  final H2hCupPlayerDto? champion;

  /// The runner-up, or null.
  final H2hCupPlayerDto? runnerUp;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'how': how,
    if (champion != null) 'champion': champion!.toJson(),
    if (runnerUp != null) 'runner_up': runnerUp!.toJson(),
  };
}

/// `GET /me/h2h-cup`: the caller's cup.
final class MyH2hCupDto {
  /// Creates the cup.
  const MyH2hCupDto({
    required this.state,
    this.monthStart,
    this.place = 0,
    this.groupNumber = 0,
    this.entrants = const <H2hCupPlayerDto>[],
    this.stages = const <H2hCupStageDto>[],
    this.title,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory MyH2hCupDto.fromJson(Map<String, Object?> json) => MyH2hCupDto(
    schemaVersion: (json['schema_version'] as int?) ?? 1,
    state: (json['state'] as String?) ?? 'not_qualified',
    monthStart: json['month_start'] as String?,
    place: (json['place'] as int?) ?? 0,
    groupNumber: (json['group_number'] as int?) ?? 0,
    entrants: [
      for (final Object? e in (json['entrants'] as List<Object?>?) ?? [])
        if (e is Map<String, Object?>) H2hCupPlayerDto.fromJson(e),
    ],
    stages: [
      for (final Object? s in (json['stages'] as List<Object?>?) ?? [])
        if (s is Map<String, Object?>) H2hCupStageDto.fromJson(s),
    ],
    title: json['title'] is Map<String, Object?>
        ? H2hCupTitleDto.fromJson(json['title']! as Map<String, Object?>)
        : null,
  );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// `qualified` or `not_qualified`.
  final String state;

  /// The first day of the month of the cup (`YYYY-MM-DD`).
  final String? monthStart;

  /// The caller's path: 1, 2 or 3 (0 when not qualified).
  final int place;

  /// The caller's elite group (0 when not qualified).
  final int groupNumber;

  /// The qualifiers of the caller's path, by group.
  final List<H2hCupPlayerDto> entrants;

  /// The two stages of the path: semi-finals, then the final.
  final List<H2hCupStageDto> stages;

  /// The path's title once decided.
  final H2hCupTitleDto? title;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'state': state,
    if (monthStart != null) 'month_start': monthStart,
    'place': place,
    'group_number': groupNumber,
    'entrants': [for (final H2hCupPlayerDto e in entrants) e.toJson()],
    'stages': [for (final H2hCupStageDto s in stages) s.toJson()],
    if (title != null) 'title': title!.toJson(),
  };
}

H2hCupPlayerDto _player(Object? raw) => H2hCupPlayerDto.fromJson(
  raw is Map<String, Object?> ? raw : const <String, Object?>{},
);
