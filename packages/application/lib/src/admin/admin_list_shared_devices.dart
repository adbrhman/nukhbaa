import 'package:application/src/identity/authorization.dart';
import 'package:application/src/identity/ports/device_sightings.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: the phones more than one account was seen on
/// (`GET /admin/shared-devices`, script 200), with their accounts, so an
/// admin can suspend them (decided by the owner on 2026-11-02).
///
/// Admin-only. Bounded to [maxGroups] phones. An empty list means every
/// phone seen holds one account.
final class AdminListSharedDevices {
  /// Creates the use-case over its reader.
  const AdminListSharedDevices({required DeviceSightings devices})
    : _devices = devices;

  final DeviceSightings _devices;

  /// The most phones one read returns.
  static const int maxGroups = 100;

  /// The shared phones, for the admin [principal].
  Future<Result<List<SharedDeviceGroup>>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    return _devices.sharedDevices(limit: maxGroups);
  }
}
