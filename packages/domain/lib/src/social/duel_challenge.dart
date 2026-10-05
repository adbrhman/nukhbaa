import 'package:domain/src/competition/fixture_ref.dart';
import 'package:domain/src/competition/participant_id.dart';
import 'package:domain/src/competition/season_id.dart';
import 'package:domain/src/identity/user_id.dart';
import 'package:domain/src/social/duel_challenge_id.dart';
import 'package:domain/src/social/duel_challenge_status.dart';
import 'package:domain/src/social/duel_code.dart';
import 'package:shared/shared.dart';

/// A shareable invitation to a single fixture duel.
///
/// The challenge is separate from referrals and rankings. It carries only the
/// stored challenge identity and lifecycle. It does not carry accepted-duel
/// rows, predictions, points, winners, or derived expiry state.
final class DuelChallenge {
  const DuelChallenge._({
    required this.id,
    required this.code,
    required this.seasonId,
    required this.fixture,
    required this.challengerParticipantId,
    required this.targetUserId,
    required this.capacity,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Rehydrates a stored challenge. Stored rows have already crossed the DB
  /// integrity boundary, so no business validation is repeated here.
  const DuelChallenge.fromStored({
    required this.id,
    required this.code,
    required this.seasonId,
    required this.fixture,
    required this.challengerParticipantId,
    required this.targetUserId,
    required this.capacity,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Creates a brand-new open challenge.
  ///
  /// Cross-row checks such as season membership, self-targeting, the
  /// thirty-minute fixture lead time, and the ten-pending-challenge cap live
  /// in the application/DB because this aggregate cannot see those rows.
  static Result<DuelChallenge> create({
    required DuelChallengeId id,
    required DuelCode code,
    required SeasonId seasonId,
    required FixtureRef fixture,
    required ParticipantId challengerParticipantId,
    required UserId? targetUserId,
    int capacity = defaultCapacity,
    required DateTime createdAt,
  }) {
    final capacityError = _validateCapacity(capacity, targetUserId);
    if (capacityError != null) {
      return Result.err(capacityError);
    }
    if (!createdAt.isUtc) {
      return const Result.err(
        AppError.validation(
          'social.duel_challenge_created_at_not_utc',
          'createdAt must be provided in UTC',
        ),
      );
    }
    return Result.ok(
      DuelChallenge._(
        id: id,
        code: code,
        seasonId: seasonId,
        fixture: fixture,
        challengerParticipantId: challengerParticipantId,
        targetUserId: targetUserId,
        capacity: capacity,
        status: DuelChallengeStatus.open,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
  }

  /// Minimum accepted challenge capacity.
  static const int minCapacity = 1;

  /// Maximum accepted challenge capacity.
  static const int maxCapacity = 10;

  /// Product default for an open challenge.
  static const int defaultCapacity = 5;

  static AppError? _validateCapacity(int capacity, UserId? targetUserId) {
    if (capacity < minCapacity || capacity > maxCapacity) {
      return const AppError.validation(
        'social.duel_challenge_capacity_out_of_range',
        'Duel challenge capacity must be between 1 and 10',
      );
    }
    if (targetUserId != null && capacity != 1) {
      return const AppError.validation(
        'social.duel_challenge_private_capacity_invalid',
        'A private duel challenge must have capacity one',
      );
    }
    return null;
  }

  /// The challenge identity.
  final DuelChallengeId id;

  /// The shareable invitation code.
  final DuelCode code;

  /// The season that owns the participant links for this challenge.
  final SeasonId seasonId;

  /// The fixture being predicted.
  final FixtureRef fixture;

  /// The creator's season participant, not a raw user id.
  final ParticipantId challengerParticipantId;

  /// The private target, or null for an open shareable challenge.
  final UserId? targetUserId;

  /// Maximum number of accepted [Duel] rows from this invitation.
  final int capacity;

  /// The only persisted challenge lifecycle state.
  final DuelChallengeStatus status;

  /// Creation instant in UTC.
  final DateTime createdAt;

  /// Last lifecycle change in UTC.
  final DateTime updatedAt;

  /// Whether this is a private target challenge.
  bool get isPrivate => targetUserId != null;

  /// Whether the stored challenge lifecycle is open.
  bool get isOpen => status.isOpen;

  /// Whether another accepted duel may be attached at [acceptedCount].
  bool hasCapacity(int acceptedCount) =>
      acceptedCount >= 0 && acceptedCount < capacity;

  /// Closes an open challenge by the challenger.
  Result<DuelChallenge> cancel({required DateTime at}) {
    return _close(DuelChallengeStatus.cancelled, at);
  }

  /// Closes an open private challenge as declined.
  ///
  /// Authorization against the actual caller is an application concern. The
  /// domain still requires a private target because a public challenge has no
  /// single person who can decline it.
  Result<DuelChallenge> decline({required DateTime at}) {
    if (targetUserId == null) {
      return const Result.err(
        AppError.invariant(
          'social.duel_challenge_decline_requires_target',
          'Only a private duel challenge can be declined',
        ),
      );
    }
    return _close(DuelChallengeStatus.declined, at);
  }

  Result<DuelChallenge> _close(DuelChallengeStatus nextStatus, DateTime at) {
    if (!status.isOpen) {
      return const Result.err(
        AppError.invariant(
          'social.duel_challenge_not_open',
          'A closed duel challenge cannot change state',
        ),
      );
    }
    if (!at.isUtc) {
      return const Result.err(
        AppError.validation(
          'social.duel_challenge_updated_at_not_utc',
          'updatedAt must be provided in UTC',
        ),
      );
    }
    return Result.ok(
      DuelChallenge._(
        id: id,
        code: code,
        seasonId: seasonId,
        fixture: fixture,
        challengerParticipantId: challengerParticipantId,
        targetUserId: targetUserId,
        capacity: capacity,
        status: nextStatus,
        createdAt: createdAt,
        updatedAt: at,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DuelChallenge &&
      other.id == id &&
      other.code == code &&
      other.seasonId == seasonId &&
      other.fixture == fixture &&
      other.challengerParticipantId == challengerParticipantId &&
      other.targetUserId == targetUserId &&
      other.capacity == capacity &&
      other.status == status &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    code,
    seasonId,
    fixture,
    challengerParticipantId,
    targetUserId,
    capacity,
    status,
    createdAt,
    updatedAt,
  );

  @override
  String toString() =>
      'DuelChallenge(${id.value}, ${status.wireValue}, ${code.value})';
}
