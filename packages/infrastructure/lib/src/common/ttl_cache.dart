/// A small, in-process, time-boxed cache in front of a database read.
///
/// Holds successful answers only: callers never store a failure, so a
/// transient error is retried on the next read. An entry expires after [ttl],
/// and the oldest entry is dropped once [maxEntries] is reached.
///
/// [generation] moves on every eviction. A read captures it before going to
/// the database and passes it back to [write]; if a write evicted the entry
/// in between, the read's answer may predate that write and is not stored.
///
/// The cache lives in this server process only: a performance layer in front
/// of the egress-metered database, never a source of truth.
final class TtlCache<K, V extends Object> {
  /// Creates an empty cache; [now] is injectable for tests.
  TtlCache({
    required this.ttl,
    required this.maxEntries,
    DateTime Function() now = DateTime.now,
  }) : assert(maxEntries > 0, 'maxEntries must be positive'),
       _now = now;

  /// How long an entry stays valid after it is stored.
  final Duration ttl;

  /// The most entries held at once.
  final int maxEntries;

  final DateTime Function() _now;
  final Map<K, (DateTime, V)> _entries = <K, (DateTime, V)>{};
  int _generation = 0;

  /// Moves on every [remove], [clear] and [replace].
  int get generation => _generation;

  /// The live entry for [key], or `null` when absent or expired.
  V? read(K key) {
    final (DateTime, V)? hit = _entries[key];
    if (hit == null) {
      return null;
    }
    if (_now().difference(hit.$1) >= ttl) {
      _entries.remove(key);
      return null;
    }
    return hit.$2;
  }

  /// Stores [value] under [key], unless an eviction happened after
  /// [startedAt] (the [generation] captured before the load began).
  void write(K key, V value, {required int startedAt}) {
    if (startedAt != _generation) {
      return;
    }
    _store(key, value);
  }

  /// Stores [value] under [key] as the freshest answer, invalidating any
  /// load still in flight.
  void replace(K key, V value) {
    _generation++;
    _store(key, value);
  }

  /// Drops [key], invalidating any load still in flight.
  void remove(K key) {
    _generation++;
    _entries.remove(key);
  }

  /// Drops every entry, invalidating any load still in flight.
  void clear() {
    _generation++;
    _entries.clear();
  }

  void _store(K key, V value) {
    _entries.remove(key);
    while (_entries.length >= maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = (_now(), value);
  }
}
