import 'package:shared/shared.dart';

/// The only lifecycle states physically stored for a duel challenge.
///
/// Accepted/active, expired, settled and draw are derived states and must not
/// become another persisted state machine.
enum DuelChallengeStatus {
  /// The challenge can still accept a duel, subject to fixture time and the
  /// challenge capacity.
  open,

  /// The challenger closed the invitation before it was filled.
  cancelled,

  /// The private target declined the invitation.
  declined;

  /// Stable wire/storage token.
  String get wireValue => switch (this) {
    DuelChallengeStatus.open => 'open',
    DuelChallengeStatus.cancelled => 'cancelled',
    DuelChallengeStatus.declined => 'declined',
  };

  /// Whether the challenge is still open for the application path.
  bool get isOpen => this == DuelChallengeStatus.open;

  /// Parses a stored or wire token without silently defaulting unknown data.
  static Result<DuelChallengeStatus> tryParse(String? raw) {
    for (final value in DuelChallengeStatus.values) {
      if (value.wireValue == raw) {
        return Result.ok(value);
      }
    }
    return Result.err(
      AppError.validation(
        'social.duel_challenge_status_unknown',
        'Unknown duel challenge status: ${raw ?? '<null>'}',
      ),
    );
  }
}
