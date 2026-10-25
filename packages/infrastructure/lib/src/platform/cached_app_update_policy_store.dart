import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Holds the oldest supported build ([AppUpdatePolicyStore], migration
/// 0113) in the server process for [ttl] (script 148).
///
/// The build gate asks for it on every request a build sends, and
/// `GET /app/latest-build` on every launch and return to the app: one
/// query a minute at most instead. An admin's change goes through this
/// store and is held at once, so the gate and the update check follow the
/// admin's button in the same process immediately; a failed write drops
/// what is held. Concurrent reads of an expired value share one query.
///
/// Should the server ever run more than one instance, another instance
/// follows within [ttl].
final class CachedAppUpdatePolicyStore implements AppUpdatePolicyStore {
  /// Wraps [inner]; [now] is injectable for tests.
  CachedAppUpdatePolicyStore(
    this._inner, {
    Duration ttl = const Duration(seconds: 60),
    DateTime Function() now = DateTime.now,
  }) : _ttl = ttl,
       _now = now;

  final AppUpdatePolicyStore _inner;
  final Duration _ttl;
  final DateTime Function() _now;

  int? _value;
  DateTime? _heldAt;
  Future<Result<int?>>? _reading;

  @override
  Future<Result<int?>> minSupportedBuild() {
    final DateTime? heldAt = _heldAt;
    if (heldAt != null && _now().difference(heldAt) < _ttl) {
      return Future<Result<int?>>.value(Result.ok(_value));
    }
    final Future<Result<int?>>? reading = _reading;
    if (reading != null) {
      return reading;
    }
    final Future<Result<int?>> read = _read();
    _reading = read;
    return read;
  }

  Future<Result<int?>> _read() async {
    try {
      final Result<int?> result = await _inner.minSupportedBuild();
      if (result is Ok<int?>) {
        _value = result.value;
        _heldAt = _now();
      }
      return result;
    } finally {
      _reading = null;
    }
  }

  @override
  Future<Result<int?>> setMinSupportedBuild({
    required int? buildNumber,
    required UserId by,
  }) async {
    final Result<int?> result = await _inner.setMinSupportedBuild(
      buildNumber: buildNumber,
      by: by,
    );
    if (result is Ok<int?>) {
      _value = result.value;
      _heldAt = _now();
    } else {
      _heldAt = null;
    }
    return result;
  }
}
