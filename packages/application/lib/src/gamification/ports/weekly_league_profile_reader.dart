import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Read port for the names and pictures a weekly-league table draws (P2-7b).
///
/// Backed by `PostgresWeeklyLeagueProfileReader`. The league's own types are
/// names-free on purpose: `WeeklyLeagueEntry` and `WeeklyLeaguePolicy` rank
/// [UserId]s and never hold a person's name, so the rules stay testable
/// without one. Who a row belongs to is asked here instead, once per read,
/// for exactly the members of the group.
///
/// Keyed by USER. `ParticipantReader` answers the same kind of question keyed
/// by participant, and a participant belongs to one monthly season, while a
/// weekly-league member is a user who may hold no participation at all.
///
/// General contract (Application ADR, Section 2): MUST NOT throw -- every
/// outcome is a typed [Result]; MUST map infrastructure failures to
/// [ErrorKind.transient].
abstract interface class WeeklyLeagueProfileReader {
  /// The profile of each of [userIds], keyed by user.
  ///
  /// A user with no stored profile is simply absent from the map (never an
  /// error): the table then draws that row without a name instead of losing
  /// the standings.
  Future<Result<Map<UserId, WeeklyLeagueMemberProfile>>> profilesOf(
    List<UserId> userIds,
  );
}

/// What a weekly-league row needs to be recognised: a name and, when there is
/// one, the version of the member's profile picture.
///
/// The picture is carried as the fact its URL is built from -- the version --
/// never as a URL: the read route is an HTTP surface owned by the server
/// (`avatarUrlOf`), not by the application layer. The owner is the key this
/// profile sits under.
final class WeeklyLeagueMemberProfile {
  /// Creates a profile.
  const WeeklyLeagueMemberProfile({
    required this.displayName,
    this.avatarUpdatedAt,
  });

  /// The platform-owned display name of the member.
  final String displayName;

  /// When the member's picture was last replaced, or null when they have
  /// none. It is the picture's version: a new picture is a new timestamp.
  final DateTime? avatarUpdatedAt;

  @override
  bool operator ==(Object other) =>
      other is WeeklyLeagueMemberProfile &&
      other.displayName == displayName &&
      other.avatarUpdatedAt == avatarUpdatedAt;

  @override
  int get hashCode => Object.hash(displayName, avatarUpdatedAt);
}
