import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Port for the limit of accounts on one phone (script 245): the terms of
/// the contest allow two accounts on a phone and no more.
///
/// A phone is an install of the app (`InstallId`); the accounts seen on it
/// are the ones `DeviceSightings` records.
///
/// MUST NOT throw; a driver failure is [ErrorKind.transient].
abstract interface class InstallAccountGate {
  /// Whether [userId] may be used on the phone [installId]: the account is
  /// already one of the accounts seen on it, or fewer than [limit] accounts
  /// have been seen there. An account that is already on the phone stays
  /// admitted even when the phone holds more than [limit] (accounts that
  /// were there before the limit).
  Future<Result<bool>> admits({
    required String installId,
    required UserId userId,
    required int limit,
  });
}
