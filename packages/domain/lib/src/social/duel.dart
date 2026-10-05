import 'package:domain/src/competition/fixture_ref.dart';
import 'package:domain/src/competition/participant_id.dart';
import 'package:domain/src/social/duel_challenge_id.dart';
import 'package:domain/src/social/duel_id.dart';
import 'package:shared/shared.dart';

/// One accepted confrontation created from a [DuelChallenge].
///
/// This entity intentionally stores no copied prediction, winner, points,
/// settled state, or draw state. Predictions remain in
/// `prediction.fixture_predictions` and scoring remains the single source of
/// official fixture points.
final class Duel {
  const Duel._({
    required this.id,
    required this.challengeId,
    required this.fixture,
    required this.challengerParticipantId,
    required this.opponentParticipantId,
    required this.acceptedAt,
    required this.createdAt,
  });

  /// Rehydrates an accepted duel from trusted storage.
  const Duel.fromStored({
    required this.id,
    required this.challengeId,
    required this.fixture,
    required this.challengerParticipantId,
    required this.opponentParticipantId,
    required this.acceptedAt,
    required this.createdAt,
  });

  /// Creates an accepted duel after the application has completed its
  /// cross-aggregate acceptance checks and the DB transaction has locked the
  /// challenge row.
  static Result<Duel> create({
    required DuelId id,
    required DuelChallengeId challengeId,
    required FixtureRef fixture,
    required ParticipantId challengerParticipantId,
    required ParticipantId opponentParticipantId,
    required DateTime acceptedAt,
  }) {
    if (challengerParticipantId == opponentParticipantId) {
      return const Result.err(
        AppError.invariant(
          'social.duel_participants_must_differ',
          'A duel must have two different participants',
        ),
      );
    }
    if (!acceptedAt.isUtc) {
      return const Result.err(
        AppError.validation(
          'social.duel_accepted_at_not_utc',
          'acceptedAt must be provided in UTC',
        ),
      );
    }
    return Result.ok(
      Duel._(
        id: id,
        challengeId: challengeId,
        fixture: fixture,
        challengerParticipantId: challengerParticipantId,
        opponentParticipantId: opponentParticipantId,
        acceptedAt: acceptedAt,
        createdAt: acceptedAt,
      ),
    );
  }

  /// The accepted duel identity.
  final DuelId id;

  /// The invitation from which this duel was accepted.
  final DuelChallengeId challengeId;

  /// The fixture both participants forecast.
  final FixtureRef fixture;

  /// The original challenge creator's season participant.
  final ParticipantId challengerParticipantId;

  /// The accepted opponent's season participant.
  final ParticipantId opponentParticipantId;

  /// When acceptance became effective (UTC).
  final DateTime acceptedAt;

  /// Storage creation instant (UTC).
  final DateTime createdAt;

  /// Whether [participantId] is one of the two duel participants.
  bool containsParticipant(ParticipantId participantId) =>
      participantId == challengerParticipantId ||
      participantId == opponentParticipantId;

  /// Returns the other participant, or null for a non-member.
  ParticipantId? opponentOf(ParticipantId participantId) {
    if (participantId == challengerParticipantId) {
      return opponentParticipantId;
    }
    if (participantId == opponentParticipantId) {
      return challengerParticipantId;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is Duel &&
      other.id == id &&
      other.challengeId == challengeId &&
      other.fixture == fixture &&
      other.challengerParticipantId == challengerParticipantId &&
      other.opponentParticipantId == opponentParticipantId &&
      other.acceptedAt == acceptedAt &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    id,
    challengeId,
    fixture,
    challengerParticipantId,
    opponentParticipantId,
    acceptedAt,
    createdAt,
  );

  @override
  String toString() =>
      'Duel(${id.value}, fixture: ${fixture.value}, '
      '${challengerParticipantId.value} vs ${opponentParticipantId.value})';
}
