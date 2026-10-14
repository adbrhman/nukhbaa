import 'package:shared/shared.dart';

/// A fixture already on the schedule that is the same match as one an admin
/// is about to add (see [SameMatchFinder]).
final class SameMatch {
  /// Creates the description of the fixture found.
  const SameMatch({
    required this.fixtureId,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
  });

  /// The fixture already on the schedule.
  final String fixtureId;

  /// Its home side, as stored.
  final String homeTeam;

  /// Its away side, as stored.
  final String awayTeam;

  /// Its kickoff, in UTC.
  final DateTime kickoffAt;
}

/// Finds the fixture already on the schedule that is the same match as a
/// new one: the same two sides, kicking off between `from` and `to`.
///
/// Read by [RegisterFixtureSchedule] so an admin cannot add a match the
/// fixtures sync (or another admin) already added. Two sides agree when
/// they name the same catalog team, or when their names are equal once
/// spelling is normalised (a club seeded for two competitions can have two
/// catalog rows under one name). Test and hidden fixtures are never the
/// same match.
abstract interface class SameMatchFinder {
  /// The nearest same match, or `null` when there is none.
  Future<Result<SameMatch?>> find({
    required String homeTeam,
    required String awayTeam,
    required String? homeTeamId,
    required String? awayTeamId,
    required DateTime from,
    required DateTime to,
  });
}
