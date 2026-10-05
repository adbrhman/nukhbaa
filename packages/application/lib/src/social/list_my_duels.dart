import 'package:application/src/common/clock.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/social/duel_views.dart';
import 'package:application/src/social/ports/duel_reader.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: the caller's open challenges and duels.
///
/// The opponent's prediction is hidden until kickoff, the same rule every
/// other player's prediction follows. Points and the winner come only from
/// the official fixture scores (`scoring.fixture_scores`, double included)
/// once both sides are final; nothing about a duel's result is stored.
final class ListMyDuels {
  /// Creates the use-case.
  const ListMyDuels({required DuelReader duels, required Clock clock})
    : _duels = duels,
      _clock = clock;

  final DuelReader _duels;
  final Clock _clock;

  /// How far back settled duels are listed.
  static const Duration history = Duration(days: 35);

  /// Most challenges answered at once.
  static const int challengeLimit = 50;

  /// Most duels answered at once.
  static const int duelLimit = 100;

  /// Lists the caller's challenges and duels.
  Future<Result<MyDuels>> call({required AuthenticatedUser principal}) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);

    final now = _clock.nowUtc();

    final challengesResult = await _duels.listOpenChallengesFor(
      userId: principal.userId,
      now: now,
      limit: challengeLimit,
    );
    if (challengesResult is Err<List<DuelChallengePreview>>) {
      return Result.err(challengesResult.error);
    }
    final challenges =
        (challengesResult as Ok<List<DuelChallengePreview>>).value;

    final duelsResult = await _duels.listDuelsFor(
      userId: principal.userId,
      since: now.subtract(history),
      limit: duelLimit,
    );
    if (duelsResult is Err<List<DuelRecord>>) {
      return Result.err(duelsResult.error);
    }
    final records = (duelsResult as Ok<List<DuelRecord>>).value;

    return Result.ok(
      MyDuels(
        challenges: List<DuelChallengeView>.unmodifiable([
          for (final challenge in challenges)
            DuelChallengeView(
              challenge: challenge,
              state: challenge.stateAt(now),
              callerIsChallenger:
                  challenge.challengerUserId == principal.userId,
              callerIsTarget: challenge.targetUserId == principal.userId,
            ),
        ]),
        duels: List<DuelView>.unmodifiable([
          for (final record in records) view(record, now),
        ]),
      ),
    );
  }

  /// What the caller may see of [record] at [now].
  static DuelView view(DuelRecord record, DateTime now) {
    final kickedOff = !now.isBefore(record.kickoffAt);
    final mine = record.myScore;
    final theirs = record.opponentScore;
    if (mine == null || theirs == null || !mine.isFinal || !theirs.isFinal) {
      return DuelView(
        record: kickedOff ? record : record.withoutOpponentPick(),
        state: kickedOff ? DuelState.live : DuelState.upcoming,
        myPoints: null,
        opponentPoints: null,
        outcome: null,
      );
    }
    final DuelOutcome outcome;
    if (mine.points > theirs.points) {
      outcome = DuelOutcome.won;
    } else if (mine.points < theirs.points) {
      outcome = DuelOutcome.lost;
    } else {
      outcome = DuelOutcome.draw;
    }
    return DuelView(
      record: record,
      state: DuelState.settled,
      myPoints: mine.points,
      opponentPoints: theirs.points,
      outcome: outcome,
    );
  }
}
