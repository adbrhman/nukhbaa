import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One participant who is about to be told about their own score, together
/// with the devices that can be told.
final class ScoreNoticeTarget {
  /// Creates a target.
  const ScoreNoticeTarget({
    required this.participantId,
    required this.userId,
    required this.tokens,
  });

  /// The participant whose score is being announced.
  final ParticipantId participantId;

  /// The user behind that participant -- the notification's recipient.
  final UserId userId;

  /// Their registered push tokens. Never empty: a participant with no device
  /// is not a target at all.
  final List<String> tokens;
}

/// Read port for announcing fixture scores (migrations 0012, 0039).
///
/// General contract (Application ADR SS2): never throws, maps driver failures
/// to [ErrorKind.transient]. Tier-3 -- a failure here is confined to the
/// announcement and never reaches the points path.
abstract interface class ScoreAnnouncementRepository {
  /// The devices of [participantIds], skipping any participant with none.
  Future<Result<List<ScoreNoticeTarget>>> targetsForParticipants(
    List<ParticipantId> participantIds,
  );

  /// A human label for [fixture] ("Home x Away"), or `Ok(null)` when the
  /// fixture has no registered schedule.
  Future<Result<String?>> matchLabel(FixtureRef fixture);
}
