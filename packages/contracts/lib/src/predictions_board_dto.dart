/// Wire shape of the players' predictions board of a day in one answer
/// (`GET /seasons/{id}/predictions-board?fixtures=`, 2026-10-11): for each
/// fixture asked for, everyone's predictions, the scores and the reactions,
/// in the very shapes the three per-fixture routes send -- or the refusal
/// that kept the fixture hidden.
///
/// Every value is server-produced (Axioms 2/5); the client draws the board
/// and decides nothing.
library;

import 'package:contracts/src/fixture_prediction_dto.dart';
import 'package:contracts/src/participant_fixture_score_dto.dart';
import 'package:contracts/src/prediction_reaction_dto.dart';

Map<String, Object?>? _map(Object? raw) =>
    raw is Map ? raw.cast<String, Object?>() : null;

/// One fixture of the board.
final class PredictionsBoardColumnDto {
  /// Creates a column.
  const PredictionsBoardColumnDto({
    required this.fixtureId,
    this.errorCode,
    this.retryable = false,
    this.predictions = const <FixturePredictionDto>[],
    this.scores,
    this.reactions,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory PredictionsBoardColumnDto.fromJson(Map<String, Object?> json) {
    final Object? rawPredictions = json['predictions'];
    final Map<String, Object?>? scores = _map(json['scores']);
    final Map<String, Object?>? reactions = _map(json['reactions']);
    return PredictionsBoardColumnDto(
      fixtureId: (json['fixture_id'] as String?) ?? '',
      errorCode: json['error_code'] as String?,
      retryable: (json['retryable'] as bool?) ?? false,
      predictions: <FixturePredictionDto>[
        if (rawPredictions is List)
          for (final Object? item in rawPredictions)
            if (item is Map)
              FixturePredictionDto.fromJson(item.cast<String, Object?>()),
      ],
      scores: scores == null ? null : FixtureScoresDto.fromJson(scores),
      reactions: reactions == null
          ? null
          : PredictionReactionsDto.fromJson(reactions),
    );
  }

  /// The fixture (UUID string).
  final String fixtureId;

  /// The refusal that keeps the fixture hidden (`prediction.*`), or a
  /// failure code; null when the column is shown.
  final String? errorCode;

  /// Whether asking again may succeed (a passing failure, not a refusal).
  final bool retryable;

  /// Everyone's predictions with their names, as
  /// `GET .../fixtures/{id}/predictions` sends them.
  final List<FixturePredictionDto> predictions;

  /// The scores and the recorded result, as `GET .../fixtures/{id}/scores`
  /// sends them; null with [errorCode].
  final FixtureScoresDto? scores;

  /// The reactions, as `GET .../fixtures/{id}/reactions` sends them; null
  /// with [errorCode] or when they could not be read.
  final PredictionReactionsDto? reactions;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'fixture_id': fixtureId,
    'error_code': errorCode,
    'retryable': retryable,
    'predictions': [for (final p in predictions) p.toJson()],
    'scores': scores?.toJson(),
    'reactions': reactions?.toJson(),
  };
}

/// Response body of `GET /seasons/{id}/predictions-board`.
final class PredictionsBoardDto {
  /// Creates the board.
  const PredictionsBoardDto({
    required this.seasonId,
    required this.columns,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating older schema versions.
  factory PredictionsBoardDto.fromJson(Map<String, Object?> json) {
    final Object? raw = json['columns'];
    return PredictionsBoardDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      seasonId: (json['season_id'] as String?) ?? '',
      columns: <PredictionsBoardColumnDto>[
        if (raw is List)
          for (final Object? item in raw)
            if (item is Map)
              PredictionsBoardColumnDto.fromJson(item.cast<String, Object?>()),
      ],
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The season (UUID string).
  final String seasonId;

  /// One column per fixture asked for, in the order asked.
  final List<PredictionsBoardColumnDto> columns;

  /// The schema version of this payload.
  final int schemaVersion;

  /// The column of [fixtureId], or null.
  PredictionsBoardColumnDto? of(String fixtureId) {
    for (final PredictionsBoardColumnDto c in columns) {
      if (c.fixtureId == fixtureId) return c;
    }
    return null;
  }

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'season_id': seasonId,
    'columns': [for (final c in columns) c.toJson()],
  };
}
