import 'package:application/application.dart';
import 'package:contracts/contracts.dart';

/// Projects the server-composed single-user prediction history to the wire DTO.
AdminUserPredictionHistoryDto adminUserPredictionHistoryToDto(
  AdminUserPredictionHistory history,
) {
  final user = UserSummaryDto(
    id: history.user.id.value,
    email: history.user.email,
    displayName: history.user.displayName,
    status: history.user.status.name,
  );
  return AdminUserPredictionHistoryDto(
    user: user,
    predictionCount: history.predictionCount,
    exactCount: history.exactCount,
    correctDoubleCount: history.correctDoubleCount,
    totalPoints: history.totalPoints,
    predictions: [
      for (final row in history.predictions)
        AdminUserPredictionRowDto(
          predictionId: row.predictionId.value,
          fixtureId: row.fixtureId.value,
          kickoffAt: row.kickoffAt.toUtc().toIso8601String(),
          leagueName: row.leagueName,
          leagueLogoUrl: row.leagueLogoUrl,
          homeTeam: row.homeTeam,
          awayTeam: row.awayTeam,
          predictedHomeGoals: row.predictedHomeGoals,
          predictedAwayGoals: row.predictedAwayGoals,
          finalHomeGoals: row.finalHomeGoals,
          finalAwayGoals: row.finalAwayGoals,
          grade: row.grade.wireValue,
          isDouble: row.isDouble,
          points: row.points,
        ),
    ],
  );
}
