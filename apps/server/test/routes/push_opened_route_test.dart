import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/me/push-opened/index.dart' as route;
import 'competition_route_harness.dart';

final class _FixedClock implements Clock {
  const _FixedClock();

  @override
  DateTime nowUtc() => DateTime.utc(2026, 9, 23, 12);
}

final class _MemoryOpens implements PushOpenRepository {
  final List<String> links = [];

  @override
  Future<Result<void>> record({
    required UserId userId,
    required String link,
    required DateTime openedAt,
  }) async {
    links.add(link);
    return const Result.ok(null);
  }
}

Future<Response> _call(_MemoryOpens opens, HttpMethod method, {Object? body}) =>
    route.onRequest(
      wireContext(
        root: CompositionRoot.forTesting(
          recordPushOpen: RecordPushOpen(
            opens: opens,
            clock: const _FixedClock(),
          ),
        ),
        principal: nonMemberPrincipal(),
        method: method,
        body: body,
      ),
    );

void main() {
  group('POST /me/push-opened', () {
    test('records a known link', () async {
      final opens = _MemoryOpens();

      final response = await _call(
        opens,
        HttpMethod.post,
        body: {'link': 'fixtures'},
      );

      expect(response.statusCode, HttpStatus.ok);
      expect((await decodeBody(response))['recorded'], true);
      expect(opens.links, ['fixtures']);
    });

    test('an unknown or missing link is 400 and nothing is kept', () async {
      final opens = _MemoryOpens();

      final unknown = await _call(
        opens,
        HttpMethod.post,
        body: {'link': 'elsewhere'},
      );
      final missing = await _call(
        opens,
        HttpMethod.post,
        body: <String, Object?>{},
      );

      expect(unknown.statusCode, HttpStatus.badRequest);
      expect(missing.statusCode, HttpStatus.badRequest);
      expect(opens.links, isEmpty);
    });
  });

  test('any other method is 405', () async {
    final response = await _call(_MemoryOpens(), HttpMethod.get);

    expect(response.statusCode, HttpStatus.methodNotAllowed);
  });
}
