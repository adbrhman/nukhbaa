import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One of the owners' switches (script 286, migration 0218).
enum OwnerSwitch {
  /// The month's crowning, by itself or by an admin's hand (decision Q04).
  crowning('crowning');

  const OwnerSwitch(this.key);

  /// Its key in `ops.owner_switches`.
  final String key;

  // NK289_01
  /// The switch whose key is [key], or null for a key this server does not
  /// know.
  static OwnerSwitch? byKey(String key) {
    for (final OwnerSwitch which in values) {
      if (which.key == key) return which;
    }
    return null;
  }
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

/// One owner switch as it stands (script 289): whether it is on, and the
/// last change made to it.
final class OwnerSwitchState {
  /// Creates the state.
  const OwnerSwitchState({
    required this.which,
    required this.isOn,
    required this.changedAt,
    this.reason,
    this.changedBy,
  });

  /// The switch.
  final OwnerSwitch which;

  /// Whether it is on.
  final bool isOn;

  /// Why it was last changed; null before any change.
  final String? reason;

  /// The owner seat who last changed it; null before any change, or when
  /// it was changed from the SQL editor.
  final UserId? changedBy;

  /// When it was last changed (UTC); the migration's time before any
  /// change.
  final DateTime changedAt;
}

/// Port for the owners' hands on their switches (script 289, migration
/// 0218): read them all, and turn one on or off for a reason. Kept apart
/// from [OwnerSwitches], which the guards read.
///
/// MUST NOT throw; an infrastructure failure is transient.
abstract interface class OwnerSwitchSettings {
  /// Every switch this server knows, in [OwnerSwitch] order.
  Future<Result<List<OwnerSwitchState>>> all();

  /// Turns [which] on or off ([on]) for [reason], by the owner seat [by].
  Future<Result<void>> set({
    required OwnerSwitch which,
    required bool on,
    required String reason,
    required UserId by,
  });
}
