import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Who may see, predict and score a fixture (migration 0098).
///
/// * A **hidden** fixture is out of every player-facing read and takes no
///   prediction and no score, for anyone, until an admin shows it again.
///   Nothing attached to it is deleted.
/// * A **test** fixture is seen and predicted by admins only and is never
///   scored, so it can never reach a board, a prize or a champion.
///
/// One place for the rule, so every read and write that applies it agrees.
/// The database repeats it as a backstop (migration 0098 triggers).
final class FixtureVisibility {
  const FixtureVisibility._();

  /// The refusal for a fixture [FixtureVisibility.playable] rules out. One
  /// code for hidden and test alike: a player is not told which.
  static const AppError unavailable = AppError.invariant(
    'prediction.fixture_unavailable',
    'This fixture is not available',
  );

  /// Whether [principal] is an admin.
  static bool isAdmin(AuthenticatedUser principal) =>
      principal.hasRole(PlatformRole.admin);

  /// Whether [principal] may see and predict [schedule]. A fixture with no
  /// schedule row carries neither flag, so it is not ruled out here (the
  /// callers that need a kickoff refuse it on their own).
  static bool playable(AuthenticatedUser principal, FixtureSchedule? schedule) {
    if (schedule == null) return true;
    if (schedule.isHidden) return false;
    return !schedule.isTest || isAdmin(principal);
  }

  /// Whether [schedule] may be shown in a read made by [principal]:
  /// [playable], or any fixture at all for an admin who asked for the
  /// hidden ones too ([includeHidden]).
  static bool listable(
    AuthenticatedUser principal,
    FixtureSchedule? schedule, {
    bool includeHidden = false,
  }) {
    if (includeHidden && isAdmin(principal)) return true;
    return playable(principal, schedule);
  }

  /// Whether [schedule] may be scored now: neither hidden nor a test.
  static bool scorable(FixtureSchedule? schedule) =>
      schedule == null || (!schedule.isHidden && !schedule.isTest);
}
