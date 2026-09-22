import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Read port for the league screen's "X passed you" card (plan P2-7,
/// migration 0068).
///
/// General contract (Application ADR section 2): never throws, maps driver
/// failures to [ErrorKind.transient].
abstract interface class OvertakenNoticeReader {
  /// Who last passed [userId] in [leagueId], or null when nobody has.
  Future<Result<UserId?>> passedBy({
    required WeeklyLeagueId leagueId,
    required UserId userId,
  });
}
