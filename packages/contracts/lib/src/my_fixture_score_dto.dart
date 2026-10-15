/// The wire shape of `GET /me/fixture-scores` (script 75, migration 0171):
/// one of the caller's own predictions with its score and the match's final
/// score, as far as each exists.
///
/// Read-only (Axioms 2/5): the grade and points are the server's, echoed as
/// scoring computed them; nothing here is client-writable, and a client never
/// re-derives points from the final score.
library;

/// One prediction of the caller that has a score or a recorded result.
///
/// The app finds the row for a prediction by ([participantId], [fixtureId]),
/// the same pair `FixturePredictionDto` carries. [grade] and [points] are
/// null while the recorded result waits to be scored; the result fields are
/// null until a result is recorded. Null fields are left off the wire.
final class MyFixtureScoreDto {
  /// Creates a my-fixture-score DTO.
  const MyFixtureScoreDto({
    required this.participantId,
    required this.fixtureId,
    this.grade,
    this.points,
    this.resultHomeGoals,
    this.resultAwayGoals,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map; absent optional fields decode as null.
  factory MyFixtureScoreDto.fromJson(Map<String, Object?> json) {
    return MyFixtureScoreDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      participantId: json['participant_id']! as String,
      fixtureId: json['fixture_id']! as String,
      grade: json['grade'] as String?,
      points: json['points'] as int?,
      resultHomeGoals: json['result_home_goals'] as int?,
      resultAwayGoals: json['result_away_goals'] as int?,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The caller's participant id the prediction belongs to (UUID string).
  final String participantId;

  /// The predicted fixture's id (UUID string).
  final String fixtureId;

  /// The grade wire token (`exact_scoreline`, `correct_outcome`,
  /// `incorrect`, `missed` or `pending`); null until scored.
  final String? grade;

  /// The server-computed points (already doubled for the day's double);
  /// null until scored.
  final int? points;

  /// The home side of the recorded final score; null until recorded.
  final int? resultHomeGoals;

  /// The away side of the recorded final score; null until recorded.
  final int? resultAwayGoals;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map, leaving null fields off.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'participant_id': participantId,
    'fixture_id': fixtureId,
    if (grade != null) 'grade': grade,
    if (points != null) 'points': points,
    if (resultHomeGoals != null) 'result_home_goals': resultHomeGoals,
    if (resultAwayGoals != null) 'result_away_goals': resultAwayGoals,
  };

  @override
  bool operator ==(Object other) =>
      other is MyFixtureScoreDto &&
      other.participantId == participantId &&
      other.fixtureId == fixtureId &&
      other.grade == grade &&
      other.points == points &&
      other.resultHomeGoals == resultHomeGoals &&
      other.resultAwayGoals == resultAwayGoals &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    participantId,
    fixtureId,
    grade,
    points,
    resultHomeGoals,
    resultAwayGoals,
    schemaVersion,
  );
}
