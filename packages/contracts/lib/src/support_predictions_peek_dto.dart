/// Support's reading of one player's predictions of the matches not yet
/// started (script 261, migration 0208):
/// `POST /admin/support/conversations/{id}/predictions` `{"reason": "..."}`.
/// The only reading of a prediction before its kickoff, by anyone; the
/// player is told in his conversation by [SupportPredictionsPeekDto.notice].
library;

import 'package:contracts/src/support_dto.dart';

Map<String, Object?> _map(Object? value) =>
    ((value as Map<Object?, Object?>?) ?? const <Object?, Object?>{})
        .cast<String, Object?>();

/// One prediction of a match not yet started.
final class SupportPeekedPredictionDto {
  /// Creates the line.
  const SupportPeekedPredictionDto({
    required this.fixtureId,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
    required this.homeGoals,
    required this.awayGoals,
    required this.isDouble,
    this.leagueName,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory SupportPeekedPredictionDto.fromJson(Map<String, Object?> json) =>
      SupportPeekedPredictionDto(
        fixtureId: (json['fixture_id'] as String?) ?? '',
        homeTeam: (json['home_team'] as String?) ?? '',
        awayTeam: (json['away_team'] as String?) ?? '',
        kickoffAt: (json['kickoff_at'] as String?) ?? '',
        homeGoals: (json['home_goals'] as int?) ?? 0,
        awayGoals: (json['away_goals'] as int?) ?? 0,
        isDouble: (json['is_double'] as bool?) ?? false,
        leagueName: json['league_name'] as String?,
      );

  /// The match.
  final String fixtureId;

  /// Its home side.
  final String homeTeam;

  /// Its away side.
  final String awayTeam;

  /// Its kickoff, ISO-8601 UTC.
  final String kickoffAt;

  /// The predicted home goals.
  final int homeGoals;

  /// The predicted away goals.
  final int awayGoals;

  /// Whether it is the player's double of the day.
  final bool isDouble;

  /// Its league's name, when it has one.
  final String? leagueName;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'fixture_id': fixtureId,
    'home_team': homeTeam,
    'away_team': awayTeam,
    'kickoff_at': kickoffAt,
    'home_goals': homeGoals,
    'away_goals': awayGoals,
    'is_double': isDouble,
    if (leagueName != null) 'league_name': leagueName,
  };

  @override
  bool operator ==(Object other) =>
      other is SupportPeekedPredictionDto &&
      other.fixtureId == fixtureId &&
      other.homeTeam == homeTeam &&
      other.awayTeam == awayTeam &&
      other.kickoffAt == kickoffAt &&
      other.homeGoals == homeGoals &&
      other.awayGoals == awayGoals &&
      other.isDouble == isDouble &&
      other.leagueName == leagueName;

  @override
  int get hashCode => Object.hash(
    fixtureId,
    homeTeam,
    awayTeam,
    kickoffAt,
    homeGoals,
    awayGoals,
    isDouble,
    leagueName,
  );
}

/// The reading: the player's open predictions by kickoff, and the message
/// that told him.
final class SupportPredictionsPeekDto {
  /// Creates the reading.
  const SupportPredictionsPeekDto({
    required this.predictions,
    required this.notice,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory SupportPredictionsPeekDto.fromJson(Map<String, Object?> json) =>
      SupportPredictionsPeekDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        predictions: [
          for (final Object? line
              in (json['predictions'] as List<Object?>?) ?? const <Object?>[])
            SupportPeekedPredictionDto.fromJson(_map(line)),
        ],
        notice: SupportMessageDto.fromJson(_map(json['notice'])),
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The player's predictions of the matches not yet started, by kickoff.
  final List<SupportPeekedPredictionDto> predictions;

  /// The message stored in his conversation to tell him.
  final SupportMessageDto notice;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'predictions': [for (final line in predictions) line.toJson()],
    'notice': notice.toJson(),
  };
}
