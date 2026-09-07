import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Port for resolving the platform's canonical [User] record for a verified
/// principal (Application ADR, Section 9). Backed in Infrastructure by
/// `PostgresUserDirectory`.
///
/// The identity provider (Supabase Auth) owns credentials; the *platform* owns
/// the canonical user row (role, status, and any future domain-owned identity
/// state). This port is the seam between the two: given a principal the token
/// already established, it returns the platform's own record, creating it on
/// first sight ("ensure") so a freshly-signed-up user has a canonical row
/// before any domain phase references them.
///
/// Contract for implementations:
/// * MUST be idempotent: repeated calls for the same principal converge on one
///   row (Application ADR, Section 2: commands are idempotent/safely
///   retryable).
/// * MUST map infrastructure failures to [ErrorKind.transient]; it MUST NOT
///   invent authorization/validation errors — the principal is already
///   verified upstream.
/// * MUST NOT throw; every outcome is a typed [Result].
abstract interface class UserDirectory {
  /// Resolves the canonical [User] for [principal], creating the row on first
  /// sight and reconciling provider-sourced fields (email) on subsequent calls.
  ///
  /// The stored [PlatformRole] and [UserStatus] are the platform's own record
  /// and are authoritative over token claims once the row exists; a newly
  /// created row is seeded with the principal's token role and
  /// [UserStatus.active].
  Future<Result<User>> ensureUser(AuthenticatedUser principal);

  /// Persists a new [displayName] (already validated by the caller) for
  /// [userId] — the sole path, besides registration seeding, allowed to
  /// change a user's display name (`UpdateDisplayName` use-case).
  Future<Result<User>> updateDisplayName(UserId userId, String displayName);

  /// Stores [bytes] as [userId]'s profile picture, replacing any current one,
  /// and stamps the update time.
  ///
  /// [mime] is already validated by the caller against the formats the
  /// platform serves; the size cap is enforced there too. The bytes are
  /// written whole -- there is no partial or streamed avatar.
  Future<Result<User>> setAvatar(UserId userId, List<int> bytes, String mime);

  /// Removes [userId]'s picture. Idempotent: clearing an absent picture
  /// succeeds, so a retried removal converges instead of erroring on a state
  /// the caller already wanted.
  Future<Result<User>> clearAvatar(UserId userId);

  /// Reads the raw picture for [userId], or `Ok(null)` when there is none.
  ///
  /// Separate from [findUser] on purpose: this is the only call that moves
  /// image bytes, and it is made by exactly one route. Keeping it apart means
  /// no ordinary user read ever drags a blob along.
  Future<Result<StoredAvatar?>> readAvatar(UserId userId);

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

/// A stored profile picture as it comes back from the directory: the bytes,
/// the content type to serve them under, and when they were stored.
///
/// Deliberately not part of [User]: an image is payload a single route moves,
/// not a fact the rest of the system reasons about. Keeping it in its own
/// type means no ordinary user read can accidentally carry a blob.
final class StoredAvatar {
  /// Creates a stored avatar.
  const StoredAvatar({
    required this.bytes,
    required this.mime,
    required this.updatedAt,
  });

  /// The raw image bytes.
  final List<int> bytes;

  /// The content type (`image/jpeg`, `image/png` or `image/webp`).
  final String mime;

  /// When this picture was stored (UTC) -- the cache-busting token.
  final DateTime updatedAt;
}
