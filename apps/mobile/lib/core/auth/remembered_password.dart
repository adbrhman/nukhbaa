/// "تذكرني" (asked by the owner, 2026-11-03): a password the player chose
/// to keep on this phone, so a player who signs in again on the same phone
/// after a while and forgot it can show it from the sign-in form.
///
/// Kept in the platform secure storage (the Android keystore), one entry
/// per e-mail, so several accounts on one phone each keep their own. It
/// never leaves the phone and is never sent to the server; the web keeps
/// nothing (no secure storage there, and no phone to tie it to).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the remembered passwords are kept.
final rememberedPasswordStoreProvider = Provider<RememberedPasswordStore>(
  (ref) => const SecureRememberedPasswordStore(),
);

/// The passwords kept on this phone, by e-mail.
abstract interface class RememberedPasswordStore {
  /// The password kept for [email], or null.
  Future<String?> passwordFor(String email);

  /// Keeps [password] for [email], replacing an older one.
  Future<void> remember({required String email, required String password});

  /// Forgets the password kept for [email], if any.
  Future<void> forget(String email);
}

/// The key a password is kept under: the e-mail as the server reads it.
String rememberedEmailKey(String email) => email.trim().toLowerCase();

/// [RememberedPasswordStore] over the platform secure storage. A read that
/// fails answers null and a write that fails is dropped: remembering is a
/// convenience and never blocks signing in.
class SecureRememberedPasswordStore implements RememberedPasswordStore {
  /// Creates a store over [storage].
  const SecureRememberedPasswordStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const String _key = 'nukhba.remembered_passwords';

  final FlutterSecureStorage _storage;

  Future<Map<String, String>> _read() async {
    final String? raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return <String, String>{};
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) return <String, String>{};
    return <String, String>{
      for (final MapEntry<String, Object?> entry in decoded.entries)
        if (entry.value case final String password) entry.key: password,
    };
  }

  Future<void> _write(Map<String, String> all) => all.isEmpty
      ? _storage.delete(key: _key)
      : _storage.write(key: _key, value: jsonEncode(all));

  @override
  Future<String?> passwordFor(String email) async {
    if (kIsWeb) return null;
    try {
      return (await _read())[rememberedEmailKey(email)];
    } on Object {
      return null;
    }
  }

  @override
  Future<void> remember({
    required String email,
    required String password,
  }) async {
    if (kIsWeb) return;
    try {
      final Map<String, String> all = await _read();
      all[rememberedEmailKey(email)] = password;
      await _write(all);
    } on Object {
      // See the class comment.
    }
  }

  @override
  Future<void> forget(String email) async {
    if (kIsWeb) return;
    try {
      final Map<String, String> all = await _read();
      if (all.remove(rememberedEmailKey(email)) != null) {
        await _write(all);
      }
    } on Object {
      // See the class comment.
    }
  }
}

/// An in-memory [RememberedPasswordStore] for tests.
class InMemoryRememberedPasswordStore implements RememberedPasswordStore {
  /// Creates a store holding [initial] (e-mail to password).
  InMemoryRememberedPasswordStore([Map<String, String>? initial])
    : passwords = <String, String>{
        for (final MapEntry<String, String> entry
            in (initial ?? const <String, String>{}).entries)
          rememberedEmailKey(entry.key): entry.value,
      };

  /// What is kept, by [rememberedEmailKey].
  final Map<String, String> passwords;

  @override
  Future<String?> passwordFor(String email) async =>
      passwords[rememberedEmailKey(email)];

  @override
  Future<void> remember({
    required String email,
    required String password,
  }) async => passwords[rememberedEmailKey(email)] = password;

  @override
  Future<void> forget(String email) async =>
      passwords.remove(rememberedEmailKey(email));
}
