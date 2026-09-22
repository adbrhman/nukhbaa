import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// A [UserAdminRepository] that tells the per-request user cache when the
/// admin surface changes a user.
///
/// Suspend and reinstate write `identity.users` through this repository, not
/// through the cached `UserDirectory` that the authentication path reads. Without
/// this hook a suspended account would keep passing authentication until its
/// cached row expired; with it, the next request reads the new status.
final class UserCacheEvictingAdminRepository implements UserAdminRepository {
  /// Wraps [inner]; [onUserChanged] runs after every [updateUser] attempt.
  const UserCacheEvictingAdminRepository(
    this._inner, {
    required void Function(UserId id) onUserChanged,
  }) : _onUserChanged = onUserChanged;

  final UserAdminRepository _inner;
  final void Function(UserId id) _onUserChanged;

  @override
  Future<Result<User?>> findUserById(UserId id) => _inner.findUserById(id);

  @override
  Future<Result<User>> updateUser(User user) async {
    final Result<User> result = await _inner.updateUser(user);
    // Evicted on failure too: a write that errored may still have landed.
    _onUserChanged(user.id);
    return result;
  }

  @override
  Future<Result<List<User>>> listUsers({String? search, required int limit}) =>
      _inner.listUsers(search: search, limit: limit);
}
