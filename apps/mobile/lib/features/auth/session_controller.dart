/// The single source of truth for the client's authentication session.
///
/// This annotation-based Riverpod controller (`@riverpod`) owns the transition
/// between the [SessionState] cases and is the only place that reads/writes the
/// [TokenStore] and calls `AuthApi.me()`. Widgets never touch the token store
/// or `api_client` directly — they watch this controller and call its methods.
///
/// ## Sign-in mechanism (contract-faithful for v1)
/// The ratified backend has **no** password/login route — Supabase mints the
/// access token (Auth phase; the server only *verifies* every token, Security
/// ADR §2). The only identity route that exists is `GET /me` behind
/// `bearerAuth`. So the client's "sign in" is: accept an access token, persist
/// it via the [TokenStore], then **validate it by calling `GET /me`**:
///   * `200` → the token is good; hold the returned principal ([SessionAuthenticated]).
///   * `401` (authorization) → the token is invalid/expired; the persisted
///     token is cleared and the attempt becomes [SessionFailed] (never a
///     half-signed-in state holding a rejected token).
///   * transient (network/`503`) → the token is *kept* (the failure is not the
///     token's fault) and the attempt becomes [SessionFailed]; the user may
///     retry without re-entering it.
///
/// ## Boot-time restore
/// [build] reads any persisted token once; if present it validates it exactly
/// as a sign-in does, so a returning user with a still-valid token lands
/// directly on the authenticated screen, and one whose token has since expired
/// is routed to sign-in with the stale token cleared.
library;

import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:contracts/contracts.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared/shared.dart';

import '../../core/auth/biometric_unlock.dart';
import '../../core/auth/google_id_token_source.dart';
import '../../core/auth/token_store.dart';
import '../../core/providers.dart';
import 'session_state.dart';

part 'session_controller.g.dart';

/// Owns and mutates the authentication [SessionState].
///
/// The controller is async: [build] resolves the boot-time state by attempting
/// a restore from the [TokenStore], so the initial value is a `Future` that the
/// router awaits (showing a splash while it is [SessionUnknown]/loading).
@riverpod
class SessionController extends _$SessionController {
  TokenStore get _store => ref.read(tokenStoreProvider);
  AuthApi get _authApi => ref.read(authApiProvider);

  @override
  Future<SessionState> build() async {
    ref.listen<int>(sessionExpiryProvider, (_, _) {
      state = const AsyncData(SessionUnauthenticated());
    });
    return _restore();
  }

  /// Boot-time restore: validate a persisted token, if any.
  Future<SessionState> _restore() async {
    final token = await _store.read();
    if (token == null || token.isEmpty) {
      return const SessionUnauthenticated();
    }
    // A token is on disk — confirm the server still accepts it before treating
    // the user as signed in.
    return _validateHeldToken(clearOnAuthFailure: true);
  }

  /// Signs in with an access [token] (minted by Supabase / supplied by the
  /// caller): persist it, then validate via `GET /me`.
  ///
  /// The state moves to [SessionAuthenticating] for the duration, then to
  /// [SessionAuthenticated] on success or [SessionFailed] on any error.
  Future<void> signIn(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      state = const AsyncData(
        SessionFailed(
          AppError.validation(
            'auth.token_empty',
            'Please enter your access token.',
          ),
        ),
      );
      return;
    }

    state = const AsyncData(SessionAuthenticating());
    try {
      await _store.write(trimmed);
    } on Object catch (cause) {
      state = AsyncData(
        SessionFailed(
          AppError.transient(
            'auth.token_store_unavailable',
            'Could not securely save your session on this device.',
            cause,
          ),
        ),
      );
      return;
    }
    final resolved = await _validateHeldToken(clearOnAuthFailure: true);
    state = AsyncData(resolved);
  }

  /// Signs in with [email] + [password] via `POST /auth/login`.
  Future<void> signInWithCredentials({
    required String email,
    required String password,
  }) async {
    state = const AsyncData(SessionAuthenticating());
    final result = await _authApi.login(email: email, password: password);
    state = AsyncData(await _onAuthResponse(result));
  }

  /// Registers a new account with [displayName] + [email] + [password] via
  /// `POST /auth/register`.
  Future<void> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    state = const AsyncData(SessionAuthenticating());
    final result = await _authApi.register(
      displayName: displayName,
      email: email,
      password: password,
    );
    state = AsyncData(await _onAuthResponse(result));
  }

  /// Signs in with Google: the device's account picker supplies an ID
  /// token, which `POST /auth/google` exchanges for a session (created on
  /// first use). Closing the picker returns to the form without an error.
  Future<void> signInWithGoogle() async {
    state = const AsyncData(SessionAuthenticating());
    final Result<String?> picked = await ref
        .read(googleIdTokenSourceProvider)
        .pickIdToken();
    switch (picked) {
      case Ok<String?>(value: final String idToken):
        final result = await _authApi.signInWithGoogle(idToken: idToken);
        state = AsyncData(await _onAuthResponse(result));
      case Ok<String?>():
        state = const AsyncData(SessionUnauthenticated());
      case Err<String?>(:final error):
        state = AsyncData(SessionFailed(error));
    }
  }

  /// Signs back in with the fingerprint after a sign-out: the refresh token
  /// [signOut] kept (fingerprint unlock on) is exchanged for a session once
  /// the fingerprint passes. A declined fingerprint leaves the form as it
  /// was; a token the provider no longer accepts is dropped, with a message
  /// to use the password; an offline attempt keeps it for the next try.
  Future<void> signInWithFingerprint() async {
    final BiometricPreferenceStore prefs = ref.read(
      biometricPreferenceStoreProvider,
    );
    final String? kept = await prefs.readSavedRefreshToken();
    if (kept == null || kept.isEmpty) return;
    final bool passed = await ref
        .read(biometricAuthenticatorProvider)
        .authenticate(reason: 'ضع بصمتك للدخول إلى نُخبة');
    if (!passed) return;
    state = const AsyncData(SessionAuthenticating());
    final Result<AuthResponseDto> result = await _authApi.refresh(
      refreshToken: kept,
    );
    switch (result) {
      case Ok<AuthResponseDto>():
        await prefs.clearSavedRefreshToken();
        state = AsyncData(await _onAuthResponse(result));
      case Err<AuthResponseDto>(:final error)
          when error.kind == ErrorKind.transient:
        state = AsyncData(SessionFailed(error));
      case Err<AuthResponseDto>():
        await prefs.clearSavedRefreshToken();
        state = const AsyncData(
          SessionFailed(
            AppError.validation(
              'auth.fingerprint_expired',
              'انتهت صلاحية الدخول بالبصمة. سجّل الدخول بكلمة المرور.',
            ),
          ),
        );
    }
  }

  /// With fingerprint unlock on, the refresh token outlives a sign-out in
  /// its own slot, so the sign-in screen can offer the fingerprint.
  Future<void> _keepForFingerprint() async {
    final BiometricPreferenceStore prefs = ref.read(
      biometricPreferenceStoreProvider,
    );
    if (!await prefs.isEnabled()) return;
    final String? token = await _store.readRefreshToken();
    if (token != null && token.isNotEmpty) {
      await prefs.saveRefreshToken(token);
    }
  }

  /// Maps a login/register [Result] to the resulting [SessionState].
  Future<SessionState> _onAuthResponse(Result<AuthResponseDto> result) async {
    switch (result) {
      case Ok<AuthResponseDto>(:final value):
        final token = value.accessToken;
        if (token == null || token.isEmpty) {
          return const SessionFailed(
            AppError.validation(
              'auth.confirmation_required',
              'Check your email to confirm your account before signing in.',
            ),
          );
        }
        await _store.write(token);
        final refreshToken = value.refreshToken;
        if (refreshToken != null && refreshToken.isNotEmpty) {
          await _store.writeRefreshToken(refreshToken);
        }
        return _validateHeldToken(clearOnAuthFailure: true);
      case Err<AuthResponseDto>(:final error):
        await _store.clear();
        return SessionFailed(error);
    }
  }

  /// Chooses the caller's display name, once (`PUT /me/display-name`), then
  /// re-validates the held token so every watcher sees the new name (the
  /// same shape as [setAvatar]).
  Future<Result<void>> chooseDisplayName({required String displayName}) async {
    final result = await _authApi.chooseDisplayName(displayName: displayName);
    if (result is Err<MeResponseDto>) {
      return Result.err(result.error);
    }
    state = AsyncData(await _validateHeldToken(clearOnAuthFailure: false));
    return const Result.ok(null);
  }

  /// Sets the caller's profile picture to [bytes] under [contentType].
  ///
  /// Performs, then re-validates the held token so every watcher sees the new
  /// identity (the same shape [register]/[signInWithCredentials] use). The
  /// server returns the full `MeResponseDto`, but re-validating rather than
  /// trusting that body keeps ONE path by which session state changes.
  Future<Result<void>> setAvatar({
    required List<int> bytes,
    required String contentType,
  }) async {
    final result = await _authApi.setAvatar(
      bytes: bytes,
      contentType: contentType,
    );
    if (result is Err<MeResponseDto>) {
      return Result.err(result.error);
    }
    state = AsyncData(await _validateHeldToken(clearOnAuthFailure: false));
    return const Result.ok(null);
  }

  /// Removes the caller's profile picture. Same shape as [setAvatar].
  Future<Result<void>> removeAvatar() async {
    final result = await _authApi.removeAvatar();
    if (result is Err<MeResponseDto>) {
      return Result.err(result.error);
    }
    state = AsyncData(await _validateHeldToken(clearOnAuthFailure: false));
    return const Result.ok(null);
  }

  /// Signs the current user out: clear the persisted token and drop to
  /// [SessionUnauthenticated]. Idempotent.
  Future<void> signOut() async {
    try {
      await _keepForFingerprint();
    } on Object {
      // Losing the fingerprint slot only costs a password sign-in.
    }
    try {
      await _store.clear();
    } on Object {
      // A failed erase must not strand the user in a signed-in UI.
    }
    state = const AsyncData(SessionUnauthenticated());
  }

  /// Clears a stale [SessionFailed] error without touching the persisted
  /// token or re-validating anything — used when the sign-in form switches
  /// between "Sign in" and "Create account" mode, so an error from one mode
  /// (e.g. "email already registered") does not linger and mislead the user
  /// after they switch to the other mode. No-op unless the current state is
  /// [SessionFailed]; deliberately does not touch [SessionAuthenticating] or
  /// any other state.
  void clearFailure() {
    final current = state.value;
    if (current is SessionFailed) {
      state = const AsyncData(SessionUnauthenticated());
    }
  }

  /// Re-attempts validation of the currently-held token (used by the "retry"
  /// affordance after a transient failure, where the token was intentionally
  /// kept). No-op-safe: if no token is held it resolves to unauthenticated.
  Future<void> retry() async {
    state = const AsyncData(SessionAuthenticating());
    final resolved = await _restore();
    state = AsyncData(resolved);
  }

  /// Calls `GET /me` with whatever token the store currently holds and maps the
  /// typed `Result` to a [SessionState].
  ///
  /// On an authorization failure the persisted token is cleared (when
  /// [clearOnAuthFailure]) because it is definitively bad; on a transient
  /// failure the token is left in place so a retry can succeed without the user
  /// re-entering it.
  Future<SessionState> _validateHeldToken({
    required bool clearOnAuthFailure,
  }) async {
    final Result<MeResponseDto> result = await _authApi.me();
    return switch (result) {
      Ok<MeResponseDto>(:final value) => SessionAuthenticated(value.user),
      Err<MeResponseDto>(:final error) => await _onValidationError(
        error,
        clearOnAuthFailure: clearOnAuthFailure,
      ),
    };
  }

  Future<SessionState> _onValidationError(
    AppError error, {
    required bool clearOnAuthFailure,
  }) async {
    if (error.kind == ErrorKind.authorization) {
      if (clearOnAuthFailure) {
        await _store.clear();
      }
      // A refused token is refused whether or not it was erased: there is
      // nothing to retry with.
      return SessionFailed(error);
    }
    // The token was NOT cleared -- the failure is the network's, not the
    // token's -- so this is recoverable without re-entering anything.
    return SessionFailed(error, canRetryRestore: true);
  }
}
