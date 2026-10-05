import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

final class FakeDuelChallengeRepository implements DuelChallengeRepository {
  final Map<String, DuelChallenge> challenges = {};
  final List<Duel> accepted = [];
  AppError? failure;
  int acceptCalls = 0;
  int createCalls = 0;

  void seedChallenge(DuelChallenge challenge) =>
      challenges[challenge.id.value] = challenge;

  void failNextWith(AppError error) => failure = error;

  AppError? _takeFailure() {
    final value = failure;
    failure = null;
    return value;
  }

  @override
  Future<Result<DuelChallenge>> createChallenge({
    required SeasonId seasonId,
    required FixtureRef fixture,
    required ParticipantId challengerParticipantId,
    required UserId? targetUserId,
    required int capacity,
    required DateTime nowUtc,
  }) async {
    createCalls++;
    final error = _takeFailure();
    if (error != null) return Result.err(error);
    final challengeResult = DuelChallenge.create(
      id: const DuelChallengeId('11111111-1111-1111-1111-111111111111'),
      code: (DuelCode.tryParse('ABCDEFGHJKMN') as Ok<DuelCode>).value,
      seasonId: seasonId,
      fixture: fixture,
      challengerParticipantId: challengerParticipantId,
      targetUserId: targetUserId,
      capacity: capacity,
      createdAt: nowUtc,
    );
    if (challengeResult is Err<DuelChallenge>) {
      return Result.err(challengeResult.error);
    }
    final challenge = (challengeResult as Ok<DuelChallenge>).value;
    challenges[challenge.id.value] = challenge;
    return Result.ok(challenge);
  }

  @override
  Future<Result<DuelChallenge?>> findChallenge(DuelChallengeId id) async {
    final error = _takeFailure();
    if (error != null) return Result.err(error);
    return Result.ok(challenges[id.value]);
  }

  @override
  Future<Result<Duel>> acceptChallenge({
    required DuelChallengeId challengeId,
    required UserId opponentUserId,
    required DateTime nowUtc,
  }) async {
    acceptCalls++;
    final error = _takeFailure();
    if (error != null) return Result.err(error);
    final challenge = challenges[challengeId.value];
    if (challenge == null) {
      return const Result.err(
        AppError.invariant('social.duel_challenge_not_found', 'missing'),
      );
    }
    final result = Duel.create(
      id: const DuelId('22222222-2222-2222-2222-222222222222'),
      challengeId: challengeId,
      fixture: challenge.fixture,
      challengerParticipantId: challenge.challengerParticipantId,
      opponentParticipantId: ParticipantId(opponentUserId.value),
      acceptedAt: nowUtc,
    );
    if (result is Err<Duel>) return Result.err(result.error);
    final duel = (result as Ok<Duel>).value;
    accepted.add(duel);
    return Result.ok(duel);
  }

  @override
  Future<Result<void>> cancelChallenge({
    required DuelChallengeId challengeId,
    required UserId challengerUserId,
  }) async {
    final error = _takeFailure();
    if (error != null) return Result.err(error);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> declineChallenge({
    required DuelChallengeId challengeId,
    required UserId targetUserId,
  }) async {
    final error = _takeFailure();
    if (error != null) return Result.err(error);
    return const Result.ok(null);
  }
}
