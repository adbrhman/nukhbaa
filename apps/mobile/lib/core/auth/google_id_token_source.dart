/// The device half of "Continue with Google": the account picker, returning
/// an ID token the server exchanges for a session.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared/shared.dart';

/// The OAuth client the ID token is minted for: the project's Web client,
/// the one Supabase's Google provider trusts. A public identifier (every
/// Google sign-in client ships its client id), not a secret.
const String googleServerClientId =
    '91161451938-biohuse9u6c9n9hjdqqnsqtcqbref3eo.apps.googleusercontent.com';

/// The Google account picker.
final googleIdTokenSourceProvider = Provider<GoogleIdTokenSource>(
  (ref) => PluginGoogleIdTokenSource(),
);

/// Obtains a Google ID token from the user, behind a seam for tests.
abstract interface class GoogleIdTokenSource {
  /// Whether this build can show the picker. The web build cannot yet: it
  /// needs Google's own rendered button, which is a separate change.
  bool get isSupported;

  /// `Ok(token)` when the user picked an account, `Ok(null)` when they
  /// closed the picker, `Err` when Google sign-in failed.
  Future<Result<String?>> pickIdToken();
}

/// [GoogleIdTokenSource] over `google_sign_in` 7.x. Never throws.
class PluginGoogleIdTokenSource implements GoogleIdTokenSource {
  bool _initialized = false;

  @override
  bool get isSupported => !kIsWeb;

  @override
  Future<Result<String?>> pickIdToken() async {
    if (!isSupported) return const Result.ok(null);
    try {
      final GoogleSignIn signIn = GoogleSignIn.instance;
      // `initialize` must run exactly once per process, before anything else.
      if (!_initialized) {
        await signIn.initialize(serverClientId: googleServerClientId);
        _initialized = true;
      }
      final GoogleSignInAccount account = await signIn.authenticate();
      final String? idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        return const Result.err(
          AppError.transient(
            'auth.google_no_token',
            'لم يُرجع Google رمز الدخول. حاول مرة أخرى.',
          ),
        );
      }
      return Result.ok(idToken);
    } on GoogleSignInException catch (cause) {
      if (cause.code == GoogleSignInExceptionCode.canceled) {
        return const Result.ok(null);
      }
      return Result.err(
        AppError.transient(
          'auth.google_failed',
          'تعذّر الدخول بحساب Google. حاول مرة أخرى.',
          cause,
        ),
      );
    } on Object catch (cause) {
      return Result.err(
        AppError.transient(
          'auth.google_failed',
          'تعذّر الدخول بحساب Google. حاول مرة أخرى.',
          cause,
        ),
      );
    }
  }
}
