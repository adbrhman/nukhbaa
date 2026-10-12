/// Use-case: trade the code of a password-reset e-mail for a recovery token.
library;

import 'package:application/src/identity/ports/auth_gateway.dart';
import 'package:shared/shared.dart';

/// Verifies the one-time code a player typed from the reset e-mail through
/// the application-owned auth port, and returns the recovery access token
/// [UpdatePassword] takes.
///
/// The code exists because the e-mail's link opened the web build, which a
/// weak connection could not load (2026-10-13); the code is typed into the
/// app the player already has.
final class VerifyRecoveryCode {
  const VerifyRecoveryCode(this._gateway);

  final AuthGateway _gateway;

  Future<Result<String>> call({required String email, required String code}) {
    return _gateway.verifyRecoveryCode(email: email, code: code);
  }
}
