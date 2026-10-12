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
    required String displayName,
  }) async {
    final result = await _client.signUp(
      email: email,
      password: password,
      displayName: displayName,
    );
    return result.map(_toIssuedSession);
  }

  @override
  Future<Result<IssuedSession>> refreshSession({
    required String refreshToken,
  }) async {
    final result = await _client.refresh(refreshToken: refreshToken);
    return result.map(_toIssuedSession);
  }

  @override
  Future<Result<IssuedSession>> signInWithIdToken({
    required String provider,
    required String idToken,
  }) async {
    final result = await _client.signInWithIdToken(
      provider: provider,
      idToken: idToken,
    );
    return result.map(_toIssuedSession);
  }

  @override
  Future<Result<void>> requestPasswordReset({required String email}) {
    return _client.requestPasswordReset(email: email);
  }

  @override
  Future<Result<void>> updatePassword({
    required String recoveryToken,
    required String password,
  }) {
    return _client.updatePassword(
      recoveryToken: recoveryToken,
      password: password,
    );
  }

  @override
  Future<Result<String>> verifyRecoveryCode({
    required String email,
    required String code,
  }) async {
    final Result<SupabaseSession> result = await _client.verifyRecoveryCode(
      email: email,
      code: code,
    );
    switch (result) {
      case Ok<SupabaseSession>(:final value):
        final String? token = value.accessToken;
        if (token == null || token.isEmpty) {
          return const Result.err(
            AppError.transient(
              'auth.malformed_response',
              'Supabase Auth returned no access token',
            ),
          );
        }
        return Result.ok(token);
      case Err<SupabaseSession>(:final error):
        // GoTrue answers a wrong, used or expired code with a 4xx, which the
        // client maps to `auth.rejected` with an English message.
        if (error.code == 'auth.rejected') {
          return const Result.err(
            AppError.validation(
              'auth.recovery_code_invalid',
              'الرمز غير صحيح أو انتهت صلاحيته. اطلب رمزًا جديدًا.',
            ),
          );
        }
        return Result.err(error);
    }
  }

  IssuedSession _toIssuedSession(SupabaseSession session) => IssuedSession(
    accessToken: session.accessToken,
    refreshToken: session.refreshToken,
    emailConfirmationRequired: session.emailConfirmationRequired,
  );
}
