/// Use-case: set a new password using a recovery access token.
library;

import 'package:application/src/identity/ports/auth_gateway.dart';
import 'package:shared/shared.dart';

/// Updates an account password through the application-owned auth port.
final class UpdatePassword {
  const UpdatePassword(this._gateway);

  final AuthGateway _gateway;

  Future<Result<void>> call({
    required String recoveryToken,
    required String password,
  }) {
    return _gateway.updatePassword(
      recoveryToken: recoveryToken,
      password: password,
    );
  }
}
