import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// What a player reads while the owners hold [which] off (script 291).
AppError ownerSwitchPaused(OwnerSwitch which) => switch (which) {
  OwnerSwitch.predictions => const AppError.invariant(
    'prediction.paused',
    'حفظ التوقعات متوقف مؤقتاً. توقعاتك المحفوظة باقية، ونعود قريباً.',
  ),
  OwnerSwitch.chat => const AppError.invariant(
    'h2h.chat_paused',
    'الدردشة متوقفة مؤقتاً. نعود قريباً.',
  ),
  OwnerSwitch.crowning => const AppError.invariant(
    'champion.crowning_paused',
    'تتويج الشهر موقوف مؤقتاً.',
  ),
  OwnerSwitch.h2hRounds => const AppError.invariant(
    'h2h.rounds_paused',
    'اعتماد جولات المواجهات موقوف مؤقتاً.',
  ),
  OwnerSwitch.h2hCup => const AppError.invariant(
    'h2h.cup_paused',
    'كأس المواجهات موقوف مؤقتاً.',
  ),
  OwnerSwitch.h2hCupCrowning => const AppError.invariant(
    'h2h.cup_crowning_paused',
    'تتويج كأس المواجهات موقوف مؤقتاً.',
  ),
};

// NK291_02
/// The refusal of a write the owners' switch [which] stops, or null to
/// serve it (script 291, migration 0221). Read now, on every request:
/// turning it takes effect on the next one. While off, everyone is
/// refused, admins included. A switch that cannot be read refuses with
/// the failure (`503`): the write would have failed on the same database.
/// No switches wired (a test that provides none) serves it.
Future<Response?> ownerSwitchStop(
  CompositionRoot root,
  OwnerSwitch which,
) async {
  final OwnerSwitches? switches = root.ownerSwitches;
  if (switches == null) return null;
  return switch (await switches.isOn(which)) {
    Ok<bool>(value: true) => null,
    Ok<bool>() => errorResponse(ownerSwitchPaused(which)),
    Err<bool>(:final error) => errorResponse(error),
  };
}
