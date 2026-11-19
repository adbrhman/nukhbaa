import 'package:shared/shared.dart';

/// One of the owners' switches (script 286, migration 0218).
enum OwnerSwitch {
  /// The month's crowning, by itself or by an admin's hand (decision Q04).
  crowning('crowning');

  const OwnerSwitch(this.key);

  /// Its key in `ops.owner_switches`.
  final String key;
}

/// Port for the owners' switches (script 286, migration 0218): on by
/// default, read on every run, never once at boot.
///
/// MUST NOT throw; an infrastructure failure is transient, and the callers
/// treat it as the switch being off.
abstract interface class OwnerSwitches {
  /// Whether [which] is on. A switch without its row is on: the row is
  /// written by the migration that adds the switch.
  Future<Result<bool>> isOn(OwnerSwitch which);
}
