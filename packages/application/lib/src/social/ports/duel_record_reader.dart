import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Read port over settled duels (migrations 0090, 0019): who won how many
/// duels in a season, for the leaderboard.
///
/// A duel is settled once both players' scores for its fixture are final
/// (grade other than `pending`); the one with more points won it, equal
/// points is a draw -- the same rule `ListMyDuels` shows each player.
///
/// General contract (Application ADR section 2): never throws, maps driver
/// failures to [ErrorKind.transient].
abstract interface class DuelRecordReader {
  /// How many settled duels of [seasonId] each participant won; a
  /// participant who won none is absent.
  Future<Result<Map<ParticipantId, int>>> winsInSeason(SeasonId seasonId);
}
