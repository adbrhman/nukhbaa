import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/_middleware.dart' as root_middleware;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

Future<Response> _preflight(String origin) async {
  final request = _MockRequest();
  when(() => request.method).thenReturn(HttpMethod.options);
  when(() => request.headers).thenReturn(<String, String>{'origin': origin});
  final context = _MockRequestContext();
  when(() => context.request).thenReturn(request);
  final handler = root_middleware.middleware((_) => Response());
  return await handler(context);
}

void main() {
  // Without NUKHBA_CORS_ALLOWED_ORIGINS the built-in list applies; the web
  // build is served from these hosts, so each must be allowed by default.
  final environmentList =
      Platform.environment['NUKHBA_CORS_ALLOWED_ORIGINS']?.trim() ?? '';

  for (final origin in <String>[
    'https://nukhbaa.app',
    'https://www.nukhbaa.app',
    'https://p01--nukhbaa-web--42bcqlpqwp8m.code.run',
    'https://adbrhman.github.io',
  ]) {
    test(
      'the web build at $origin passes the preflight',
      () async {
        final response = await _preflight(origin);

        expect(response.statusCode, HttpStatus.noContent);
        expect(response.headers['Access-Control-Allow-Origin'], origin);
      },
      skip: environmentList.isNotEmpty,
    );
  }

  test('any other origin gets no CORS grant', () async {
    final response = await _preflight('https://nukhbaa.app.evil.example');

    expect(
      response.headers.containsKey('Access-Control-Allow-Origin'),
      isFalse,
    );
  });
}
