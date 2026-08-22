import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:infrastructure/src/identity/auth_config.dart';
import 'package:shared/shared.dart';

/// The outcome of a successful Supabase Auth (GoTrue) sign-in / sign-up.
///
/// A pure infrastructure value: the raw session facts returned by GoTrue,
/// mapped by the server route into the transport DTO. [accessToken] is null
/// only when GoTrue created the account but withheld a session pending email
/// confirmation.
final class SupabaseSession {
  /// Creates a session value.
  const SupabaseSession({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.email,
    required this.emailConfirmationRequired,
  });

  /// The Supabase access token (JWT), or null when confirmation is pending.
  final String? accessToken;

  /// The Supabase refresh token, or null when no session was issued.
  final String? refreshToken;

  /// The user's id (UUID string), when known.
  final String? userId;

  /// The user's email, when known.
  final String? email;

  /// Whether a session was withheld pending email confirmation.
  final bool emailConfirmationRequired;
}

/// Talks to a Supabase project's GoTrue (Auth) REST API to exchange an
/// email/password for a Supabase session. This is the ONLY component that
/// issues HTTP to Supabase Auth (Infrastructure ADR: external connections live
/// here, never in a route handler).
///
/// Every method is total: it always returns a [Result] and never throws. A
/// hard [_timeout] bounds every call so a stalled network can never leave the
/// caller (and, one layer up, the client's sign-in spinner) hanging forever —
/// a timeout maps to a transient [AppError] just like any transport failure.
final class SupabaseAuthClient {
  /// Creates a client for the project described by [config], using
  /// [httpClient] for I/O. [timeout] bounds every individual GoTrue call
  /// (default 15s; pass null in tests that intentionally leave a call
  /// unresolved).
  SupabaseAuthClient({
    required AuthConfig config,
    required http.Client httpClient,
    Duration? timeout = const Duration(seconds: 15),
  }) : _config = config,
       _httpClient = httpClient,
       _timeout = timeout;

  final AuthConfig _config;
  final http.Client _httpClient;
  final Duration? _timeout;

  /// Exchanges [email] + [password] for a session via
  /// POST /token?grant_type=password.
  Future<Result<SupabaseSession>> signIn({
    required String email,
    required String password,
  }) {
    return _post(
      path: 'token',
      query: {'grant_type': 'password'},
      body: {'email': email, 'password': password},
      onSuccess: _sessionFromLogin,
    );
  }

  /// Creates an account via POST /signup and returns the resulting session (or
  /// a confirmation-pending marker when the project requires email
  /// confirmation).
  Future<Result<SupabaseSession>> signUp({
    required String email,
    required String password,
    String? displayName,
  }) {
    return _post(
      path: 'signup',
      query: const {},
      body: {
        'email': email,
        'password': password,
        // GoTrue stores this under auth.users.raw_user_meta_data and mirrors
        // it into the issued JWT's `user_metadata` claim, where
        // SupabaseJwtVerifier reads it back to seed identity.users on first
        // sight. Omitted entirely (not sent as null/empty) when absent.
        if (displayName != null && displayName.trim().isNotEmpty)
          'data': {'display_name': displayName.trim()},
      },
      onSuccess: _sessionFromSignup,
    );
  }

  /// Shared request pipeline: builds the GoTrue request, applies the required
  /// apikey + JSON headers, bounds it with [_timeout], and maps the response.
  /// Never throws.
  Future<Result<SupabaseSession>> _post({
    required String path,
    required Map<String, String> query,
    required Map<String, Object?> body,
    required Result<SupabaseSession> Function(Map<String, Object?> json)
    onSuccess,
  }) async {
    final anonKey = _config.anonKey;
    if (anonKey == null) {
      // The deployment did not configure the auth proxy — fail clearly instead
      // of sending a keyless request GoTrue would reject obscurely. Not
      // retryable: this is a deployment invariant, not a transient blip.
      return const Result.err(
        AppError.invariant(
          'auth.not_configured',
          'Email/password auth is not configured on this server',
        ),
      );
    }

    final uri = _config.gotrueUri
        .resolve(path)
        .replace(queryParameters: query.isEmpty ? null : query);

    final http.Response response;
    try {
      final pending = _httpClient.post(
        uri,
        headers: {
          'apikey': anonKey,
          'authorization': 'Bearer $anonKey',
          'content-type': 'application/json',
          'accept': 'application/json',
        },
        body: jsonEncode(body),
      );
      final timeout = _timeout;
      response = timeout == null
          ? await pending
          : await pending.timeout(timeout);
    } on TimeoutException catch (cause) {
      return Result.err(
        AppError.transient(
          'auth.upstream_timeout',
          'Supabase Auth did not respond in time',
          cause,
        ),
      );
    } on Object catch (cause) {
      return Result.err(
        AppError.transient(
          'auth.upstream_unreachable',
          'Could not reach Supabase Auth',
          cause,
        ),
      );
    }

    return _dispatch(response, onSuccess);
  }

  Result<SupabaseSession> _dispatch(
    http.Response response,
    Result<SupabaseSession> Function(Map<String, Object?> json) onSuccess,
  ) {
    final status = response.statusCode;
    Map<String, Object?> json;
    try {
      final decoded = jsonDecode(response.body);
      json = decoded is Map<String, Object?> ? decoded : <String, Object?>{};
    } on Object {
      json = <String, Object?>{};
    }

    if (status >= 200 && status < 300) {
      return onSuccess(json);
    }

    // Non-2xx from GoTrue: this is a REJECTION of the submitted credentials
    // or signup payload (bad password, wrong password, already-registered
    // email, invalid email, etc.) — a validation-class, terminal outcome the
    // user must correct. This is deliberately NOT `ErrorKind.authorization`,
    // which this codebase reserves for "the caller's bearer token is
    // missing/invalid on a protected route" (see `AuthenticateRequest` /
    // `TokenVerifier`). Conflating the two collapses every distinct GoTrue
    // rejection reason into one generic "session expired" message on the
    // client (`ErrorPresenter` deliberately does not surface `message` for
    // `authorization`, since that case's cause is never useful/actionable
    // detail) and reports the wrong HTTP status (401 instead of 400) for
    // things like "email already registered". `validation` preserves
    // GoTrue's actual message end-to-end via `ErrorPresenter`.
    final message = _errorMessage(json) ?? 'Authentication failed';
    return Result.err(AppError.validation('auth.rejected', message));
  }

  /// Extracts a human-readable error message from a GoTrue error body, trying
  /// the several shapes GoTrue uses across versions.
  static String? _errorMessage(Map<String, Object?> json) {
    final msg =
        json['msg'] ??
        json['error_description'] ??
        json['error'] ??
        json['message'];
    return msg is String && msg.isNotEmpty ? msg : null;
  }

  /// Maps a GoTrue /token success body to a [SupabaseSession].
  static Result<SupabaseSession> _sessionFromLogin(Map<String, Object?> json) {
    final accessToken = json['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      return const Result.err(
        AppError.transient(
          'auth.malformed_response',
          'Supabase Auth returned no access token',
        ),
      );
    }
    final user = json['user'] as Map<String, Object?>?;
    return Result.ok(
      SupabaseSession(
        accessToken: accessToken,
        refreshToken: json['refresh_token'] as String?,
        userId: user?['id'] as String?,
        email: user?['email'] as String?,
        emailConfirmationRequired: false,
      ),
    );
  }

  /// Maps a GoTrue /signup success body to a [SupabaseSession]. On
  /// confirm-email projects GoTrue returns the user WITHOUT a session; we
  /// surface that as [SupabaseSession.emailConfirmationRequired].
  static Result<SupabaseSession> _sessionFromSignup(Map<String, Object?> json) {
    // A signup that immediately yields a session includes access_token at the
    // top level (autoconfirm projects). Otherwise the body is the user object.
    final accessToken = json['access_token'] as String?;
    if (accessToken != null && accessToken.isNotEmpty) {
      final user = json['user'] as Map<String, Object?>?;
      return Result.ok(
        SupabaseSession(
          accessToken: accessToken,
          refreshToken: json['refresh_token'] as String?,
          userId: user?['id'] as String?,
          email: user?['email'] as String?,
          emailConfirmationRequired: false,
        ),
      );
    }
    // No session: the top-level object IS the created user.
    final userId = json['id'] as String?;
    final email = json['email'] as String?;
    return Result.ok(
      SupabaseSession(
        accessToken: null,
        refreshToken: null,
        userId: userId,
        email: email,
        emailConfirmationRequired: true,
      ),
    );
  }
}
