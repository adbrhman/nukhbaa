/// Versioned wire shapes for the admin read of ONE user's fixture-prediction
/// history. The server joins the already-existing prediction, fixture schedule,
/// result and score read models; no client-side point calculation is involved.
library;

import 'package:contracts/src/admin_dto.dart';

/// One row in the selected user's prediction history.
final class AdminUserPredictionRowDto {
  const AdminUserPredictionRowDto({
    required this.predictionId,
    required this.fixtureId,
    required this.kickoffAt,
    required this.homeTeam,
    required this.awayTeam,
    required this.predictedHomeGoals,
    required this.predictedAwayGoals,
    required this.grade,
    required this.isDouble,
    this.leagueName,
    this.leagueLogoUrl,
    this.finalHomeGoals,
    this.finalAwayGoals,
    this.points,
    this.schemaVersion = currentSchemaVersion,
  });

  factory AdminUserPredictionRowDto.fromJson(Map<String, Object?> json) {
    return AdminUserPredictionRowDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      predictionId: json['prediction_id']! as String,
      fixtureId: json['fixture_id']! as String,
      kickoffAt: json['kickoff_at']! as String,
      leagueName: json['league_name'] as String?,
      leagueLogoUrl: json['league_logo_url'] as String?,
      homeTeam: json['home_team']! as String,
      awayTeam: json['away_team']! as String,
      predictedHomeGoals: json['predicted_home_goals']! as int,
      predictedAwayGoals: json['predicted_away_goals']! as int,
      finalHomeGoals: json['final_home_goals'] as int?,
      finalAwayGoals: json['final_away_goals'] as int?,
      grade: json['grade']! as String,
      isDouble: (json['is_double'] as bool?) ?? false,
      points: json['points'] as int?,
    );
  }

  static const int currentSchemaVersion = 1;

  final String predictionId;
  final String fixtureId;
  final String kickoffAt;
  final String? leagueName;
  final String? leagueLogoUrl;
  final String homeTeam;
  final String awayTeam;
  final int predictedHomeGoals;
  final int predictedAwayGoals;
  final int? finalHomeGoals;
  final int? finalAwayGoals;
  final String grade;
  final bool isDouble;
  final int? points;
  final int schemaVersion;

  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'prediction_id': predictionId,
    'fixture_id': fixtureId,
    'kickoff_at': kickoffAt,
    if (leagueName != null) 'league_name': leagueName,
    if (leagueLogoUrl != null) 'league_logo_url': leagueLogoUrl,
    'home_team': homeTeam,
    'away_team': awayTeam,
    'predicted_home_goals': predictedHomeGoals,
    'predicted_away_goals': predictedAwayGoals,
    if (finalHomeGoals != null) 'final_home_goals': finalHomeGoals,
    if (finalAwayGoals != null) 'final_away_goals': finalAwayGoals,
    'grade': grade,
    'is_double': isDouble,
    if (points != null) 'points': points,
  };

  @override
  bool operator ==(Object other) =>
      other is AdminUserPredictionRowDto &&
      other.predictionId == predictionId &&
      other.fixtureId == fixtureId &&
      other.kickoffAt == kickoffAt &&
      other.leagueName == leagueName &&
      other.leagueLogoUrl == leagueLogoUrl &&
      other.homeTeam == homeTeam &&
      other.awayTeam == awayTeam &&
      other.predictedHomeGoals == predictedHomeGoals &&
      other.predictedAwayGoals == predictedAwayGoals &&
      other.finalHomeGoals == finalHomeGoals &&
      other.finalAwayGoals == finalAwayGoals &&
      other.grade == grade &&
      other.isDouble == isDouble &&
      other.points == points &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    predictionId,
    fixtureId,
    kickoffAt,
    leagueName,
    leagueLogoUrl,
    homeTeam,
    awayTeam,
    predictedHomeGoals,
    predictedAwayGoals,
    finalHomeGoals,
    finalAwayGoals,
    grade,
    isDouble,
    points,
    schemaVersion,
  );
}

/// The selected user's summary and prediction rows.
final class AdminUserPredictionHistoryDto {
  const AdminUserPredictionHistoryDto({
    required this.user,
    required this.predictionCount,
    required this.exactCount,
    required this.correctDoubleCount,
    required this.totalPoints,
    required this.predictions,
    this.schemaVersion = currentSchemaVersion,
  });

  factory AdminUserPredictionHistoryDto.fromJson(Map<String, Object?> json) {
    final raw = json['predictions']! as List<Object?>;
    return AdminUserPredictionHistoryDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      user: UserSummaryDto.fromJson(
        (json['user']! as Map<Object?, Object?>).cast<String, Object?>(),
      ),
      predictionCount: json['prediction_count']! as int,
      exactCount: json['exact_count']! as int,
      correctDoubleCount: json['correct_double_count']! as int,
      totalPoints: json['total_points']! as int,
      predictions: raw
          .map(
            (e) => AdminUserPredictionRowDto.fromJson(
              (e! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
    );
  }

  static const int currentSchemaVersion = 1;

  final UserSummaryDto user;
  final int predictionCount;
  final int exactCount;
  final int correctDoubleCount;
  final int totalPoints;
  final List<AdminUserPredictionRowDto> predictions;
  final int schemaVersion;

  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'user': user.toJson(),
    'prediction_count': predictionCount,
    'exact_count': exactCount,
    'correct_double_count': correctDoubleCount,
    'total_points': totalPoints,
    'predictions': [for (final row in predictions) row.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is AdminUserPredictionHistoryDto &&
      other.user == user &&
      other.predictionCount == predictionCount &&
      other.exactCount == exactCount &&
      other.correctDoubleCount == correctDoubleCount &&
      other.totalPoints == totalPoints &&
      _listEquals(other.predictions, predictions) &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    user,
    predictionCount,
    exactCount,
    correctDoubleCount,
    totalPoints,
    Object.hashAll(predictions),
    schemaVersion,
  );

  static bool _listEquals(
    List<AdminUserPredictionRowDto> a,
    List<AdminUserPredictionRowDto> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
