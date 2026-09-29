/// Maps the champions of the monthly contests (migration 0077) to their wire
/// shapes. The picture URLs are built here, at the HTTP edge, the one layer
/// that owns the route shapes.
library;

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:domain/domain.dart';
import 'package:server/http/avatar_url.dart';

/// The server-relative URL of a champion's celebration picture. The `v`
/// parameter is the picture's time in epoch milliseconds: a replaced picture
/// is a new URL, so no device keeps the old one from its cache.
String championPhotoUrlOf({
  required SeasonId seasonId,
  required UserId userId,
  required DateTime updatedAt,
}) =>
    '/champions/${seasonId.value}/photos/${userId.value}'
    '?v=${updatedAt.toUtc().millisecondsSinceEpoch}';

/// One crowned champion on the wire. The celebration runs for the first
/// [ListMonthChampions.celebrationWindow] of the next month.
MonthChampionDto monthChampionToDto(MonthChampion champion) {
  final DateTime? photoAt = champion.photoUpdatedAt;
  final DateTime? avatarAt = champion.avatarUpdatedAt;
  final DateTime crownedAt = champion.crownedAt.toUtc();
  return MonthChampionDto(
    seasonId: champion.seasonId.value,
    seasonLabel: champion.seasonLabel,
    userId: champion.userId.value,
    displayName: champion.displayName,
    points: champion.points,
    exactCount: champion.exactCount,
    decidedCount: champion.decidedCount,
    referralPoints: champion.referralPoints,
    crownedAt: crownedAt.toIso8601String(),
    celebrateUntil: ListMonthChampions.celebrateUntil(
      champion,
    ).toIso8601String(),
    photoUrl: photoAt == null
        ? null
        : championPhotoUrlOf(
            seasonId: champion.seasonId,
            userId: champion.userId,
            updatedAt: photoAt,
          ),
    avatarUrl: avatarAt == null
        ? null
        : avatarUrlOf(userId: champion.userId, updatedAt: avatarAt),
    prize: champion.prize,
  );
}

/// A month's champions on the wire.
MonthChampionsDto monthChampionsToDto(List<MonthChampion> champions) =>
    MonthChampionsDto(
      champions: [
        for (final MonthChampion champion in champions)
          monthChampionToDto(champion),
      ],
    );

/// The admin's crowning preview on the wire.
ChampionCandidatesDto championCandidatesToDto(ChampionCandidates preview) =>
    ChampionCandidatesDto(
      seasonId: preview.month.seasonId.value,
      seasonLabel: preview.month.label,
      ended: preview.ended,
      unscoredFixtures: preview.month.unscoredFixtures,
      crowned: [for (final UserId id in preview.month.crowned) id.value],
      candidates: [
        for (final ChampionCandidate line in preview.candidates)
          _candidateToDto(line),
      ],
    );

ChampionCandidateDto _candidateToDto(ChampionCandidate line) {
  final UserId? avatarUser = line.entry.avatarUserId;
  final DateTime? avatarAt = line.entry.avatarUpdatedAt;
  return ChampionCandidateDto(
    rank: line.entry.rank,
    userId: line.userId.value,
    displayName: line.entry.displayName,
    points: line.entry.totalPoints,
    exactCount: line.entry.exactCount,
    decidedCount: line.entry.decidedCount,
    referralPoints: line.entry.referralPoints,
    avatarUrl: avatarUser == null || avatarAt == null
        ? null
        : avatarUrlOf(userId: avatarUser, updatedAt: avatarAt),
  );
}
