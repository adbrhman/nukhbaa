import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/common/ttl_cache.dart';
import 'package:shared/shared.dart';

/// Short-lived, in-process caches in front of [UserDirectory]'s two hot
/// reads.
///
/// [findUser] runs on every authenticated request (the role/status
/// reconciliation in `AuthenticateRequest`), which made it the most frequent
/// statement against the database. Holding a user for [userTtl] turns a
/// burst of requests from one person into one query.
///
/// [readAvatar] moves up to 512 KB per call from `identity.users`, and a
/// device that drops its in-memory copy fetches the same picture again.
/// Holding it here serves repeats without touching the database.
///
/// Every write that goes through this directory refreshes or drops its own
/// entry, and [forget] lets the admin path (suspend/reinstate, which writes
/// through a different repository) drop a user at once, so a status change
/// takes effect on the next request rather than after [userTtl].
final class CachedUserDirectory implements UserDirectory {
  /// Wraps [inner]; [now] is injectable for tests.
  CachedUserDirectory(
    this._inner, {
    Duration userTtl = const Duration(seconds: 30),
    Duration avatarTtl = const Duration(hours: 1),
    int maxUsers = 1024,
    int maxAvatars = 48,
    DateTime Function() now = DateTime.now,
  }) : _users = TtlCache<String, User>(
         ttl: userTtl,
         maxEntries: maxUsers,
         now: now,
       ),
       _avatars = TtlCache<String, StoredAvatar>(
         ttl: avatarTtl,
         maxEntries: maxAvatars,
         now: now,
       );

  final UserDirectory _inner;
  final TtlCache<String, User> _users;
  final TtlCache<String, StoredAvatar> _avatars;

  /// Drops [id]'s cached user so the next read comes from the database.
  void forget(UserId id) => _users.remove(id.value);

  @override
  Future<Result<User?>> findUser(UserId id) async {
    final User? cached = _users.read(id.value);
    if (cached != null) {
      return Result.ok(cached);
    }
    final int startedAt = _users.generation;
    final Result<User?> result = await _inner.findUser(id);
    if (result case Ok<User?>(value: final User user)) {
      _users.write(id.value, user, startedAt: startedAt);
    }
    return result;
  }

  @override
  Future<Result<User>> ensureUser(AuthenticatedUser principal) async =>
      _remember(await _inner.ensureUser(principal));

  @override
  Future<Result<User>> updateDisplayName(
    UserId userId,
    String displayName,
  ) async => _remember(await _inner.updateDisplayName(userId, displayName));

  @override
  Future<Result<void>> updateUtcOffsetMinutes(UserId userId, int minutes) =>
      _inner.updateUtcOffsetMinutes(userId, minutes);

  @override
  Future<Result<User>> setAvatar(
    UserId userId,
    List<int> bytes,
    String mime,
  ) async {
    final Result<User> result = await _inner.setAvatar(userId, bytes, mime);
    _avatars.remove(userId.value);
    return _rememberOrForget(userId, result);
  }

  @override
  Future<Result<User>> clearAvatar(UserId userId) async {
    final Result<User> result = await _inner.clearAvatar(userId);
    _avatars.remove(userId.value);
    return _rememberOrForget(userId, result);
  }

  @override
  Future<Result<StoredAvatar?>> readAvatar(UserId userId) async {
    final StoredAvatar? cached = _avatars.read(userId.value);
    if (cached != null) {
      return Result.ok(cached);
    }
    final int startedAt = _avatars.generation;
    final Result<StoredAvatar?> result = await _inner.readAvatar(userId);
    if (result case Ok<StoredAvatar?>(value: final StoredAvatar avatar)) {
      _avatars.write(userId.value, avatar, startedAt: startedAt);
    }
    return result;
  }

  Result<User> _remember(Result<User> result) {
    if (result case Ok<User>(:final value)) {
      _users.replace(value.id.value, value);
    }
    return result;
  }

  Result<User> _rememberOrForget(UserId userId, Result<User> result) {
    if (result is Err<User>) {
      _users.remove(userId.value);
      return result;
    }
    return _remember(result);
  }
}
