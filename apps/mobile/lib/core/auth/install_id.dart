/// A random id for this app install, kept in the secure store (migration
/// 0073). It travels with the invitation requests so the server can hold an
/// invitation whose invitee is on the inviter's own install for review; the
/// server stores it only hashed. Clearing the app's data makes a new one,
/// which is why it is a signal for a human, never proof on its own.
library;

import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      // No id is a complete answer: the invitation still goes through, it
      // only carries one signal fewer.
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

/// This install's id store. The web build has none (migration 0086): a
/// browser cannot be told apart from the phone it runs on, so an
/// invitation claimed there is refused as `app_required` and the player
/// is told to use the app.
final installIdStoreProvider = Provider<InstallIdStore>(
  (ref) => kIsWeb ? const FixedInstallIdStore(null) : SecureInstallIdStore(),
);
