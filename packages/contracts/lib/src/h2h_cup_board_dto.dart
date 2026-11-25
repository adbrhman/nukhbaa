// NK308_01
/// `GET /me/h2h-cup/board`: the Elite Cup of the month as every signed-in
/// player reads it -- the three paths, their stages, pairs and fixtures, with
/// the two players' picks on each fixture (script 308).
///
/// **A pick crosses this wire only once it may be seen.** A side whose pick is
/// withheld is [H2hCupBoardSideDto.revealed] false and carries no pick key and
/// no flag saying whether the player predicted: before kickoff nobody learns
/// that, not by a key, not by an empty field, not by the size of the payload.
/// A side that may be seen with no pick means the player did not predict.
library;

import 'package:contracts/src/h2h_cup_dto.dart';
import 'package:contracts/src/h2h_round_detail_dto.dart';

/// One player's side of one fixture: his pick, or that it is withheld.
final class H2hCupBoardSideDto {
  /// Creates a side. A side that is not [revealed] cannot carry a [pick].
  const H2hCupBoardSideDto({required this.revealed, this.pick})
    : assert(revealed || pick == null, 'a withheld side carries no pick');

  /// A side whose pick is withheld.
  const H2hCupBoardSideDto.hidden() : revealed = false, pick = null;

  /// Deserializes from a JSON map. A payload that does not say the side is
  /// revealed reads as withheld, and a pick on a withheld side is dropped.
  factory H2hCupBoardSideDto.fromJson(Map<String, Object?> json) {
    final bool revealed = (json['revealed'] as bool?) ?? false;
    final Object? raw = json['pick'];
    return H2hCupBoardSideDto(
      revealed: revealed,
      pick: revealed && raw is Map<String, Object?>
          ? H2hPickDto.fromJson(raw)
          : null,
    );
  }

  /// Whether the pick may be seen: the fixture has kicked off, or the side
  /// is the caller's own.
  final bool revealed;

  /// The player's pick, or null when withheld or when he did not predict.
  final H2hPickDto? pick;

  /// Serializes to a JSON-encodable map. A withheld side is `revealed` only.
  Map<String, Object?> toJson() {
    final H2hPickDto? shown = revealed ? pick : null;
    return {'revealed': revealed, if (shown != null) 'pick': shown.toJson()};
  }
}

/// One fixture of a stage, with both players' sides of a pair.
final class H2hCupBoardFixtureDto {
  /// Creates the fixture line.
  const H2hCupBoardFixtureDto({
    required this.fixtureId,
    required this.homeTeam,
    required this.awayTeam,
    required this.state,
    required this.homeSide,
    required this.awaySide,
    this.homeTeamId,
    this.awayTeamId,
    this.kickoffAt,
    this.homeGoals,
    this.awayGoals,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hCupBoardFixtureDto.fromJson(Map<String, Object?> json) =>
      H2hCupBoardFixtureDto(
        fixtureId: (json['fixture_id'] as String?) ?? '',
        homeTeam: (json['home_team'] as String?) ?? '',
        awayTeam: (json['away_team'] as String?) ?? '',
        homeTeamId: json['home_team_id'] as String?,
        awayTeamId: json['away_team_id'] as String?,
        kickoffAt: json['kickoff_at'] as String?,
        state: (json['state'] as String?) ?? 'not_started',
        homeGoals: json['home_goals'] as int?,
        awayGoals: json['away_goals'] as int?,
        homeSide: _side(json['home_side']),
        awaySide: _side(json['away_side']),
      );

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

  /// The kickoff, ISO-8601 UTC, or null when none is registered (such a
  /// fixture counts as not started).
  final String? kickoffAt;

  /// `not_started`, `live`, `finished`, or `void` (left the stage's day or
  /// hidden: it counts for neither player).
  final String state;

  /// The final home goals, once a result is recorded.
  final int? homeGoals;

  /// The final away goals, once a result is recorded.
  final int? awayGoals;

  /// The side of the pair's home player.
  final H2hCupBoardSideDto homeSide;

  /// The side of the pair's away player.
  final H2hCupBoardSideDto awaySide;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'fixture_id': fixtureId,
    'home_team': homeTeam,
    'away_team': awayTeam,
    if (homeTeamId != null) 'home_team_id': homeTeamId,
    if (awayTeamId != null) 'away_team_id': awayTeamId,
    if (kickoffAt != null) 'kickoff_at': kickoffAt,
    'state': state,
    if (homeGoals != null) 'home_goals': homeGoals,
    if (awayGoals != null) 'away_goals': awayGoals,
    'home_side': homeSide.toJson(),
    'away_side': awaySide.toJson(),
  };
}

/// One pair of a stage, with the fixtures both players predicted.
final class H2hCupBoardPairDto {
  /// Creates the pair.
  const H2hCupBoardPairDto({
    required this.slot,
    required this.home,
    required this.away,
    required this.decided,
    required this.fixtures,
    this.winnerUserId,
    this.homePoints,
    this.awayPoints,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hCupBoardPairDto.fromJson(Map<String, Object?> json) =>
      H2hCupBoardPairDto(
        slot: (json['slot'] as int?) ?? 0,
        home: _player(json['home']),
        away: _player(json['away']),
        decided: (json['decided'] as bool?) ?? false,
        winnerUserId: json['winner_user_id'] as String?,
        homePoints: json['home_points'] as int?,
        awayPoints: json['away_points'] as int?,
        fixtures: [
          for (final Object? f in (json['fixtures'] as List<Object?>?) ?? [])
            if (f is Map<String, Object?>) H2hCupBoardFixtureDto.fromJson(f),
        ],
      );

  /// The pair's slot.
  final int slot;

  /// The first player.
  final H2hCupPlayerDto home;

  /// The second player.
  final H2hCupPlayerDto away;

  /// Whether the pair has a result.
  final bool decided;

  /// The winner, or null when undecided or when both lost.
  final String? winnerUserId;

  // NK330B_01
  /// The first player's prediction points on the stage's fixtures, or null
  /// from a server that does not send it: the figure the cup decided the
  /// pair with once it is [decided], until then the points of the fixtures
  /// the board shows for his side (0 before any score).
  final int? homePoints;

  /// The second player's prediction points, as [homePoints].
  final int? awayPoints;

  /// The stage's fixtures, by kickoff, with each player's side.
  final List<H2hCupBoardFixtureDto> fixtures;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'slot': slot,
    'home': home.toJson(),
    'away': away.toJson(),
    'decided': decided,
    if (winnerUserId != null) 'winner_user_id': winnerUserId,
    if (homePoints != null) 'home_points': homePoints,
    if (awayPoints != null) 'away_points': awayPoints,
    'fixtures': [for (final H2hCupBoardFixtureDto f in fixtures) f.toJson()],
  };
}

/// One stage of a path.
final class H2hCupBoardStageDto {
  /// Creates the stage.
  const H2hCupBoardStageDto({
    required this.round,
    required this.cupDay,
    required this.phase,
    required this.attempt,
    required this.pairs,
    this.day,
    this.bye,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hCupBoardStageDto.fromJson(Map<String, Object?> json) =>
      H2hCupBoardStageDto(
        round: (json['round'] as String?) ?? '',
        cupDay: (json['cup_day'] as int?) ?? 0,
        phase: (json['phase'] as String?) ?? 'waiting',
        attempt: (json['attempt'] as int?) ?? 1,
        day: json['day'] as String?,
        pairs: [
          for (final Object? p in (json['pairs'] as List<Object?>?) ?? [])
            if (p is Map<String, Object?>) H2hCupBoardPairDto.fromJson(p),
        ],
        bye: json['bye'] is Map<String, Object?>
            ? H2hCupPlayerDto.fromJson(json['bye']! as Map<String, Object?>)
            : null,
      );

  /// `semi` or `final`.
  final String round;

  /// The cup day, 1 to 4.
  final int cupDay;

  /// `waiting`, `scheduled`, `live`, `decided` or `skipped`.
  final String phase;

  /// 1, or more for a stage carried to another day.
  final int attempt;

  /// The Riyadh day of its fixtures (`YYYY-MM-DD`), null before it has one.
  final String? day;

  /// Its pairs, by slot: empty before it is given a day.
  final List<H2hCupBoardPairDto> pairs;

  /// The qualifier left without a pair (three qualifiers), or null.
  final H2hCupPlayerDto? bye;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'round': round,
    'cup_day': cupDay,
    'phase': phase,
    'attempt': attempt,
    if (day != null) 'day': day,
    'pairs': [for (final H2hCupBoardPairDto p in pairs) p.toJson()],
    if (bye != null) 'bye': bye!.toJson(),
  };
}

/// One path of the cup (1, 2 or 3).
final class H2hCupBoardPathDto {
  /// Creates the path.
  const H2hCupBoardPathDto({
    required this.place,
    required this.stages,
    this.title,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hCupBoardPathDto.fromJson(Map<String, Object?> json) =>
      H2hCupBoardPathDto(
        place: (json['place'] as int?) ?? 0,
        stages: [
          for (final Object? s in (json['stages'] as List<Object?>?) ?? [])
            if (s is Map<String, Object?>) H2hCupBoardStageDto.fromJson(s),
        ],
        title: json['title'] is Map<String, Object?>
            ? H2hCupTitleDto.fromJson(json['title']! as Map<String, Object?>)
            : null,
      );

  /// The path: 1, 2 or 3.
  final int place;

  /// The path's stages: semi-finals, then the final.
  final List<H2hCupBoardStageDto> stages;

  /// The path's title once decided.
  final H2hCupTitleDto? title;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'place': place,
    'stages': [for (final H2hCupBoardStageDto s in stages) s.toJson()],
    if (title != null) 'title': title!.toJson(),
  };
}

/// `GET /me/h2h-cup/board`: the whole cup of the month for any signed-in
/// player or admin.
final class H2hCupBoardDto {
  /// Creates the board.
  const H2hCupBoardDto({
    this.monthStart,
    this.paths = const <H2hCupBoardPathDto>[],
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hCupBoardDto.fromJson(Map<String, Object?> json) => H2hCupBoardDto(
    schemaVersion: (json['schema_version'] as int?) ?? 1,
    monthStart: json['month_start'] as String?,
    paths: [
      for (final Object? p in (json['paths'] as List<Object?>?) ?? [])
        if (p is Map<String, Object?>) H2hCupBoardPathDto.fromJson(p),
    ],
  );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The first day of the month of the cup (`YYYY-MM-DD`); null before a
  /// cup stands, when [paths] is empty too.
  final String? monthStart;

  /// The cup's paths, 1 to 3; empty before the cup stands.
  final List<H2hCupBoardPathDto> paths;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    if (monthStart != null) 'month_start': monthStart,
    'paths': [for (final H2hCupBoardPathDto p in paths) p.toJson()],
  };
}

H2hCupBoardSideDto _side(Object? raw) => raw is Map<String, Object?>
    ? H2hCupBoardSideDto.fromJson(raw)
    : const H2hCupBoardSideDto.hidden();

H2hCupPlayerDto _player(Object? raw) => H2hCupPlayerDto.fromJson(
  raw is Map<String, Object?> ? raw : const <String, Object?>{},
);
