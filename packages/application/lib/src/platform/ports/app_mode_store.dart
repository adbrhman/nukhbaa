import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

// NK292_01
/// The whole app's mode, in the owners' hands (script 292, migration 0222,
/// item 1 of the owner's report).
enum AppMode {
  /// Everything works.
  normal('normal'),

  /// The players browse; their writes are refused, but signing in, the
  /// devices, support and deleting an account (decided 2026-11-19).
  readOnly('read_only'),

  /// Only signing in, deleting an account and the admins.
  closed('closed');

  const AppMode(this.wire);

  /// Its value in `ops.app_mode.mode` and on the wire.
  final String wire;

  /// The mode whose [wire] is [value], or null.
  static AppMode? byWire(String value) {
    for (final AppMode mode in values) {
      if (mode.wire == value) return mode;
    }
    return null;
  }
}

/// The app's mode as it stands, and its last change.
final class AppModeState {
  /// Creates the state.
  const AppModeState({
    required this.mode,
    required this.changedAt,
    this.reason,
    this.changedBy,
  });

  /// The mode.
  final AppMode mode;

  /// Why it was last changed; null before any change.
  final String? reason;

  /// The owner seat who changed it; null before any change, or from the
  /// SQL editor.
  final UserId? changedBy;

  /// When it was last changed (UTC).
  final DateTime changedAt;
}

/// Persistence port for the app's mode (`ops.app_mode`, migration 0222).
/// MUST NOT throw; an infrastructure failure is transient.
abstract interface class AppModeStore {
  /// The mode now.
  Future<Result<AppModeState>> read();

  /// Sets [mode] for [reason], by the owner seat [by].
  Future<Result<void>> set({
    required AppMode mode,
    required String reason,
    required UserId by,
  });
}
