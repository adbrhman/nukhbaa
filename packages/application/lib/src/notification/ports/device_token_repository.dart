import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Persistence port for device push-notification tokens (migration 0039).
///
/// Backed by `PostgresDeviceTokenRepository`. Speaks in typed ids and plain
/// strings, never rows or SQL, so the use-case above it stays pure and
/// testable against an in-memory fake.
///
/// General contract (Application ADR §2): MUST NOT throw — every outcome is
/// a typed [Result]; MUST map infrastructure failures to
/// [ErrorKind.transient].
abstract interface class DeviceTokenRepository {
  /// Registers [token] for [userId] on [platform], upserting by token: a
  /// token already on file for a different user is reassigned (the same
  /// physical device signed in as someone else), never duplicated.
  Future<Result<void>> upsert({
    required UserId userId,
    required String token,
    required String platform,
  });
}
