import 'package:application/src/admin/ports/duplicate_name_reader.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: the display names more than one account carries
/// (`GET /admin/duplicate-names`), for the admin to resolve by renaming.
///
/// Admin-only. Bounded to [maxGroups] groups; once those are renamed, the next
/// ones appear. An empty list means every chosen name is unique.
final class AdminListDuplicateNames {
  /// Creates the use-case over its reader.
  const AdminListDuplicateNames({required DuplicateNameReader names})
    : _names = names;

  final DuplicateNameReader _names;

  /// The most groups one read returns.
  static const int maxGroups = 100;

  /// The duplicate-name groups, for the admin [principal].
  Future<Result<List<DuplicateNameGroup>>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    return _names.duplicateNames(limit: maxGroups);
  }
}
