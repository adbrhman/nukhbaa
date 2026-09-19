import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Read port for the daily challenge: how much of one Riyadh match day a
/// participant has covered (P1-2).
///
/// Backed by `PostgresDailyChallengeRepository`. It answers a question, it
/// does not decide anything: whether the day counts as complete is
/// [DailyChallengeProgress.isComplete], in Dart, and whether that is worth
/// recording is the use-case's call.
///
/// General contract (Application ADR §2): MUST NOT throw — every outcome is
/// a typed [Result]; MUST map infrastructure failures to
/// [ErrorKind.transient].
///
/// **Tier-3.** It is consulted on the tail of a prediction that has already
/// been saved, so a failure here costs a challenge record and never the
/// prediction itself.
abstract interface class DailyChallengeRepository {
  /// How many fixtures of [seasonId] kick off on the Riyadh day [day], and
  /// how many of them [participantId] has predicted.
  ///
  /// [day] is a UTC midnight carrying that Riyadh day's date, as produced by
  /// `riyadhDayOf`.
  Future<Result<DailyChallengeProgress>> progressOn({
    required SeasonId seasonId,
    required ParticipantId participantId,
    required DateTime day,
  });
}

/// One participant's coverage of one match day.
final class DailyChallengeProgress {
  /// Creates a coverage reading.
  const DailyChallengeProgress({required this.total, required this.predicted});

  /// How many fixtures the season holds on that day.
  final int total;

  /// How many of them the participant has predicted.
  final int predicted;

  /// Whether the day is covered in full.
  ///
  /// A day with no fixtures is NOT complete: an empty day is not an
  /// achievement, and treating it as one would hand every user a streak on
  /// an international break.
  bool get isComplete => total > 0 && predicted >= total;
}
