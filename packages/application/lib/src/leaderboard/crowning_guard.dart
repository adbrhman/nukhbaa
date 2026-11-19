import 'package:application/src/admin/ports/owner_switches.dart';
import 'package:application/src/notification/owner_inbox.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// The owners' stop on the month's crowning (script 286, migration 0218,
/// decision Q04, decided by the owner on 2026-11-20).
///
/// While the crowning switch is off, no month is crowned by itself
/// (`AutoCrownMonths` holds it) and no admin crowns one by hand; an owner
/// seat still may, once he has checked the points. A switch that cannot be
/// read counts as off: the crowning waits rather than risk a wrong one.
// NK286_01
final class CrowningGuard {
  /// Creates the guard over the switches and the owner seats.
  const CrowningGuard({
    required OwnerSwitches switches,
    required OwnerNotices owners,
  }) : _switches = switches,
       _owners = owners;

  final OwnerSwitches _switches;
  final OwnerNotices _owners;

  /// Whether the crowning switch is on, read now.
  Future<Result<bool>> isOn() => _switches.isOn(OwnerSwitch.crowning);

  /// Whether [principal] may crown by hand now: any admin while the switch
  /// is on; only an owner seat while it is off or cannot be read.
  Future<bool> admitsByHand(AuthenticatedUser principal) async {
    final Result<bool> on = await isOn();
    if (on case Ok<bool>(value: true)) {
      return true;
    }
    return switch (await _owners.isOwner(principal.userId)) {
      Ok<bool>(:final value) => value,
      Err<bool>() => false,
    };
  }
}
