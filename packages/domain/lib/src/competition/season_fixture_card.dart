import 'package:domain/src/competition/fixture_ref.dart';
import 'package:domain/src/competition/season_id.dart';

/// A [SeasonFixture] link enriched with its fixture-schedule identity (team
/// names + kickoff), for the per-fixture Prediction browse read (Axiom 4
/// Amendment — the season-scoped sibling of [RoundFixtureCard], since a
/// fixture's prediction belongs to its season directly via [SeasonFixture],
/// never a round).
///
/// [homeTeam]/[awayTeam]/[kickoffAt] are nullable: the season-fixture link
/// (Axiom 3) never verifies a schedule exists for the fixture it names, so a
/// linked fixture with no registered schedule yet is a legitimate state, not
/// an error.
final class SeasonFixtureCard {
  /// Creates a season-fixture card projection.
  const SeasonFixtureCard({
    required this.seasonId,
    required this.fixtureId,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
  });

  /// The owning season.
  final SeasonId seasonId;

  /// The referenced fixture (owned by Football Data; referenced by id only).
  final FixtureRef fixtureId;

  /// The home side's team name, or `null` if no schedule is registered yet.
  final String? homeTeam;

  /// The away side's team name, or `null` if no schedule is registered yet.
  final String? awayTeam;

  /// The kickoff time, or `null` if no schedule is registered yet.
  final DateTime? kickoffAt;

  @override
  bool operator ==(Object other) =>
      other is SeasonFixtureCard &&
      other.seasonId == seasonId &&
      other.fixtureId == fixtureId &&
      other.homeTeam == homeTeam &&
      other.awayTeam == awayTeam &&
      other.kickoffAt == kickoffAt;

  @override
  int get hashCode =>
      Object.hash(seasonId, fixtureId, homeTeam, awayTeam, kickoffAt);

  @override
  String toString() =>
      'SeasonFixtureCard(season: ${seasonId.value}, fixture: '
      '${fixtureId.value}, home: $homeTeam, away: $awayTeam, '
      'kickoff: $kickoffAt)';
}
