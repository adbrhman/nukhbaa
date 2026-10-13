/// The client-side home of the Supabase access token.
///
/// `api_client` is deliberately token-agnostic (its [TokenProvider] just asks
/// "what is the current bearer token?"); the app owns *where* that token lives.
/// This is the seam: a small async key-value contract for the one credential
/// the client holds, with a platform-secure implementation and an in-memory
/// fake for tests.
///
/// It stores/loads only the opaque token string — it never verifies, decodes,
/// or refreshes it (that is the identity provider's concern; the server
/// verifies every token per Security ADR §2).
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A minimal async store for the single bearer credential.
///
/// Every method is total in the sense that it completes with a value or throws
/// only on a genuine platform-storage failure; callers treat a thrown read as
/// "no token" (see [SecureTokenStore.read]).
abstract interface class TokenStore {
  /// Returns the persisted access token, or `null` if none is stored.
  Future<String?> read();

  /// Persists [token] as the current access token, replacing any previous one.
  Future<void> write(String token);

  /// Returns the persisted refresh token, or `null` if none is stored.
  Future<String?> readRefreshToken();

  /// Persists [token] as the refresh token that renews the session.
  Future<void> writeRefreshToken(String token);

  /// Returns the profile last confirmed by `GET /me` (its JSON), or `null`.
  /// Lets a launch open the app at once while `/me` is asked again in the
  /// background (audit M-04).
  Future<String?> readProfile();

  /// Remembers the profile `GET /me` just confirmed (its JSON).
  Future<void> writeProfile(String json);

  /// Removes the persisted access and refresh tokens and the remembered
  /// profile (sign-out).
  Future<void> clear();
}

/// Platform-secure [TokenStore] backed by `flutter_secure_storage`
/// (Keychain on iOS, Keystore/EncryptedSharedPreferences on Android, a
/// WebCrypto-backed store on web).
final class SecureTokenStore implements TokenStore {
  /// Creates a secure store over [storage].
  SecureTokenStore(this._storage);

  final FlutterSecureStorage _storage;

  /// PERF: the transport asks for the token on EVERY request, and a keystore
  /// read is a platform-channel round trip with a decrypt behind it -- a
  /// screen issuing twenty requests paid twenty of them on the UI isolate.
  /// The token only ever changes through [write]/[clear] on this same
  /// instance (the app holds exactly one, from `core/providers.dart`), so
  /// the value is cached after the first read and every later read is a
  /// field access. [_loaded] is separate from [_cached] because "no token
  /// stored" is itself an answer worth caching.
  String? _cached;
  bool _loaded = false;

  /// The storage key under which the access token is persisted.
  static const String tokenKey = 'nukhba.access_token';

  /// The storage key under which the refresh token is persisted.
  static const String refreshTokenKey = 'nukhba.refresh_token';

  /// The storage key under which the last confirmed profile is persisted.
  static const String profileKey = 'nukhba.profile';

  @override
  Future<String?> read() async {
    // A read failure (e.g. a corrupted keystore entry) is treated as "no
    // token" rather than crashing the app on boot — the user is simply asked
    // to sign in again. The failure is not swallowed silently in higher
    // layers: an absent token routes to the sign-in screen.
    if (_loaded) return _cached;
    try {
      _cached = await _storage.read(key: tokenKey);
    } on Object {
      _cached = null;
    }
    _loaded = true;
    return _cached;
  }

  @override
  Future<void> write(String token) {
    _cached = token;
    _loaded = true;
    return _storage.write(key: tokenKey, value: token);
  }

  // Read only when a renewal runs, so not cached: a keystore read there
  // costs nothing next to the network round trip that follows.
  @override
  Future<String?> readRefreshToken() async {
    try {
      return await _storage.read(key: refreshTokenKey);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> writeRefreshToken(String token) =>
      _storage.write(key: refreshTokenKey, value: token);

  // Read once per launch, so not cached either.
  @override
  Future<String?> readProfile() async {
    try {
      return await _storage.read(key: profileKey);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> writeProfile(String json) =>
      _storage.write(key: profileKey, value: json);

  @override
  Future<void> clear() async {
    _cached = null;
    _loaded = true;
    await _storage.delete(key: tokenKey);
    await _storage.delete(key: refreshTokenKey);
    await _storage.delete(key: profileKey);
  }
}

/// An in-memory [TokenStore] for tests and for a transient web session where
/// no persistence is desired. Not used by the production wiring.
final class InMemoryTokenStore implements TokenStore {
  /// Creates an in-memory store, optionally seeded with an existing [token].
  InMemoryTokenStore([this._token]);

  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  String? _refreshToken;

  @override
  Future<String?> readRefreshToken() async => _refreshToken;

  @override
  Future<void> writeRefreshToken(String token) async => _refreshToken = token;

  String? _profile;

  @override
  Future<String?> readProfile() async => _profile;

  @override
  Future<void> writeProfile(String json) async => _profile = json;

  @override
  Future<void> clear() async {
    _token = null;
    _refreshToken = null;
    _profile = null;
  }
}
