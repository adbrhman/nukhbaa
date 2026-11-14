import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Read port for the right outcomes of a head-to-head month (NK275): the
/// fourth measure of commitment, after absences, predictions and exact
/// scorelines (owner, 2026-11-14).
///
/// Backed by `PostgresH2hSheetReader`. MUST NOT throw; MUST map
/// infrastructure failures to [ErrorKind.transient].
abstract interface class H2hOutcomeReader {
  /// For the month opened by [monthStart]: how many fixtures of its locked
  /// rounds each player called with the right outcome and the wrong score.
  /// A player with none is not in the map.
  Future<Result<Map<UserId, int>>> outcomesOf(DateTime monthStart);
}
