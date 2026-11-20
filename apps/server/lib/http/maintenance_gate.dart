import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/owner_path.dart';
import 'package:shared/shared.dart';

/// What a player reads while the app is read only (script 292). Arabic,
/// so every build since 2026-10-03 shows it as it is, like the update
/// message (`build_gate.dart`).
const String readOnlyMessage =
    'نُخبة في وضع الصيانة الآن: تستطيع تصفح النتائج والترتيب، لكن حفظ '
    'التوقعات والتعديل متوقفان مؤقتاً. نقاطك وتوقعاتك محفوظة، ونعود قريباً.';

/// What a player reads while the app is closed (script 292).
const String closedMessage =
    'نُخبة متوقفة مؤقتاً للصيانة. نقاطك وتوقعاتك محفوظة، ونعود قريباً.';

/// The paths no mode closes: the health checks, the update check, signing
/// in, and the admins' and owners' pages (their own gates guard them).
bool _alwaysOpen(String path) =>
    path == '/' ||
    path == '/health' ||
    path == '/app/latest-build' ||
    path.startsWith('/auth/') ||
    path == '/admin' ||
    path.startsWith('/admin/') ||
    isOwnerPath(path);

/// The writes a read-only app still takes (decided 2026-11-19): the
/// devices, deleting an account, support, the reports the app sends by
/// itself, and marking things read.
const Set<String> _readOnlyWrites = <String>{
  '/me/device-token',
  '/me/device-token/remove',
  '/me/account',
  '/me/push-opened',
  '/me/screen-views',
  '/me/frame-report',
  '/me/time-zone',
  '/me/notification-preferences',
  '/me/h2h-league/chat/read',
  '/errors/report',
};

bool _readOnlyWrite(String path) =>
    _readOnlyWrites.contains(path) ||
    path.startsWith('/me/support/') ||
    path.startsWith('/notifications/');

// NK292_05
/// The refusal of a request in [mode], or null to serve it (script 292).
/// The admins are let through by [maintenanceGate], not here.
AppError? maintenanceRefusal({
  required AppMode mode,
  required String path,
  required HttpMethod method,
}) {
  if (mode == AppMode.normal) return null;
  final String trimmed = path.length > 1 && path.endsWith('/')
      ? path.substring(0, path.length - 1)
      : path;
  if (_alwaysOpen(trimmed)) return null;
  if (mode == AppMode.readOnly) {
    if (method == HttpMethod.get || method == HttpMethod.head) return null;
    if (_readOnlyWrite(trimmed)) return null;
    return const AppError.invariant('app.read_only', readOnlyMessage);
  }
  if (trimmed == '/me/account' && method == HttpMethod.delete) return null;
  if (trimmed == '/errors/report') return null;
  return const AppError.invariant('app.closed', closedMessage);
}

/// The app's mode, read from [AppModeStore] at most every [ttl] (script
/// 292): one read per ten seconds, not one per request. A read that fails
/// counts as normal, so a database fault never closes the app by itself.
/// [forget] after the owners change it, so this server sees it at once.
final class AppModeCache {
  /// Creates the cache over [store].
  AppModeCache(
    this._store, {
    Duration ttl = const Duration(seconds: 10),
    DateTime Function()? now,
  }) : _ttl = ttl,
       _now = now ?? DateTime.now;

  final AppModeStore _store;
  final Duration _ttl;
  final DateTime Function() _now;
  AppMode? _mode;
  DateTime? _readAt;

  /// The mode now, from the cache while it is fresh.
  Future<AppMode> current() async {
    final DateTime now = _now();
    final AppMode? kept = _mode;
    final DateTime? at = _readAt;
    if (kept != null && at != null && now.difference(at) < _ttl) return kept;
    final AppMode read = switch (await _store.read()) {
      Ok<AppModeState>(:final value) => value.mode,
      Err<AppModeState>() => AppMode.normal,
    };
    _mode = read;
    _readAt = now;
    return read;
  }

  /// Drops what is kept: the next request reads the mode again.
  void forget() {
    _mode = null;
    _readAt = null;
  }
}

/// The root middleware's gate for the app's mode (script 292): a request
/// the mode refuses is answered with its Arabic message (`409`), unless it
/// comes from an admin, who passes to test; his writes are audited as
/// always. Off while [cache] has none (no mode wired).
Middleware maintenanceGate({
  required Future<AppModeCache?> Function() cache,
  required Future<Result<AuthenticatedUser>> Function(String? header)
  authenticate,
}) {
  return (Handler handler) {
    return (RequestContext context) async {
      final AppModeCache? modes = await cache();
      if (modes == null) return handler(context);
      final AppError? refusal = maintenanceRefusal(
        mode: await modes.current(),
        path: context.request.uri.path,
        method: context.request.method,
      );
      if (refusal == null) return handler(context);
      final Result<AuthenticatedUser> who = await authenticate(
        context.request.headers[HttpHeaders.authorizationHeader],
      );
      if (who case Ok<AuthenticatedUser>(
        :final value,
      ) when value.role == PlatformRole.admin) {
        return handler(context);
      }
      return errorResponse(refusal);
    };
  };
}
