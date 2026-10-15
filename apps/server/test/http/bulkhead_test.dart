import 'dart:async';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/http/bulkhead.dart';
import 'package:server/http/request_scope.dart';
import 'package:test/test.dart';

/// A route's places (batch 156): the ones beyond the limit are answered at
/// once with 503, and a place is freed when its request ends, failed or not.
void main() {
  test('beyond the limit: 503 server.busy at once; a freed place takes the '
      'next', () async {
    final Bulkhead bulkhead = Bulkhead(2);
    final Completer<Response> first = Completer<Response>();
    final Completer<Response> second = Completer<Response>();

    final Future<Response> a = bulkhead.run(() => first.future);
    final Future<Response> b = bulkhead.run(() => second.future);
    expect(bulkhead.running, 2);

    final Response refused = await bulkhead.run(
      () async => Response(body: 'ran'),
    );
    expect(refused.statusCode, HttpStatus.serviceUnavailable);
    expect(await refused.body(), contains('server.busy'));

    first.complete(Response(body: 'a'));
    expect((await a).statusCode, HttpStatus.ok);
    expect(bulkhead.running, 1);

    final Response next = await bulkhead.run(() async => Response(body: 'ran'));
    expect(await next.body(), 'ran');

    second.complete(Response(body: 'b'));
    await b;
    expect(bulkhead.running, 0);
  });

  test('a refusal marks its request shed; a request that ran is not '
      '(batch 157)', () async {
    final Bulkhead bulkhead = Bulkhead(1);
    final Completer<Response> held = Completer<Response>();
    final RequestScope running = RequestScope('a');
    final RequestScope refused = RequestScope('b');

    final Future<Response> first = running.run(
      () => bulkhead.run(() => held.future),
    );
    final Response busy = await refused.run(
      () => bulkhead.run(() async => Response(body: 'ran')),
    );

    expect(busy.statusCode, HttpStatus.serviceUnavailable);
    expect(refused.shed, isTrue);
    held.complete(Response(body: 'a'));
    await first;
    expect(running.shed, isFalse);
  });

  test('a request that throws frees its place', () async {
    final Bulkhead bulkhead = Bulkhead(1);

    await expectLater(
      bulkhead.run(() async => throw StateError('boom')),
      throwsStateError,
    );

    expect(bulkhead.running, 0);
  });
}
