import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// The accounts seen on one phone (script 200): two or more [users], oldest
/// account first, and when the phone was [lastSeen].
final class SharedDeviceGroup {
  /// Creates a group.
  const SharedDeviceGroup({required this.users, required this.lastSeen});

  /// Every account seen on the phone, oldest first.
  final List<User> users;

  /// The latest sighting of any of them on it.
  final DateTime lastSeen;
}

/// Port for the phones the accounts are played from (migration 0197).
///
/// A phone is an install of the app (`InstallId`); the push token an install
/// registered (migration 0177) counts as the same phone, so phones seen
/// before the install id was sent are listed too.
///
/// MUST NOT throw; a driver failure is [ErrorKind.transient].
abstract interface class DeviceSightings {
  /// Records that [userId] is signed in on the install [installId].
  Future<Result<void>> record({
    required String installId,
    required UserId userId,
  });

  /// At most [limit] phones that more than one account was seen on, the
  /// most crowded first, then the latest seen. A phone whose accounts are
  /// all on a larger phone's list is left out: it is the same phone.
  Future<Result<List<SharedDeviceGroup>>> sharedDevices({required int limit});
}
