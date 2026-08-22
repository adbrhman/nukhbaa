/// Use-case: register a new email/password account.
library;

import 'package:application/src/identity/ports/auth_gateway.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Registers a new account with [email] + [password] via the platform's
/// [AuthGateway].
final class RegisterWithPassword {
  /// Creates the use-case with its required [AuthGateway] port.
  const RegisterWithPassword(this._gateway);

  final AuthGateway _gateway;

  /// Executes the registration with a required [displayName] (validated
  /// against the same rule as `UpdateDisplayName`). Never throws; returns a
  /// typed [Result].
  Future<Result<IssuedSession>> call({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final validated = User.validateDisplayName(displayName);
    if (validated is Err<String>) {
      return Result.err(validated.error);
    }
    return _gateway.signUpWithPassword(
      email: email,
      password: password,
      displayName: (validated as Ok<String>).value,
    );
  }
}
