/// The cache epoch (migration 0194, script 196): how this server learns
/// that a table it holds in memory was written somewhere else.
library;

import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// The `application_name` of every session this server opens. A write from
/// any other session (the SQL Editor) moves `ops.cache_epoch`.
const String serverApplicationName = 'nukhbaa-server';

/// One reading of `ops.cache_epoch`.
final class CacheEpoch {
  /// Creates a reading.
  const CacheEpoch({required this.epoch, this.source});

  /// Moves by one with every statement made outside the server.
  final int epoch;

  /// The table and the session of the last move, or null before any.
  final String? source;
}

/// Reads the epoch.
abstract interface class CacheEpochReader {
  /// The current epoch, or null when the row is missing (0194 not applied).
  Future<Result<CacheEpoch?>> read();
}

/// [CacheEpochReader] over Postgres: one row of a one-row table.
final class PostgresCacheEpochReader implements CacheEpochReader {
  /// Reads through [_db].
  const PostgresCacheEpochReader(this._db);

  final DbExecutor _db;

  static const String _sql = '''
SELECT epoch, source FROM ops.cache_epoch WHERE id = 1
''';

  @override
  Future<Result<CacheEpoch?>> read() async {
    final result = await _db.query(_sql);
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        value.isEmpty
            ? null
            : CacheEpoch(
                epoch: switch (value.first['epoch']) {
                  final int n => n,
                  final Object other => int.tryParse(other.toString()) ?? 0,
                  null => 0,
                },
                source: value.first['source']?.toString(),
              ),
      ),
    };
  }
}

/// Drops the read caches ([_flush]) when the epoch moved since the last
/// reading. The first reading is the baseline: a server just started holds
/// nothing old. A failed reading drops nothing and keeps the baseline.
final class CacheEpochWatcher {
  /// Watches [reader]; [flush] drops every read cache.
  CacheEpochWatcher({
    required CacheEpochReader reader,
    required void Function() flush,
  }) : _reader = reader,
       _flush = flush;

  final CacheEpochReader _reader;
  final void Function() _flush;
  int? _seen;

  /// Reads the epoch; when it moved, drops the caches and says why
  /// (`epoch N: <table> by <session>`). Null when nothing was dropped.
  Future<Result<String?>> check() async {
    final result = await _reader.read();
    if (result is Err<CacheEpoch?>) {
      return Result.err(result.error);
    }
    final CacheEpoch? now = (result as Ok<CacheEpoch?>).value;
    if (now == null) {
      return const Result.ok(null);
    }
    final int? seen = _seen;
    _seen = now.epoch;
    if (seen == null || seen == now.epoch) {
      return const Result.ok(null);
    }
    _flush();
    return Result.ok('epoch ${now.epoch}: ${now.source ?? 'unknown'}');
  }
}
