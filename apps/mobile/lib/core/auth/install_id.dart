/// A random id for this app install, kept in the secure store (migration
/// 0073). It travels with the crash reports only, so the server can limit
/// how often one device reports (the invitations it was made for were
/// removed on 2026-10-26). Clearing the app's data makes a new one.
library;

import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Reads this install's id, creating it on first use.
abstract interface class InstallIdStore {
  /// The id, or null when the secure store cannot be read.
  Future<String?> read();
}

/// [InstallIdStore] over the platform's secure store.
final class SecureInstallIdStore implements InstallIdStore {
  /// Creates the store over [storage].
  SecureInstallIdStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;
  String? _cached;

  /// The secure-store key.
  static const String key = 'nukhba.install_id';

  @override
  Future<String?> read() async {
    final String? cached = _cached;
    if (cached != null) {
      return cached;
    }
    try {
      final String? stored = await _storage.read(key: key);
      if (stored != null && stored.isNotEmpty) {
        _cached = stored;
        return stored;
      }
      final String fresh = newInstallId(Random.secure());
      await _storage.write(key: key, value: fresh);
      _cached = fresh;
      return fresh;
    } on Object {
      // No id is a complete answer: the report still goes through, it is
      // only limited by account instead.
      return null;
    }
  }
}

/// A fixed id, for tests and previews.
final class FixedInstallIdStore implements InstallIdStore {
  /// Creates the store answering [id].
  const FixedInstallIdStore(this.id);

  /// The id every read answers.
  final String? id;

  @override
  Future<String?> read() async => id;
}

/// A new install id: 32 random hex digits in the 8-4-4-4-12 shape.
String newInstallId(Random random) {
  const String hex = '0123456789abcdef';
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < 32; i++) {
    if (i == 8 || i == 12 || i == 16 || i == 20) {
      out.write('-');
    }
    out.write(hex[random.nextInt(16)]);
  }
  return out.toString();
}
