import 'package:application/src/identity/install_id.dart';
import 'package:application/src/identity/ports/device_sightings.dart';
import 'package:application/src/identity/ports/install_account_gate.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Command use-case: the signed-in caller opened the app on an install
/// (`GET /me`, script 200), so the admin can see which accounts share a
/// phone.
///
/// A request without an install id (the web, a build before script 200) or
/// with a malformed one records nothing and succeeds. Never throws.
final class RecordDeviceSighting {
  /// Creates the use-case over its store; [gate] is the limit of accounts on
  /// a phone, and without it no account is ever refused.
  const RecordDeviceSighting({
    required DeviceSightings sightings,
    InstallAccountGate? gate,
  }) : _sightings = sightings,
       _gate = gate;

  /// How many accounts the terms of the contest allow on one phone.
  static const int maxAccountsPerPhone = 2;

  final DeviceSightings _sightings;
  final InstallAccountGate? _gate;

  /// Whether the signed-in caller may use the phone [installId]: refuses,
  /// with `device.account_limit`, an account that would be the third on it.
  ///
  /// Fails open: a request without an install id (the web, an old build), a
  /// malformed one, a missing gate or a failed read admits the caller, so a
  /// fault of ours never locks a player out. Never throws.
  Future<Result<void>> admit({
    required AuthenticatedUser principal,
    required String? installId,
  }) async {
    final InstallAccountGate? gate = _gate;
    final String? id = InstallId.parse(installId);
    if (gate == null || id == null) {
      return const Result.ok(null);
    }
    final Result<bool> answer = await gate.admits(
      installId: id,
      userId: principal.userId,
      limit: maxAccountsPerPhone,
    );
    if (answer case Ok<bool>(value: false)) {
      return const Result.err(
        AppError.invariant(
          'device.account_limit',
          '\u0644\u0627 \u064a\u0645\u0643\u0646 \u0627\u0633\u062a\u062e\u062f\u0627\u0645 \u0623\u0643\u062b\u0631 \u0645\u0646 \u062d\u0633\u0627\u0628\u064a\u0646 \u0639\u0644\u0649 \u0647\u0630\u0627 \u0627\u0644\u0647\u0627\u062a\u0641. \u0633\u062c\u0651\u0644 \u0627\u0644\u062f\u062e\u0648\u0644 \u0628\u0623\u062d\u062f \u062d\u0633\u0627\u0628\u064a\u0643 \u0627\u0644\u0645\u0648\u062c\u0648\u062f\u064a\u0646.',
        ),
      );
    }
    return const Result.ok(null);
  }

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
