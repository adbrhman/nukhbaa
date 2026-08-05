import 'package:domain/src/competition/fixture_ref.dart';
import 'package:shared/shared.dart';

/// The minimal admin-fed IDENTITY of a fixture — which two sides play and when
/// (Next-Task decision 2026-07-11, option (a)).
final class FixtureSchedule {
  const FixtureSchedule._({
    required this.fixture,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
  });

  const FixtureSchedule.fromStored({
    required this.fixture,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
  });

  static Result<FixtureSchedule> create({
    required FixtureRef fixture,
    required String homeTeam,
    required String awayTeam,
    required DateTime kickoffAt,
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

  @override
  bool operator ==(Object other) =>
      other is FixtureSchedule &&
      other.fixture == fixture &&
      other.homeTeam == homeTeam &&
      other.awayTeam == awayTeam &&
      other.kickoffAt == kickoffAt;

  @override
  int get hashCode => Object.hash(fixture, homeTeam, awayTeam, kickoffAt);

  @override
  String toString() =>
      'FixtureSchedule(fixture: ${fixture.value}, $homeTeam vs $awayTeam '
      'at $kickoffAt)';
}
