import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Who a duel notification goes to and what it names (migration 0092).
final class DuelNotice {
  /// Creates the notice.
  const DuelNotice({
    required this.recipientUserId,
    required this.actorUserId,
    required this.actorName,
    required this.code,
    required this.homeTeam,
    required this.awayTeam,
    required this.tokens,
    this.utcOffsetMinutes,
  });

  /// The player told.
  final UserId recipientUserId;

  /// The player whose action it was: the challenger, or the one who accepted.
  final UserId actorUserId;

  /// The actor's display name.
  final String actorName;

  /// The challenge's share code.
  final String code;

  /// Home side, as the schedule names it.
  final String homeTeam;

  /// Away side, as the schedule names it.
  final String awayTeam;

  /// The recipient's push tokens; empty when they have no device.
  final List<String> tokens;

  /// Minutes the recipient's clock is ahead of UTC, as last reported.
  final int? utcOffsetMinutes;
}

/// Reads who to tell about a duel event and what to say.
abstract interface class DuelNoticeReader {
  /// The private target of [challengeId], told by its challenger; `Ok(null)`
  /// when the challenge has no target or does not exist.
  Future<Result<DuelNotice?>> challengedNotice(DuelChallengeId challengeId);

  /// The challenger behind [duelId], told by the player who accepted;
  /// `Ok(null)` when the duel does not exist.
  Future<Result<DuelNotice?>> acceptedNotice(DuelId duelId);
}
