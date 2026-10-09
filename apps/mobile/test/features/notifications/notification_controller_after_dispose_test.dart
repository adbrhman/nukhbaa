/// FF7T in the error log: "Cannot use the Ref of
/// notificationControllerProvider after it has been disposed", thrown from
/// `markRead` when the server's answer came back.
///
/// The controller is auto-disposed. Two ways it closes while a request is
/// out: nothing listens to it any more (the page went away), or the whole
/// container is replaced (sign-out). Either way the late answer must be
/// returned, not thrown.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/notifications/notifications_providers.dart';
import 'package:shared/shared.dart';

import '../../support/auth_harness.dart';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

void main() {
  test(
    'nothing listens any more: a slow answer is returned, not thrown',
    () async {
      final harness = buildAuthHarness((http.Request request) async {
        // Slower than one turn of the event loop, as any real network is: the
        // unlistened controller is closed before this answer lands.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final String path = request.url.path;
        if (path == '/notifications/n1/read') {
          return _json(<String, Object?>{'read': true});
        }
        if (path == '/notifications/read_all') {
          return _json(<String, Object?>{'marked': 1});
        }
        return okMe(sampleUser);
      }, seedToken: 'jwt');
      addTearDown(harness.dispose);

      final Result<bool> mark = await harness.container
          .read(notificationControllerProvider.notifier)
          .markRead('n1');
      final Result<int> markAll = await harness.container
          .read(notificationControllerProvider.notifier)
          .markAllSeen();

      expect(mark, isA<Ok<bool>>());
      expect(markAll, isA<Ok<int>>());
      expect(
        harness.captured.map((c) => c.request.url.path),
        containsAll(<String>[
          '/notifications/n1/read',
          '/notifications/read_all',
        ]),
      );
    },
  );

  test('the container is replaced (sign-out) while the mark is out', () async {
    final Completer<void> answer = Completer<void>();
    final harness = buildAuthHarness((http.Request request) async {
      await answer.future;
      if (request.url.path == '/notifications/n1/read') {
        return _json(<String, Object?>{'read': true});
      }
      return okMe(sampleUser);
    }, seedToken: 'jwt');

    final Future<Result<bool>> mark = harness.container
        .read(notificationControllerProvider.notifier)
        .markRead('n1');
    harness.dispose();
    answer.complete();

    expect(await mark, isA<Ok<bool>>());
  });
}
