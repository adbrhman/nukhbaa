import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

import 'package:application/application.dart';

/// Port: the platform's canonical user store.
///
/// Implementations are owned by the infrastructure layer.
abstract interface class UserDirectory {
  /// Upserts the canonical [User] row for [principal].
  ///
  /// First sight creates the row seeded with role `user` and status `active`.
  /// Subsequent calls reconcile the provider-sourced email while leaving the
  /// platform-owned `role` and `status` untouched.
  Future<Result<User>> ensureUser(AuthenticatedUser principal);

  /// Reads the canonical [User] for [id] WITHOUT creating it.
  ///
  /// Returns `Ok(null)` when no platform row exists yet.
  ///
  /// This is the per-request reconciliation read on the authentication path:
  /// the stored role/status are authoritative over the token's claims, so
  /// every guarded request must consult them. Deliberately a pure READ —
  /// unlike [ensureUser], this runs on every single request, and an upsert
  /// there would put a write on the hottest path in the system.
  Future<Result<User?>> findUser(UserId id);
}
