import 'package:application/src/admin/ports/owner_switches.dart';
import 'package:shared/shared.dart';

/// Whether the owners' switch [which] holds the work back (script 304).
///
/// True when the switch is off, and also when it cannot be read: the work
/// waits rather than risk a wrong result, as the month's crowning does
/// (`CrowningGuard`). With no [switches] wired (a test that provides none)
/// nothing is held.
Future<bool> ownerSwitchHolds(
  OwnerSwitches? switches,
  OwnerSwitch which,
) async {
  if (switches == null) {
    return false;
  }
  return switch (await switches.isOn(which)) {
    Ok<bool>(:final value) => !value,
    Err<bool>() => true,
  };
}
