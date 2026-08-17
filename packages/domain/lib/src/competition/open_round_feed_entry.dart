import 'package:domain/src/competition/competition_id.dart';
import 'package:domain/src/competition/round_id.dart';

/// One **open**, publicly-visible round joined with its owning competition's
/// display facts — the row shape of the `GET /feed/matches` aggregate read
/// (server-side fan-in decision, replacing the client-side
/// competition → season → round drill-down).
///
/// This is a cross-aggregate *projection*, not a member of either the
/// `Competition` or `Round` aggregate: it exists solely to carry exactly what
/// the feed needs (a competition's display name + a round's identity and
/// frozen ruleset version) out of a single joined query, mirroring
/// [RoundFixtureCard]'s role for the fixtures browse read. It never crosses
/// back into a write path and carries no group reference (Axiom 4) and no
/// points (Axiom 5).
final class OpenRoundFeedEntry {
  /// Creates a feed entry.
  const OpenRoundFeedEntry({
    required this.competitionId,
    required this.competitionName,
    required this.roundId,
    required this.rulesetVersion,
  });

  /// The owning competition's identity.
  final CompetitionId competitionId;

  /// The owning competition's display name.
  final String competitionName;

  /// The open round's identity.
  final RoundId roundId;

  /// The round's frozen ruleset version (never the opaque snapshot).
  final int rulesetVersion;

  @override
  bool operator ==(Object other) =>
      other is OpenRoundFeedEntry &&
      other.competitionId == competitionId &&
      other.competitionName == competitionName &&
      other.roundId == roundId &&
      other.rulesetVersion == rulesetVersion;

  @override
  int get hashCode =>
      Object.hash(competitionId, competitionName, roundId, rulesetVersion);

  @override
  String toString() =>
      'OpenRoundFeedEntry(competition: ${competitionId.value} '
      '"$competitionName", round: ${roundId.value}, '
      'rulesetVersion: $rulesetVersion)';
}
