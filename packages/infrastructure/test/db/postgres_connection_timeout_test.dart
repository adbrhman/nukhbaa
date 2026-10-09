/// A query that times out says where its time went: waiting for one of the
/// pool's connections, or running on one, with how busy the pool was.
///
/// The night of 2026-10-06 logged an hour of `db.query_timeout` on five
/// routes, while `pg_stat_statements` held no query slower than about two
/// seconds since July. The message now tells the next one apart.
library;

import 'dart:async';

import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:postgres/postgres.dart' as pg;
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// A pool that hands out a connection after [wait], or never when [wait]
/// is null. The connection never answers.
final class _Pool implements pg.Pool<void> {
  _Pool({this.wait});

  final Duration? wait;

  @override
  Future<R> withConnection<R>(
    Future<R> Function(pg.Connection connection) fn, {
    pg.ConnectionSettings? settings,
    Object? locality,
  }) async {
    final Duration? delay = wait;
    if (delay == null) return Completer<R>().future;
    await Future<void>.delayed(delay);
    return fn(const _SilentConnection());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A connection whose queries never come back.
final class _SilentConnection implements pg.Connection {
  const _SilentConnection();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      invocation.memberName == #execute
      ? Completer<pg.Result>().future
      : super.noSuchMethod(invocation);
}

AppError _errorOf(Result<List<Map<String, dynamic>>> result) =>
    (result as Err<List<Map<String, dynamic>>>).error;

void main() {
  const Duration timeout = Duration(milliseconds: 200);

  test('a query that never got a connection says so', () async {
    final PostgresConnection db = PostgresConnection.withPoolForTest(
      _Pool(),
      timeout: timeout,
    );

    final AppError error = _errorOf(await db.query('SELECT 1'));

    expect(error.code, 'db.query_timeout');
    expect(error.message, contains('still waiting for a connection after'));
    expect(error.message, contains('connections in use 0/8, waiting 1'));
  });

  test('a query that got a connection and ran out of time says that', () async {
    final PostgresConnection db = PostgresConnection.withPoolForTest(
      _Pool(wait: const Duration(milliseconds: 50)),
      timeout: timeout,
    );

    final AppError error = _errorOf(await db.query('SELECT 1'));

    expect(error.code, 'db.query_timeout');
    expect(error.message, matches(RegExp(r'waited 0\.\ds for a connection')));
    expect(error.message, matches(RegExp(r'ran 0\.\ds')));
    expect(error.message, contains('connections in use 1/8, waiting 0'));
  });
}
