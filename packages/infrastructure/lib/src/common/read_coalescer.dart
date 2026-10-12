import 'dart:async';

/// Joins concurrent loads of the same key into one database read.
///
/// A cache helps only once its first load has finished. While an entry is
/// missing -- the server just started, it expired, or a write evicted it --
/// every request that arrives before the database answers would run the
/// same query on its own pool connection. On 2026-10-11 at 20:41 UTC that
/// was 150 to 180 requests queued behind the pool's 8 connections within
/// eleven seconds (`ops.error_samples`, scores and predictions routes), the
/// moment a result was scored and the scores cache dropped the fixture.
/// Run through [run], the requests that arrive while a load is in flight
/// share its answer instead of queueing a query each.
///
/// The caller puts its cache's generation in [run]'s key, so a request that
/// arrives after a write never joins a load that began before it.
///
/// In-process only, like the caches it sits behind.
final class ReadCoalescer<K, R> {
  final Map<K, Future<R>> _inFlight = <K, Future<R>>{};

  /// How many loads are in flight right now.
  int get inFlight => _inFlight.length;

  /// The load already in flight for [key], or [load] started now.
  Future<R> run(K key, Future<R> Function() load) {
    final Future<R>? pending = _inFlight[key];
    if (pending != null) {
      return pending;
    }
    final Future<R> started = load();
    _inFlight[key] = started;
    void release() {
      if (identical(_inFlight[key], started)) {
        _inFlight.remove(key);
      }
    }

    unawaited(
      started.then<void>((R _) => release(), onError: (Object _) => release()),
    );
    return started;
  }
}
