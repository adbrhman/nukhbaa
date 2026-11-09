import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Read port for the age of accounts: when each one was created.
///
/// The terms of the contest say that a tie for first place is won by the
/// oldest account, so the automatic crowning needs that date and nothing
/// else about the players.
///
/// General contract: MUST NOT throw; infrastructure failures are
/// `Result.err`.
abstract interface class AccountAgeReader {
  /// When each of [users] created its account (UTC), keyed by user id. A user
  /// without a known date is left out of the map.
  Future<Result<Map<String, DateTime>>> createdAt(List<UserId> users);
}
