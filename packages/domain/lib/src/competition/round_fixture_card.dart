import 'package:domain/src/competition/fixture_ref.dart';
import 'package:domain/src/competition/round_id.dart';

/// A [RoundFixture] link enriched with its fixture-schedule identity (team
/// names + kickoff), for the client's prediction-form browse read (Session
/// decision 2026-08-07: `BrowseRoundFixtures` widens the existing
/// `GET /rounds/{id}/fixtures` read instead of adding a new endpoint).
///
/// [homeTeam]/[awayTeam]/[kickoffAt] are nullable: the round-fixture link
/// (Axiom 3) never verifies a schedule exists for the fixture it names, so a
/// linked fixture with no registered schedule yet is a legitimate state, not
/// an error.
final class RoundFixtureCard {
  /// Creates a round-fixture card projection.
  const RoundFixtureCard({
    required this.roundId,
    required this.fixtureId,
    required this.displayOrder,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
  });

  /// The owning round.
  final RoundId roundId;

  /// The referenced fixture (owned by Football Data; referenced by id only).
  final FixtureRef fixtureId;

  /// The 0-based presentation order of this fixture within its round.
  final int displayOrder;

  /// The home side's team name, or `null` if no schedule is registered yet.
  final String? homeTeam;

  /// The away side's team name, or `null` if no schedule is registered yet.
  final String? awayTeam;

  /// The kickoff time, or `null` if no schedule is registered yet.
  final DateTime? kickoffAt;

  @override
  bool operator ==(Object other) =>
      other is RoundFixtureCard &&
      other.roundId == roundId &&
      other.fixtureId == fixtureId &&
      other.displayOrder == displayOrder &&
      other.homeTeam == homeTeam &&
      other.awayTeam == awayTeam &&
      other.kickoffAt == kickoffAt;

  @override
  int get hashCode => Object.hash(
    roundId,
    fixtureId,
    displayOrder,
    homeTeam,
    awayTeam,
    kickoffAt,
  );

  @override
  String toString() =>
      'RoundFixtureCard(round: ${roundId.value}, fixture: '
      '${fixtureId.value}, order: $displayOrder, home: $homeTeam, '
      'away: $awayTeam, kickoff: $kickoffAt)';
}
