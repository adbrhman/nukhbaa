import 'dart:convert';
import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/build_gate.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/_middleware.dart' as root_middleware;

/// Script 142: once `NUKHBA_BUILD_HEADER_SINCE` is set, a request from a
/// build too old to be served is answered with the Arabic update message
/// before it reaches any route; the root middleware wires the gate.

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

RequestContext _context(String path, Map<String, String> headers) {
  final request = _MockRequest();
  when(() => request.method).thenReturn(HttpMethod.get);
  when(() => request.uri).thenReturn(Uri.parse('https://api.test$path'));
  when(() => request.headers).thenReturn(headers);
  final context = _MockRequestContext();
  when(() => context.request).thenReturn(request);
  // The root middleware provides the composition root; nothing here reads it.
  when(
    () => context.provide<Future<CompositionRoot>>(any()),
  ).thenReturn(context);
  return context;
}

/// The route behind the gate, counting the requests that reach it.
final class _Route {
  int reached = 0;

  Response call(RequestContext context) {
    reached++;
    return Response(body: 'served');
  }
}

Future<Response> _through(
  int? minBuild,
  _Route route,
  String path, [
  Map<String, String> headers = const <String, String>{},
]) async =>
    await buildGate(minBuild: minBuild)(route.call)(_context(path, headers));

void main() {
  setUpAll(() {
    registerFallbackValue(CompositionRoot.instance);
  });

  test('the root middleware lets a build with no header through while '
      'NUKHBA_BUILD_HEADER_SINCE is not set', () async {
    final route = _Route();
    final handler = root_middleware.middleware(route.call);

    final Response response = await handler(
      _context('/me/fixture-predictions', const <String, String>{}),
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(route.reached, 1);
  }, skip: minServedBuild(Platform.environment) != null);

  test('a build with no header is refused with the Arabic message, as a 409 '
      'envelope every build since 2026-10-03 shows', () async {
    final route = _Route();

    final Response response = await _through(775, route, '/me/active-seasons');

    expect(response.statusCode, HttpStatus.conflict);
    final ErrorResponseDto body = ErrorResponseDto.fromJson(
      jsonDecode(await response.body()) as Map<String, Object?>,
    );
    expect(body.code, 'app.update_required');
    expect(body.message, oldBuildMessage);
    expect(body.message, contains('links.nukhbaa.app'));
    // The old app's own buttons, as its screens spell them (script 143).
    expect(body.message, contains('«تسجيل الدخول بحساب آخر»'));
    expect(body.message, contains('«يتوفر تحديث جديد»'));
    expect(RegExp('[؀-ۿ]').hasMatch(body.message), isTrue);
    expect(route.reached, 0);
  });

  test('a build older than the minimum is refused; that build and newer ones '
      'are served', () async {
    final route = _Route();

    final Response older = await _through(775, route, '/feed', {
      appBuildHeader: '774',
    });
    final Response same = await _through(775, route, '/feed', {
      appBuildHeader: '775',
    });
    final Response newer = await _through(775, route, '/feed', {
      appBuildHeader: '790',
    });

    expect(older.statusCode, HttpStatus.conflict);
    expect(same.statusCode, HttpStatus.ok);
    expect(newer.statusCode, HttpStatus.ok);
    expect(route.reached, 2);
  });

  test('the update check, the health checks, the web build and a local run '
      'always pass', () async {
    final route = _Route();

    for (final String path in <String>['/app/latest-build', '/health', '/']) {
      expect((await _through(775, route, path)).statusCode, HttpStatus.ok);
    }
    expect(
      (await _through(775, route, '/feed', {
        'origin': 'https://nukhbaa.app',
      })).statusCode,
      HttpStatus.ok,
    );
    expect(
      (await _through(775, route, '/feed', {appBuildHeader: '0'})).statusCode,
      HttpStatus.ok,
    );
    expect(route.reached, 5);
  });

  test('the gate is off without the variable, or with a value that is not a '
      'build number', () async {
    final route = _Route();
    for (final Map<String, String> environment in <Map<String, String>>[
      const <String, String>{},
      const <String, String>{'NUKHBA_BUILD_HEADER_SINCE': ''},
      const <String, String>{'NUKHBA_BUILD_HEADER_SINCE': 'soon'},
      const <String, String>{'NUKHBA_BUILD_HEADER_SINCE': '0'},
    ]) {
      final int? minBuild = minServedBuild(environment);
      expect(minBuild, isNull);
      expect(
        (await _through(minBuild, route, '/feed')).statusCode,
        HttpStatus.ok,
      );
    }
    expect(
      minServedBuild(const <String, String>{
        'NUKHBA_BUILD_HEADER_SINCE': ' 775 ',
      }),
      775,
    );
  });
}
