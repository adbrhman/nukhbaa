import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// The accounts that share one display name (migration 0084's
/// `identity.display_name_key`): two or more [users], oldest account first.
final class DuplicateNameGroup {
  /// Creates a group.
  const DuplicateNameGroup(this.users);

  /// Every account carrying the name, oldest first.
  final List<User> users;
}

/// Port for the admin "duplicate names" read: every name that more than one
/// account carries, so an admin can rename all but one of them.
///
/// A new, narrow port rather than a method on `UserAdminRepository`, which has
/// many implementations that this read does not concern.
///
/// Two names are the same when their normalised keys match (case, spaces,
/// Arabic diacritics and tatweel ignored; alef forms, alef maqsura and ta
/// marbuta folded). Automatic names (the e-mail local part) are never
/// counted: they are temporary, and the app already asks those players to
/// choose a name.
///
/// MUST NOT throw; a driver failure is [ErrorKind.transient].
abstract interface class DuplicateNameReader {
  /// At most [limit] groups, the most crowded first.
  Future<Result<List<DuplicateNameGroup>>> duplicateNames({required int limit});
}
