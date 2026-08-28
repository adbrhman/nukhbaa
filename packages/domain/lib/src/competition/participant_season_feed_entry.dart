import 'package:domain/src/competition/competition_id.dart';
import 'package:domain/src/competition/season_id.dart';

/// One season a user is **actively** participating in, right now, joined with
/// its owning competition's display facts — the row shape backing a "my
/// seasons" feed read (the participant-scoped analogue of
/// [OpenRoundFeedEntry]'s platform-wide round feed).
///
/// A cross-aggregate *projection*, not a member of the `Participant`,
/// `CompetitionSeason`, or `Competition` aggregate: it exists solely to carry
/// exactly what a "which seasons am I actively in, currently" read needs out
/// of a single joined query, so the client can then fan out to the
/// already-existing `BrowseSeasonFixtures` read (`GET /seasons/{id}/fixtures`)
/// per season. It never crosses back into a write path.
final class ParticipantSeasonFeedEntry {
  /// Creates a feed entry.
  const ParticipantSeasonFeedEntry({
    required this.competitionId,
    required this.competitionName,
    required this.seasonId,
    required this.seasonLabel,
    required this.startAt,
    required this.endAt,
  });

  /// The owning competition's identity.
  final CompetitionId competitionId;

  /// The owning competition's display name.
  final String competitionName;

  /// The season's identity — the key the client uses to fetch its fixtures.
  final SeasonId seasonId;

  /// The season's display label.
  final String seasonLabel;

  /// UTC instant the season's calendar window opens (inclusive).
  final DateTime startAt;

  /// UTC instant the season's calendar window closes (exclusive).
  final DateTime endAt;

  @override
  bool operator ==(Object other) =>
      other is ParticipantSeasonFeedEntry &&
      other.competitionId == competitionId &&
      other.competitionName == competitionName &&
      other.seasonId == seasonId &&
      other.seasonLabel == seasonLabel &&
      other.startAt == startAt &&
      other.endAt == endAt;

  @override
  int get hashCode => Object.hash(
    competitionId,
    competitionName,
    seasonId,
    seasonLabel,
    startAt,
    endAt,
  );

  @override
  String toString() =>
      'ParticipantSeasonFeedEntry(competition: ${competitionId.value} '
      '"$competitionName", season: ${seasonId.value} "$seasonLabel", '
      '$startAt - $endAt)';
}
