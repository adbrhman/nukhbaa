import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Product invariants shared by the Duel application commands.
///
/// The database migration 0090 mirrors these values as its final backstop.
/// Cross-row limits such as the pending count remain storage-owned because the
/// application has no transaction boundary of its own.
final class DuelPolicy {
  const DuelPolicy._();

  /// Default number of accepted duels for an open invitation.
  static const int defaultCapacity = DuelChallenge.defaultCapacity;

  /// Maximum number of accepted duels from one invitation.
  static const int maxCapacity = DuelChallenge.maxCapacity;

  /// Minimum number of minutes before kickoff required to create a challenge.
  static const int minimumLeadMinutes = 30;

  /// Maximum number of still-pending invitations a challenger may have.
  /// The database serializes and enforces this value.
  static const int maxPendingChallenges = 10;

  static Result<void> validateCapacity({
    required int capacity,
    required UserId? targetUserId,
  }) {
    if (capacity < DuelChallenge.minCapacity ||
        capacity > DuelChallenge.maxCapacity) {
      return const Result.err(
        AppError.validation(
          'social.duel_capacity_out_of_range',
          'Duel challenge capacity must be between 1 and 10',
        ),
      );
    }
    if (targetUserId != null && capacity != 1) {
      return const Result.err(
        AppError.validation(
          'social.duel_private_capacity_invalid',
          'A private duel challenge must have capacity one',
        ),
      );
    }
    return const Result.ok(null);
  }
}
