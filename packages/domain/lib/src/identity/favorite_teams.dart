import 'package:domain/src/football_data/team_ref.dart';
import 'package:shared/shared.dart';

/// The teams a user follows (plan P3-1, migration 0065): the audience of the
/// pre-match push (plan P3-4a).
///
/// **At most [max] teams, each once.** The limit keeps that push bounded -- a
/// user who followed every club would be pinged before every match -- and it
/// lives here rather than in SQL because the server is the only writer.
///
/// Order is the caller's: teams are kept as given, repeats dropped.
final class FavoriteTeams {
  const FavoriteTeams._(this.teams);

  /// The most teams one user may follow.
  static const int max = 3;

  /// A user who follows no team.
  static const FavoriteTeams none = FavoriteTeams._(<TeamRef>[]);

  /// Builds the set from [teams], dropping repeats, or a validation error
  /// when more than [max] distinct teams are given.
  static Result<FavoriteTeams> tryCreate(List<TeamRef> teams) {
    final distinct = <TeamRef>[];
    for (final team in teams) {
      if (!distinct.contains(team)) {
        distinct.add(team);
      }
    }
    if (distinct.length > max) {
      return const Result.err(
        AppError.validation(
          'identity.favorite_teams_too_many',
          'At most three favorite teams',
        ),
      );
    }
    return Result.ok(FavoriteTeams._(List<TeamRef>.unmodifiable(distinct)));
  }

  /// The teams, in the order given.
  final List<TeamRef> teams;

  @override
  bool operator ==(Object other) {
    if (other is! FavoriteTeams || other.teams.length != teams.length) {
      return false;
    }
    for (var i = 0; i < teams.length; i++) {
      if (other.teams[i] != teams[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(teams);

  @override
  String toString() => 'FavoriteTeams($teams)';
}
