import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Port for the admin user-sanction surface: resolve a platform [User] by id
/// and persist a lifecycle-status transition (Application ADR §9).
///
/// This is a **new, narrow port** justified exactly like the Ledger's
/// `ParticipantReader`: the ratified `UserDirectory` only offers
/// `ensureUser(principal)` (an idempotent upsert keyed on a *verified*
/// principal) — it has no "find an arbitrary user by id" or "update another
/// user's status" capability, and widening that frozen port would violate the
/// no-change-without-approval rule (Roadmap ADR §rules). `SuspendUser` /
/// `ReinstateUser` act on a TARGET user (by path id), who is not the caller, so
/// this port exposes the two operations they need. Infrastructure implements it
/// by reading/writing the same `identity.users` row the directory owns.
///
/// A new internal port inside the existing `application` package (no new
/// package), so `tooling/import_lint` is unaffected.
///
/// General contract (Application ADR §2):
/// * MUST NOT throw — every outcome is a typed [Result].
/// * MUST map infrastructure failures to [ErrorKind.transient].
/// Aggregate counts across EVERY row of `identity.users` (Database ADR §3),
/// independent of [UserAdminRepository.listUsers]'s bounded browse page.
/// [active] and [suspended] always sum to [total]: `UserStatus` is a closed
/// two-value enum (migration `0001_identity.sql`'s `identity.user_status`),
/// so there is no third status left unaccounted for.
final class UserCounts {
  /// Creates the counts.
  const UserCounts({
    required this.total,
    required this.active,
    required this.suspended,
  });

  /// Every stored user, regardless of status.
  final int total;

  /// Users whose `status` is `active`.
  final int active;

  /// Users whose `status` is `suspended`.
  final int suspended;
}

abstract interface class UserAdminRepository {
  /// Returns the [User] identified by [id], or `Ok(null)` when no such user
  /// exists. The suspend/reinstate use-cases report a `null` as a typed
  /// not-found (never leaking whether the id was well-formed-but-absent).
  Future<Result<User?>> findUserById(UserId id);

  /// Persists [user] (an already-validated transition produced by
  /// `User.suspend()`/`reinstate()`), returning the stored value. The status is
  /// the only field the admin surface mutates; the adapter updates that column
  /// only. A driver failure maps to [ErrorKind.transient].
  Future<Result<User>> updateUser(User user);

  /// Browses users by an optional case-insensitive display-name or
  /// email-contains [search], capped at [limit], ordered by display name then
  /// email. The admin surface's find-a-user read.
  Future<Result<List<User>>> listUsers({String? search, required int limit});

  /// The platform-wide user counts: a single aggregate over EVERY row, never
  /// a page. This is what backs "how many users does the platform have" —
  /// [listUsers] exists only to find one user to sanction and is bounded by
  /// design, so it must never be mistaken for this total.
  Future<Result<UserCounts>> countUsers();
}
