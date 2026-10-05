import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:domain/domain.dart';

// Maps Duel results (migration 0090) to their wire DTOs. Pure. The
// opponent's prediction is read from the DuelView's record, which
// ListMyDuels has already emptied before kickoff.

/// A challenge as one caller sees it.
DuelChallengeDto duelChallengeViewToDto(DuelChallengeView view) {
  final challenge = view.challenge;
  return DuelChallengeDto(
    id: challenge.challengeId.value,
    code: challenge.code.value,
    seasonId: challenge.seasonId.value,
    fixtureId: challenge.fixture.value,
    homeTeam: challenge.homeTeam,
    awayTeam: challenge.awayTeam,
    kickoffAt: challenge.kickoffAt.toUtc().toIso8601String(),
    challengerUserId: challenge.challengerUserId.value,
    challengerName: challenge.challengerName,
    isPrivate: challenge.targetUserId != null,
    capacity: challenge.capacity,
    acceptedCount: challenge.acceptedCount,
    state: view.state.wireValue,
    isMine: view.callerIsChallenger,
    isForMe: view.callerIsTarget,
  );
}

/// The duel an acceptance created.
DuelDto duelToDto(Duel duel) => DuelDto(
  id: duel.id.value,
  challengeId: duel.challengeId.value,
  fixtureId: duel.fixture.value,
  acceptedAt: duel.acceptedAt.toUtc().toIso8601String(),
);

/// One duel from the caller's side.
DuelSummaryDto duelViewToDto(DuelView view) {
  final record = view.record;
  final mine = record.myPick;
  final theirs = record.opponentPick;
  return DuelSummaryDto(
    id: record.duelId.value,
    challengeId: record.challengeId.value,
    fixtureId: record.fixture.value,
    homeTeam: record.homeTeam,
    awayTeam: record.awayTeam,
    kickoffAt: record.kickoffAt.toUtc().toIso8601String(),
    acceptedAt: record.acceptedAt.toUtc().toIso8601String(),
    isChallenger: record.callerIsChallenger,
    opponentUserId: record.opponentUserId.value,
    opponentName: record.opponentName,
    myHomeGoals: mine?.homeGoals,
    myAwayGoals: mine?.awayGoals,
    myIsDouble: mine?.isDouble ?? false,
    opponentHomeGoals: theirs?.homeGoals,
    opponentAwayGoals: theirs?.awayGoals,
    opponentIsDouble: theirs?.isDouble,
    state: view.state.wireValue,
    myPoints: view.myPoints,
    opponentPoints: view.opponentPoints,
    outcome: view.outcome?.wireValue,
  );
}

/// The whole `GET /me/duels` answer.
MyDuelsDto myDuelsToDto(MyDuels duels) => MyDuelsDto(
  challenges: [for (final c in duels.challenges) duelChallengeViewToDto(c)],
  duels: [for (final d in duels.duels) duelViewToDto(d)],
);
