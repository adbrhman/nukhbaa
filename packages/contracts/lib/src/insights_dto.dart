/// Body of `GET /me/insights` (plan P4-4): the caller's accuracy, patterns
/// and last week's recap, as the server computed them.
///
/// Percent fields are null when nothing was decided, never a made-up zero.
/// Dates are Riyadh days as `YYYY-MM-DD`.
final class InsightsDto {
  /// Creates the body.
  const InsightsDto({
    required this.month,
    required this.leagues,
    required this.weeks,
    required this.longestCorrectRun,
    this.communityPercent,
    this.bestLeague,
    this.worstLeague,
    this.followedPercent,
    this.othersPercent,
    this.lastWeek,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory InsightsDto.fromJson(Map<String, Object?> json) {
    return InsightsDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      month: AccuracyDto.fromJson(_map(json['month'])),
      communityPercent: json['community_percent'] as int?,
      leagues: <LeagueAccuracyDto>[
        for (final item in _list(json['leagues']))
          LeagueAccuracyDto.fromJson(_map(item)),
      ],
      bestLeague: json['best_league'] as String?,
      worstLeague: json['worst_league'] as String?,
      followedPercent: json['followed_percent'] as int?,
      othersPercent: json['others_percent'] as int?,
      longestCorrectRun: (json['longest_correct_run'] as int?) ?? 0,
      weeks: <WeekAccuracyDto>[
        for (final item in _list(json['weeks']))
          WeekAccuracyDto.fromJson(_map(item)),
      ],
      lastWeek: json['last_week'] == null
          ? null
          : WeekRecapDto.fromJson(_map(json['last_week'])),
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// This Riyadh month's accuracy.
  final AccuracyDto month;

  /// Every player's accuracy this month, as a whole percent.
  final int? communityPercent;

  /// Accuracy per league, most played first.
  final List<LeagueAccuracyDto> leagues;

  /// The best league, when two qualify and differ.
  final String? bestLeague;

  /// The worst league, when two qualify and differ.
  final String? worstLeague;

  /// Accuracy on a followed team's fixtures, when both samples suffice.
  final int? followedPercent;

  /// Accuracy on every other fixture, alongside [followedPercent].
  final int? othersPercent;

  /// The longest run of right predictions in the window.
  final int longestCorrectRun;

  /// The last weeks, oldest first, the current one last.
  final List<WeekAccuracyDto> weeks;

  /// Last week's recap, or null when last week had no decided prediction.
  final WeekRecapDto? lastWeek;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'month': month.toJson(),
    'community_percent': communityPercent,
    'leagues': [for (final league in leagues) league.toJson()],
    'best_league': bestLeague,
    'worst_league': worstLeague,
    'followed_percent': followedPercent,
    'others_percent': othersPercent,
    'longest_correct_run': longestCorrectRun,
    'weeks': [for (final week in weeks) week.toJson()],
    'last_week': lastWeek?.toJson(),
  };
}

/// Decided predictions and how many were right.
final class AccuracyDto {
  /// Creates the tally.
  const AccuracyDto({
    required this.decided,
    required this.correct,
    required this.exact,
    this.percent,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory AccuracyDto.fromJson(Map<String, Object?> json) => AccuracyDto(
    decided: (json['decided'] as int?) ?? 0,
    correct: (json['correct'] as int?) ?? 0,
    exact: (json['exact'] as int?) ?? 0,
    percent: json['percent'] as int?,
  );

  /// Predictions whose fixture has a result.
  final int decided;

  /// Right winner or draw.
  final int correct;

  /// Exact scorelines.
  final int exact;

  /// Whole percent right, null when nothing was decided.
  final int? percent;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'decided': decided,
    'correct': correct,
    'exact': exact,
    'percent': percent,
  };
}

/// Accuracy in one league.
final class LeagueAccuracyDto {
  /// Creates the line.
  const LeagueAccuracyDto({required this.name, required this.accuracy});

  /// Deserializes from a JSON map, tolerating missing keys.
  factory LeagueAccuracyDto.fromJson(Map<String, Object?> json) =>
      LeagueAccuracyDto(
        name: (json['name'] as String?) ?? '',
        accuracy: AccuracyDto.fromJson(json),
      );

  /// The league's name.
  final String name;

  /// The accuracy in it.
  final AccuracyDto accuracy;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {'name': name, ...accuracy.toJson()};
}

/// Accuracy in one Riyadh week.
final class WeekAccuracyDto {
  /// Creates the line.
  const WeekAccuracyDto({required this.weekStart, required this.accuracy});

  /// Deserializes from a JSON map, tolerating missing keys.
  factory WeekAccuracyDto.fromJson(Map<String, Object?> json) =>
      WeekAccuracyDto(
        weekStart: (json['week_start'] as String?) ?? '',
        accuracy: AccuracyDto.fromJson(json),
      );

  /// The Monday opening the week, `YYYY-MM-DD`.
  final String weekStart;

  /// The accuracy in it.
  final AccuracyDto accuracy;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'week_start': weekStart,
    ...accuracy.toJson(),
  };
}

/// The recap of one finished week.
final class WeekRecapDto {
  /// Creates the recap.
  const WeekRecapDto({
    required this.weekStart,
    required this.accuracy,
    required this.points,
    this.best,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory WeekRecapDto.fromJson(Map<String, Object?> json) => WeekRecapDto(
    weekStart: (json['week_start'] as String?) ?? '',
    accuracy: AccuracyDto.fromJson(json),
    points: (json['points'] as int?) ?? 0,
    best: json['best'] == null
        ? null
        : BestPredictionDto.fromJson(_map(json['best'])),
  );

  /// The Monday opening the week, `YYYY-MM-DD`.
  final String weekStart;

  /// The week's accuracy.
  final AccuracyDto accuracy;

  /// Points earned by the week's predictions.
  final int points;

  /// The prediction that earned the most.
  final BestPredictionDto? best;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'week_start': weekStart,
    ...accuracy.toJson(),
    'points': points,
    'best': best?.toJson(),
  };
}

/// The best prediction of a week.
final class BestPredictionDto {
  /// Creates the line.
  const BestPredictionDto({
    required this.homeTeam,
    required this.awayTeam,
    required this.points,
    required this.exact,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory BestPredictionDto.fromJson(Map<String, Object?> json) =>
      BestPredictionDto(
        homeTeam: (json['home_team'] as String?) ?? '',
        awayTeam: (json['away_team'] as String?) ?? '',
        points: (json['points'] as int?) ?? 0,
        exact: (json['exact'] as bool?) ?? false,
      );

  /// The home side.
  final String homeTeam;

  /// The away side.
  final String awayTeam;

  /// Points it earned.
  final int points;

  /// Whether it was the exact scoreline.
  final bool exact;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'home_team': homeTeam,
    'away_team': awayTeam,
    'points': points,
    'exact': exact,
  };
}

Map<String, Object?> _map(Object? raw) =>
    raw is Map<String, Object?> ? raw : const <String, Object?>{};

List<Object?> _list(Object? raw) =>
    raw is List<Object?> ? raw : const <Object?>[];
