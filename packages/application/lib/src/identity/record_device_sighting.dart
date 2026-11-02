import 'package:application/src/identity/install_id.dart';
import 'package:application/src/identity/ports/device_sightings.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Command use-case: the signed-in caller opened the app on an install
/// (`GET /me`, script 200), so the admin can see which accounts share a
/// phone.
///
/// A request without an install id (the web, a build before script 200) or
/// with a malformed one records nothing and succeeds. Never throws.
final class RecordDeviceSighting {
  /// Creates the use-case over its store.
  const RecordDeviceSighting({required DeviceSightings sightings})
    : _sightings = sightings;

  final DeviceSightings _sightings;

  /// Records [principal] on the install [installId].
  Future<Result<void>> call({
    required AuthenticatedUser principal,
    required String? installId,
  }) async {
    final String? id = InstallId.parse(installId);
    if (id == null) {
      return const Result.ok(null);
    }
    return _sightings.record(installId: id, userId: principal.userId);
  }
}
