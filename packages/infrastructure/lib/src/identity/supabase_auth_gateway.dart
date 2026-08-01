/// Adapts the existing [SupabaseAuthClient] to the application-owned
/// [AuthGateway] port.
library;

import 'package:application/application.dart';
import 'package:infrastructure/src/identity/supabase_auth_client.dart';
import 'package:shared/shared.dart';

/// [AuthGateway] implementation backed by [SupabaseAuthClient].
final class SupabaseAuthGateway implements AuthGateway {
  /// Creates a gateway wrapping [client].
  const SupabaseAuthGateway(this._client);

  final SupabaseAuthClient _client;

  @override
  Future<Result<IssuedSession>> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final result = await _client.signIn(email: email, password: password);
    return result.map(_toIssuedSession);
  }

  @override
  Future<Result<IssuedSession>> signUpWithPassword({
    required String email,
    required String password,
  }) async {
    final result = await _client.signUp(email: email, password: password);
    return result.map(_toIssuedSession);
  }

  IssuedSession _toIssuedSession(SupabaseSession session) => IssuedSession(
    accessToken: session.accessToken,
    refreshToken: session.refreshToken,
    emailConfirmationRequired: session.emailConfirmationRequired,
  );
}
