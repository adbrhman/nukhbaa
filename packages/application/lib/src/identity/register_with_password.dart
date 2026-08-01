/// Use-case: register a new email/password account.
library;

import 'package:application/src/identity/ports/auth_gateway.dart';
import 'package:shared/shared.dart';

/// Registers a new account with [email] + [password] via the platform's
/// [AuthGateway].
final class RegisterWithPassword {
  /// Creates the use-case with its required [AuthGateway] port.
  const RegisterWithPassword(this._gateway);

  final AuthGateway _gateway;

  /// Executes the registration. Never throws; returns a typed [Result].
  Future<Result<IssuedSession>> call({
    required String email,
    required String password,
  }) {
    return _gateway.signUpWithPassword(email: email, password: password);
  }
}
