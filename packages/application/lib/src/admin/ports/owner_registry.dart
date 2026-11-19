import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Port for the owner seats (script 285, migration 0217, decision Q01):
/// one primary and his backups, known by account id, never by an e-mail
/// written in the code.
///
/// MUST NOT throw; an infrastructure failure is transient.
abstract interface class OwnerRegistry {
  /// The seats whose account is an active admin, the primary first. Empty
  /// when no seat can act.
  Future<Result<List<UserId>>> activeOwners();
}
