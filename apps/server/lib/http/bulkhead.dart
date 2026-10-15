import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/http/request_scope.dart';

/// At most [limit] requests of one route at once in this process (batch
/// 156). The rest are answered at once with `503 server.busy` instead of
/// queueing for the database: the server holds a few connections, and a
/// route that apps fan out over (one request per match) could take all of
/// them while every other screen waited ten seconds and failed (2026-10-16:
/// "connections in use 8/8, waiting 89").
final class Bulkhead {
  /// Creates a bulkhead of [limit] places.
  Bulkhead(this.limit) : assert(limit > 0, 'a bulkhead needs a place');

  /// How many requests may run at once.
  final int limit;

  int _running = 0;

  /// The requests running now.
  int get running => _running;

  /// The stable code of the answer to a request that found no free place.
  static const String busyCode = 'server.busy';

  /// Runs [handle] in a free place, or answers `503` [busyCode] with no
  /// wait when every place is taken. The place is freed however [handle]
  /// ends. A refusal is the bulkhead working, not a fault: it marks the
  /// request [RequestScope.shed], so it is not put in the error log.
  Future<Response> run(Future<Response> Function() handle) async {
    if (_running >= limit) {
      RequestScope.current?.shed = true;
      return Response.json(
        statusCode: HttpStatus.serviceUnavailable,
        body: const ErrorResponseDto(
          code: busyCode,
          message: 'الخادم مشغول الآن. حاول بعد قليل.',
        ).toJson(),
      );
    }
    _running++;
    try {
      return await handle();
    } finally {
      _running--;
    }
  }
}
