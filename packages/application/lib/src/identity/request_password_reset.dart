/// Use-case: request a password-reset email.
library;

import 'package:application/src/identity/ports/auth_gateway.dart';
import 'package:shared/shared.dart';

/// Requests a password-reset email through the application-owned auth port.
final class RequestPasswordReset {
  const RequestPasswordReset(this._gateway);

  final AuthGateway _gateway;

  Future<Result<void>> call({required String email}) {
    return _gateway.requestPasswordReset(email: email);
  }
}
