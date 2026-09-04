import 'package:domain/src/competition/fixture_ref.dart';
import 'package:domain/src/football_data/team_ref.dart';
import 'package:shared/shared.dart';

/// The minimal admin-fed IDENTITY of a fixture — which two sides play and when
/// (Next-Task decision 2026-07-11, option (a)).
///
/// [homeTeamId]/[awayTeamId] are an ADDITIVE enrichment (Football Data phase,
/// migration `0024_fixture_schedule_team_ids.sql`): an optional link to the
/// canonical [Team] each side names, so a client can resolve a real crest
/// instead of a letter placeholder. `null` on either side is a legitimate
/// state — a legacy fixture registered before this field existed, or an
/// admin who picked a team not yet in the Football Data catalog — never an
/// error; [homeTeam]/[awayTeam] (free text) remain the fixture's identity of
/// record either way (Axiom 3: team identity travels as free text on the
/// wire, Next-Task decision 2026-07-11, option (a) — this field only adds a
/// *resolvable* enrichment on top, it never replaces the free-text name).
final class FixtureSchedule {
  const FixtureSchedule._({
    required this.fixture,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
    this.homeTeamId,
    this.awayTeamId,
  });

  const FixtureSchedule.fromStored({
    required this.fixture,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
    this.homeTeamId,
    this.awayTeamId,
  });

  static Result<FixtureSchedule> create({
    required FixtureRef fixture,
    required String homeTeam,
    required String awayTeam,
    required DateTime kickoffAt,
    TeamRef? homeTeamId,
    TeamRef? awayTeamId,
  }) {
    final trimmedHome = homeTeam.trim();
    final trimmedAway = awayTeam.trim();

    final homeError = _validateTeamName('home', trimmedHome);
    if (homeError != null) {
      return Result.err(homeError);
    }
    final awayError = _validateTeamName('away', trimmedAway);
    if (awayError != null) {
      return Result.err(awayError);
    }
    if (trimmedHome.toLowerCase() == trimmedAway.toLowerCase()) {
      return const Result.err(
        AppError.validation(
          'competition.fixture_schedule_same_team',
          'A fixture must have two distinct teams',
        ),
      );
    }

    return Result.ok(
      FixtureSchedule._(
        fixture: fixture,
        homeTeam: trimmedHome,
        awayTeam: trimmedAway,
        kickoffAt: kickoffAt,
        homeTeamId: homeTeamId,
        awayTeamId: awayTeamId,
      ),
    );
  }

  static AppError? _validateTeamName(String side, String name) {
    if (name.isEmpty || name.length > 120) {
      return AppError.validation(
        'competition.fixture_schedule_team_len',
        'The $side team name must be between 1 and 120 characters',
      );
    }
    return null;
  }

  final FixtureRef fixture;
  final String homeTeam;
  final String awayTeam;
  final DateTime kickoffAt;
  final TeamRef? homeTeamId;
  final TeamRef? awayTeamId;

  @override
  bool operator ==(Object other) =>
      other is FixtureSchedule &&
      other.fixture == fixture &&
      other.homeTeam == homeTeam &&
      other.awayTeam == awayTeam &&
      other.kickoffAt == kickoffAt &&
      other.homeTeamId == homeTeamId &&
      other.awayTeamId == awayTeamId;

  @override
  int get hashCode => Object.hash(
    fixture,
    homeTeam,
    awayTeam,
    kickoffAt,
    homeTeamId,
    awayTeamId,
  );

  @override
  String toString() =>
      'FixtureSchedule(fixture: ${fixture.value}, $homeTeam vs $awayTeam '
      'at $kickoffAt)';
}
