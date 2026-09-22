/// Device-side pieces of fingerprint unlock: whether the user switched it
/// on, and the platform prompt itself.
///
/// Nothing here holds a credential. The session lives in the [TokenStore]
/// and renews itself through the refresh token; the fingerprint only decides
/// whether this app opens straight onto that session.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Where the user's fingerprint-unlock choice is kept.
final biometricPreferenceStoreProvider = Provider<BiometricPreferenceStore>(
  (ref) => const SecureBiometricPreferenceStore(),
);

/// The platform fingerprint prompt.
final biometricAuthenticatorProvider = Provider<BiometricAuthenticator>(
  (ref) => LocalBiometricAuthenticator(),
);

/// Whether fingerprint unlock is on, and whether it was already offered.
abstract interface class BiometricPreferenceStore {
  /// Whether the user switched fingerprint unlock on.
  Future<bool> isEnabled();

  /// Records the user's choice.
  Future<void> setEnabled({required bool enabled});

  /// Whether the one-time offer after sign-in was already shown.
  Future<bool> wasOffered();

  /// Records that the one-time offer was shown.
  Future<void> markOffered();
}

/// [BiometricPreferenceStore] over the platform secure storage.
class SecureBiometricPreferenceStore implements BiometricPreferenceStore {
  /// Creates a store over [storage].
  const SecureBiometricPreferenceStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const String _enabledKey = 'nukhba.biometric.enabled';
  static const String _offeredKey = 'nukhba.biometric.offered';

  final FlutterSecureStorage _storage;

  @override
  Future<bool> isEnabled() async =>
      await _storage.read(key: _enabledKey) == 'true';

  @override
  Future<void> setEnabled({required bool enabled}) =>
      _storage.write(key: _enabledKey, value: enabled ? 'true' : 'false');

  @override
  Future<bool> wasOffered() async =>
      await _storage.read(key: _offeredKey) == 'true';

  @override
  Future<void> markOffered() => _storage.write(key: _offeredKey, value: 'true');
}

/// An in-memory [BiometricPreferenceStore] for tests.
class InMemoryBiometricPreferenceStore implements BiometricPreferenceStore {
  /// Creates a store, optionally already [enabled].
  InMemoryBiometricPreferenceStore({bool enabled = false, bool offered = false})
    : _enabled = enabled,
      _offered = offered;

  bool _enabled;
  bool _offered;

  @override
  Future<bool> isEnabled() async => _enabled;

  @override
  Future<void> setEnabled({required bool enabled}) async => _enabled = enabled;

  @override
  Future<bool> wasOffered() async => _offered;

  @override
  Future<void> markOffered() async => _offered = true;
}

/// The fingerprint prompt, behind a seam so screens can be tested.
abstract interface class BiometricAuthenticator {
  /// Whether this device has a fingerprint (or face) enrolled and usable.
  Future<bool> isAvailable();

  /// Shows the system prompt with [reason]; true when the user passed it.
  Future<bool> authenticate({required String reason});
}

/// [BiometricAuthenticator] over `local_auth`. Never throws: a missing
/// sensor, a lockout or the web build all read as "not available" or "not
/// passed", and the caller falls back to the password.
class LocalBiometricAuthenticator implements BiometricAuthenticator {
  /// Creates an authenticator over [auth].
  LocalBiometricAuthenticator([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    try {
      if (!await _auth.canCheckBiometrics) return false;
      final List<BiometricType> enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> authenticate({required String reason}) async {
    if (kIsWeb) return false;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on Object {
      return false;
    }
  }
}
