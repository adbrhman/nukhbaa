/// The players this phone's owner blocked (script 225).
///
/// Google Play's user-generated-content policy asks for an in-app way to
/// report and to block objectionable users. Blocking here is a choice of
/// what this phone shows: a blocked player's name and picture are replaced
/// by [blockedPlayerLabel] on the boards, and the list can be emptied from
/// the settings. It is kept on the phone (the platform secure storage), by
/// the name as it is written, so a player blocked in one season stays
/// blocked in the next; it never leaves the phone.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// What a blocked player's name is replaced by.
const String blockedPlayerLabel = 'لاعب محظور';

String _tidy(String displayName) =>
    displayName.trim().replaceAll(RegExp(r'\s+'), ' ');

/// The key a player is blocked under: the name, tidied and lower-cased.
String blockKeyOf(String displayName) => _tidy(displayName).toLowerCase();

/// Where the blocked players are kept: key to the name as it was written.
abstract interface class BlockedPlayersStore {
  /// What is kept; empty when nothing is, or when it cannot be read.
  Future<Map<String, String>> load();

  /// Keeps [blocked], replacing what was kept.
  Future<void> save(Map<String, String> blocked);
}

/// Where the blocked players are kept on this phone.
final Provider<BlockedPlayersStore> blockedPlayersStoreProvider =
    Provider<BlockedPlayersStore>((ref) => const SecureBlockedPlayersStore());

/// [BlockedPlayersStore] over the platform secure storage. A read that fails
/// answers nothing and a write that fails is dropped: the choice still
/// holds until the app closes, and it never blocks a screen.
class SecureBlockedPlayersStore implements BlockedPlayersStore {
  /// Creates a store over [storage].
  const SecureBlockedPlayersStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const String _key = 'nukhba.blocked_players';

  final FlutterSecureStorage _storage;

  @override
  Future<Map<String, String>> load() async {
    if (kIsWeb) return <String, String>{};
    try {
      final String? raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return <String, String>{};
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return <String, String>{};
      return <String, String>{
        for (final MapEntry<String, Object?> entry in decoded.entries)
          if (entry.value case final String name) entry.key: name,
      };
    } on Object {
      return <String, String>{};
    }
  }

  @override
  Future<void> save(Map<String, String> blocked) async {
    if (kIsWeb) return;
    try {
      if (blocked.isEmpty) {
        await _storage.delete(key: _key);
      } else {
        await _storage.write(key: _key, value: jsonEncode(blocked));
      }
    } on Object {
      // See the class comment.
    }
  }
}

/// An in-memory [BlockedPlayersStore] for tests.
class InMemoryBlockedPlayersStore implements BlockedPlayersStore {
  /// Creates a store holding [initial].
  InMemoryBlockedPlayersStore([Map<String, String>? initial])
    : blocked = <String, String>{...?initial};

  /// What is kept.
  Map<String, String> blocked;

  @override
  Future<Map<String, String>> load() async => <String, String>{...blocked};

  @override
  Future<void> save(Map<String, String> blocked) async {
    this.blocked = <String, String>{...blocked};
  }
}

/// The blocked players: [blockKeyOf] to the name as it was written.
class BlockedPlayers extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() {
    unawaited(_restore());
    return const <String, String>{};
  }

  Future<void> _restore() async {
    final Map<String, String> kept = await ref
        .read(blockedPlayersStoreProvider)
        .load();
    if (!ref.mounted || kept.isEmpty) return;
    state = <String, String>{...kept, ...state};
  }

  /// Blocks the player called [displayName].
  Future<void> block(String displayName) async {
    final String key = blockKeyOf(displayName);
    if (key.isEmpty) return;
    state = <String, String>{...state, key: _tidy(displayName)};
    await ref.read(blockedPlayersStoreProvider).save(state);
  }

  /// Lifts the block kept under [key].
  Future<void> unblock(String key) async {
    if (!state.containsKey(key)) return;
    state = <String, String>{...state}..remove(key);
    await ref.read(blockedPlayersStoreProvider).save(state);
  }
}

/// The blocked players of this phone.
final NotifierProvider<BlockedPlayers, Map<String, String>>
blockedPlayersProvider = NotifierProvider<BlockedPlayers, Map<String, String>>(
  BlockedPlayers.new,
);
