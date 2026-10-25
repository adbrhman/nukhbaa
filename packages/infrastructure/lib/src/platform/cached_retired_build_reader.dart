import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Holds the players on a retired build ([RetiredBuildReader], script 149)
/// in the server process for [ttl].
///
/// It is asked only while an admin holds a minimum, and only for a request
/// that names no build: a few dozen players, read once every [ttl] at most
/// instead of on every request. A player who updates is never refused
/// meanwhile -- the new build names itself -- and leaves the list at the
/// next read. Concurrent reads of an expired list share one query; a failed
/// read is not held.
final class CachedRetiredBuildReader implements RetiredBuildReader {
  /// Wraps [inner]; [now] is injectable for tests.
  CachedRetiredBuildReader(
    this._inner, {
    Duration ttl = const Duration(minutes: 10),
    DateTime Function() now = DateTime.now,
  }) : _ttl = ttl,
       _now = now;

  final RetiredBuildReader _inner;
  final Duration _ttl;
  final DateTime Function() _now;

  DateTime? _before;
  Set<UserId> _players = const <UserId>{};
  DateTime? _heldAt;
  Future<Result<Set<UserId>>>? _reading;

  @override
  Future<Result<Set<UserId>>> playersOnBuildsBefore(DateTime before) {
    final DateTime? heldAt = _heldAt;
    if (heldAt != null &&
        _before == before &&
        _now().difference(heldAt) < _ttl) {
      return Future<Result<Set<UserId>>>.value(Result.ok(_players));
    }
    final Future<Result<Set<UserId>>>? reading = _reading;
    if (reading != null && _before == before) {
      return reading;
    }
    _before = before;
    final Future<Result<Set<UserId>>> read = _read(before);
    _reading = read;
    return read;
  }

  Future<Result<Set<UserId>>> _read(DateTime before) async {
    try {
      final Result<Set<UserId>> result = await _inner.playersOnBuildsBefore(
        before,
      );
      if (result is Ok<Set<UserId>>) {
        _players = result.value;
        _heldAt = _now();
      }
      return result;
    } finally {
      _reading = null;
    }
  }
}
