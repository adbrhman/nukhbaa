library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final themePreferenceStoreProvider = Provider<ThemePreferenceStore>(
  (ref) => const SecureThemePreferenceStore(),
);

abstract interface class ThemePreferenceStore {
  Future<ThemeMode> read();
  Future<void> write(ThemeMode mode);
}

class SecureThemePreferenceStore implements ThemePreferenceStore {
  const SecureThemePreferenceStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const String _key = 'nukhba.themeMode';
  final FlutterSecureStorage _storage;

  @override
  Future<ThemeMode> read() async {
    final String? raw = await _storage.read(key: _key);
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  @override
  Future<void> write(ThemeMode mode) =>
      _storage.write(key: _key, value: mode.name);
}

class InMemoryThemePreferenceStore implements ThemePreferenceStore {
  InMemoryThemePreferenceStore([this._mode = ThemeMode.system]);
  ThemeMode _mode;

  @override
  Future<ThemeMode> read() async => _mode;

  @override
  Future<void> write(ThemeMode mode) async => _mode = mode;
}

class ThemeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _hydrate();
    return ThemeMode.system;
  }

  Future<void> _hydrate() async {
    final ThemeMode stored = await ref
        .read(themePreferenceStoreProvider)
        .read();
    if (stored != state) state = stored;
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == state) return;
    state = mode;
    await ref.read(themePreferenceStoreProvider).write(mode);
  }

  Future<void> toggle() =>
      setMode(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
}

final themeControllerProvider = NotifierProvider<ThemeController, ThemeMode>(
  ThemeController.new,
);
