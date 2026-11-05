import 'dart:async';

import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:postgres/postgres.dart' as pg;
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// A pool that hands a transaction out after [wait], or never when [wait] is
/// null.
final class _Pool implements pg.Pool<void> {
  _Pool({this.wait});

  final Duration? wait;

  @override
  Future<R> runTx<R>(
    Future<R> Function(pg.TxSession session) fn, {
    pg.TransactionSettings? settings,
    Object? locality,
  }) async {
    final Duration? delay = wait;
    if (delay == null) return Completer<R>().future;
    await Future<void>.delayed(delay);
    return fn(const _Tx());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Tx implements pg.TxSession {
  const _Tx();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 96WW: a transaction waited for a pool connection with no limit, so a
/// prediction save outlived the app's own 35 s timeout.
void main() {
  const Duration wait = Duration(milliseconds: 100);

  test(
    'a transaction that never gets a connection gives up and says so',
    () async {
      var ran = false;
      final PostgresConnection db = PostgresConnection.withPoolForTest(
        _Pool(),
        connectionWait: wait,
      );

      final Result<int> result = await db.runInTransaction<int>((tx) async {
        ran = true;
        return const Result.ok(1);
      });

      final AppError error = (result as Err<int>).error;
      expect(error.code, 'db.tx_connection_timeout');
      expect(error.kind, ErrorKind.transient);
      expect(error.message, contains('connections in use 0/8, waiting 1'));
      expect(ran, isFalse);
    },
  );

  test(
    'a connection that arrives after the caller gave up runs nothing',
    () async {
      var ran = false;
      final PostgresConnection db = PostgresConnection.withPoolForTest(
        _Pool(wait: const Duration(milliseconds: 300)),
        connectionWait: wait,
      );

      final Result<int> result = await db.runInTransaction<int>((tx) async {
        ran = true;
        return const Result.ok(1);
      });
      expect(result, isA<Err<int>>());

      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(ran, isFalse);
    },
  );

  test(
    'a transaction that gets its connection in time runs and returns',
    () async {
      var ran = false;
      final PostgresConnection db = PostgresConnection.withPoolForTest(
        _Pool(wait: const Duration(milliseconds: 10)),
        connectionWait: wait,
      );

      final Result<int> result = await db.runInTransaction<int>((tx) async {
        ran = true;
        return const Result.ok(7);
      });

      expect((result as Ok<int>).value, 7);
      expect(ran, isTrue);
    },
  );

  test('an Err from the work still comes back unchanged', () async {
    final PostgresConnection db = PostgresConnection.withPoolForTest(
      _Pool(wait: const Duration(milliseconds: 10)),
      connectionWait: wait,
    );

    final Result<int> result = await db.runInTransaction<int>(
      (tx) async => const Result.err(AppError.validation('x.bad', 'no')),
    );

    expect((result as Err<int>).error.code, 'x.bad');
  });
}
