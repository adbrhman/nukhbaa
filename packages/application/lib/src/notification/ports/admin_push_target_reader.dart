import 'package:shared/shared.dart';

/// Read-only push targets for active platform administrators.
///
/// The infrastructure adapter resolves this from the canonical
/// `identity.users.role = 'admin'` guard and the device-token table, so a
/// caller never supplies an arbitrary recipient list.
abstract interface class AdminPushTargetReader {
  /// Returns the current FCM tokens belonging only to active administrators.
  Future<Result<List<String>>> tokensForActiveAdmins();
}
