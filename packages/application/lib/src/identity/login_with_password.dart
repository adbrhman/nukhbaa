/// Use-case: sign in with an existing email/password account.
library;

import 'package:application/src/identity/ports/auth_gateway.dart';
import 'package:shared/shared.dart';

/// Signs in with [email] + [password] via the platform's [AuthGateway].
final class LoginWithPassword {
  /// Creates the use-case with its required [AuthGateway] port.
  const LoginWithPassword(this._gateway);

  final AuthGateway _gateway;

  /// Executes the login. Never throws; returns a typed [Result].
  Future<Result<IssuedSession>> call({
    required String email,
    required String password,
  }) {
    return _gateway.signInWithPassword(email: email, password: password);
  }
}
